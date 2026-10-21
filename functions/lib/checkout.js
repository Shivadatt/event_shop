'use strict';

// The order/coupon/shipping DECISIONS, extracted from index.js so they are testable with plain Node
// (`node --test test/`) — no emulator, no Admin SDK, no deployed backend.
//
// Nothing in this file throws or touches Firestore: each helper returns a value and index.js turns
// a rejected value into the HttpsError code the Dart repository maps. Money is integer paise.
//
// COVERAGE, stated honestly: the rules below are pinned by `functions/test/coupon_windows.test.js`,
// `shipping_serviceability.test.js` and `price_rounding.test.js`, which run these helpers AND the real
// callables. The Dart client has its own copies (lib/data/models/coupon.dart, lib/data/models/
// store_settings.dart and the checkout controller). Only the PRICING engine is fixture-pinned on both
// sides (`test/data/slab_fixtures.json` — `priceCases`, `gridCases`, `taxCases`); that file has no
// `couponCases` or `shippingCases`, so coupon and shipping parity between Dart and Node is UNVERIFIED
// until such cases exist. If a rule here changes, add the fixture cases and mirror the Dart side in the
// same commit, or the checkout estimate starts lying to buyers about what `ordersCreate` will charge.

const { toInt, toMillis } = require('./coerce');

// ---- coupon ------------------------------------------------------------------------------------

const COUPON_INVALID = 'This code is no longer valid.';
const COUPON_WHOLESALE = 'This code cannot be combined with wholesale pricing.';
const COUPON_MIN_QTY = (minQty) => `Minimum quantity ${minQty} required.`;
const COUPON_MIN_CART = 'Add items worth more to use this code.';

// Mirrors Dart Coupon.redeemableAt(). Every window bound goes through toMillis: a Timestamp is an
// OBJECT, so `now < startsAt` with a raw object compares against NaN and silently passes — an
// expired or not-yet-started coupon would discount. Read the instant, then compare.
function couponIsRedeemable(coupon, now) {
  if (!coupon || coupon.isActive === false) return false;
  const usageLimit = coupon.usageLimit;
  if (usageLimit != null && toInt(coupon.usedCount) >= toInt(usageLimit)) return false;
  const at = toMillis(now) ?? Date.now();
  const startsAt = toMillis(coupon.startsAt);
  const endsAt = toMillis(coupon.endsAt);
  if (startsAt != null && at < startsAt) return false;
  if (endsAt != null && at > endsAt) return false;
  return true;
}

function couponHasScope(coupon) {
  const cats = Array.isArray(coupon.appliesToCategoryIds) ? coupon.appliesToCategoryIds : [];
  const prods = Array.isArray(coupon.appliesToProductIds) ? coupon.appliesToProductIds : [];
  return cats.length > 0 || prods.length > 0;
}

// Sum of the only lines the coupon may touch. Mirrors Dart Coupon.eligibleSubtotalFor().
function eligibleSubtotalPaise(coupon, pricedLines) {
  const cats = Array.isArray(coupon.appliesToCategoryIds) ? coupon.appliesToCategoryIds : [];
  const prods = Array.isArray(coupon.appliesToProductIds) ? coupon.appliesToProductIds : [];
  if (cats.length === 0 && prods.length === 0) {
    return pricedLines.reduce((sum, line) => sum + toInt(line.lineTotalPaise), 0);
  }
  return pricedLines
    .filter((line) => cats.includes(line.categoryId) || prods.includes(line.productId))
    .reduce((sum, line) => sum + toInt(line.lineTotalPaise), 0);
}

// Mirrors Coupon.discountFor + scope + minQty + excludesWholesale. Eligible subtotal is the only
// slice of the cart the coupon applies to, so category/product scoped coupons never touch the rest.
// Returns { discountPaise, freeShipping, reason } — never throws, so `ordersCreate` can fall back
// to a full-price order with an explanatory message instead of failing the checkout.
function couponDiscount(coupon, pricedLines, { wholesale, cartUnits, now }) {
  if (!couponIsRedeemable(coupon, now)) return { discountPaise: 0, freeShipping: false, reason: COUPON_INVALID };
  if (coupon.excludesWholesale === true && wholesale) return { discountPaise: 0, freeShipping: false, reason: COUPON_WHOLESALE };
  const minQty = toInt(coupon.minQty, 1);
  if (toInt(cartUnits, 0) < minQty) return { discountPaise: 0, freeShipping: false, reason: COUPON_MIN_QTY(minQty) };

  const eligible = eligibleSubtotalPaise(coupon, pricedLines);
  if (eligible < toInt(coupon.minCartValuePaise)) return { discountPaise: 0, freeShipping: false, reason: COUPON_MIN_CART };

  const kind = coupon.kind;
  let raw = 0;
  if (kind === 'percentage') raw = Math.round((eligible * toInt(coupon.percentOff)) / 100);
  else if (kind === 'flat') raw = Math.min(Math.max(toInt(coupon.valuePaise), 0), eligible);
  else if (kind === 'freeShipping') raw = 0;
  const cap = coupon.maxDiscountPaise;
  if (cap != null) raw = Math.min(Math.max(raw, 0), toInt(cap));
  return { discountPaise: raw, freeShipping: kind === 'freeShipping', reason: '' };
}

// ---- shipping ----------------------------------------------------------------------------------

// Sentinel returned when NO rule in the table can deliver to a pincode. Callers must reject the
// order (index.js fails `failed-precondition`/UNSERVICEABLE) — never fold it into a total, which is
// exactly what the client-side estimate used to do by returning 0.
const UNSERVICEABLE = -1;

function zoneCovers(zone, pincode) {
  if (!zone || zone.isActive === false || !Array.isArray(zone.pincodePrefixes)) return false;
  const code = String(pincode || '');
  return zone.pincodePrefixes.some((prefix) => code.startsWith(String(prefix)));
}

function findZone(settings, pincode) {
  const zones = Array.isArray(settings.shippingZones) ? settings.shippingZones : [];
  return zones.find((z) => zoneCovers(z, pincode)) || null;
}

// Serviceability and price are two different questions, and only the zone table can answer the
// first one. Order of decisions:
//   1. pickup is always free;
//   2. no zone covers the pincode -> deliverable ONLY if the store's own nationwide promise
//      (`freeShippingAbovePaise`, i.e. "we ship anywhere above this cart value") is met, otherwise
//      UNSERVICEABLE. A free-shipping COUPON never waives this: free delivery to an address the
//      store cannot reach is not a discount, it is an order nobody can fulfil;
//   3. inside a covered zone, a free-shipping coupon or either free-above threshold zeroes the rate.
// Mirrors the Dart side of the contract in docs/functions-and-orders.md §4.
function shippingFor(settings, { deliveryMode, pincode, subtotalPaise, freeShippingCoupon }) {
  if (deliveryMode === 'pickup') return 0;
  const zone = findZone(settings, pincode);
  const freeAbove = settings.freeShippingAbovePaise;
  if (!zone) {
    if (freeAbove != null && subtotalPaise >= toInt(freeAbove)) return 0;
    return UNSERVICEABLE;
  }
  if (freeShippingCoupon) return 0;
  if (zone.freeAbovePaise != null && subtotalPaise >= toInt(zone.freeAbovePaise)) return 0;
  if (freeAbove != null && subtotalPaise >= toInt(freeAbove)) return 0;
  return toInt(zone.flatRatePaise);
}

// A courier order needs a pincode the zone table can even be asked about. The client validates the
// same shape (OmValidators.pincode) before submit, so this only closes the server-side hole where a
// blank/short pincode silently matched nothing.
const PINCODE = /^\d{6}$/;
function isValidPincode(pincode) {
  return PINCODE.test(String(pincode || '').trim());
}

// ---- receipts ----------------------------------------------------------------------------------
//
// RETIRED HERE ON PURPOSE: this module used to carry a second `receiptFromOrder(order, { orderId })`
// and a `mayReplayKeyIdempotencyRecord(record, uid, role, adminRoles)`. Both are gone, and building a
// receipt or deciding replay ownership now belongs ONLY to lib/order_access.js:
//   * the local `receiptFromOrder` read `orderId || order.id || ''`, which lets a stray `id` field in
//     a stored document body override the id the caller is told about;
//   * `mayReplayKeyIdempotencyRecord` let any admin role resolve any buyer's key, and bound a
//     guest-placed key to any other anonymous caller (`null === null`).
// The owner has ruled on both (see the header of order_access.js): no staff bypass, and guest replay
// requires the original buyer's contact detail. Keeping a permissive second copy here would invite
// exactly the drift those rulings close.

// The receipt shape the Dart `OrderReceipt.fromMap` decodes. `grandTotalPaise` on the wire is the
// rupee-rounded amount the buyer is actually charged, so create, replay and the stored document all
// agree; `roundingPaise` stays informational.
function totalsToReceipt(t) {
  return {
    subtotalPaise: t.subtotalPaise,
    slabDiscountPaise: t.slabSavingsPaise,
    couponDiscountPaise: t.couponDiscountPaise,
    shippingPaise: t.shippingPaise,
    taxPaise: t.taxPaise,
    roundingPaise: t.payableRoundedPaise - t.grandTotalPaise,
    grandTotalPaise: t.payableRoundedPaise,
    paidPaise: 0,
    refundedPaise: 0,
  };
}

// ---- PRICE_CHANGED epsilon ---------------------------------------------------------------------

// The client sends `totals.payableRoundedPaise` — the rupee-rounded amount it showed the buyer — so
// the server compares like with like against the amount it is about to store and charge. Comparing
// a rounded client figure against the UNROUNDED `grandTotalPaise` would spend the whole epsilon on
// rounding (up to 99 paise) and leave nothing for real drift.
function priceAgreement(clientTotalPaise, totals, epsilonPaise) {
  const chargedPaise = totals.payableRoundedPaise;
  const client = toInt(clientTotalPaise);
  if (!(client > 0)) return { checked: false, ok: true, chargedPaise, diffPaise: 0, epsilonPaise: toInt(epsilonPaise) };
  const diff = client - chargedPaise;
  return {
    checked: true,
    ok: Math.abs(diff) <= toInt(epsilonPaise, 0),
    chargedPaise,
    diffPaise: diff,
    epsilonPaise: toInt(epsilonPaise, 0),
  };
}

module.exports = {
  COUPON_INVALID,
  COUPON_WHOLESALE,
  COUPON_MIN_QTY,
  COUPON_MIN_CART,
  UNSERVICEABLE,
  couponIsRedeemable,
  couponHasScope,
  eligibleSubtotalPaise,
  couponDiscount,
  zoneCovers,
  findZone,
  shippingFor,
  isValidPincode,
  totalsToReceipt,
  priceAgreement,
};
