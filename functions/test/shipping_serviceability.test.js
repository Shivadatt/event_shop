'use strict';

// F3 regression suite: is this pincode deliverable AT ALL, decided before any free-shipping rule.
//
// The bug being pinned: a free-shipping COUPON short-circuited the zone table. `shippingFor` used to
// answer "the coupon says free, so 0" before asking whether a zone covers the address, so an order
// to a pincode the store cannot reach was accepted with shipping 0 — a checkout that succeeds and a
// parcel nobody can send. Serviceability and price are two different questions; only the zone table
// answers the first, and a discount never waives it.
//
// The other half of the fix is the pincode SHAPE. A blank or half-typed code matched no zone and then
// fell through to the store-wide free-shipping threshold, so an address-less courier order was
// accepted at shipping 0. `lib/checkout.js#isValidPincode` is the same 6-digit rule the client
// enforces (OmValidators.pincode), so the server refuses it too.

const test = require('node:test');
const assert = require('node:assert/strict');

const { createHarness } = require('./support/harness');
const checkout = require('../lib/checkout');

const h = createHarness();
const UID_A = 'uid-buyer-a';

const ZONE = { id: 'z1', name: 'Bengaluru', pincodePrefixes: ['560'], flatRatePaise: 1000, freeAbovePaise: null, isActive: true };

function shipSettings(overrides = {}) {
  return { taxRateBps: 0, allowGuestCheckout: true, invoicePrefix: 'OME', freeShippingAbovePaise: null, shippingZones: [ZONE], ...overrides };
}

function ship(settings, { deliveryMode = 'courier', pincode = '560001', subtotalPaise = 10000, freeShippingCoupon = false } = {}) {
  return checkout.shippingFor(settings, { deliveryMode, pincode, subtotalPaise, freeShippingCoupon });
}

test.beforeEach(() => {
  h.reset();
  h.settings();
  h.product('p1');
  h.user(UID_A, { email: 'a@example.test' });
});

// ---- the rule itself ----------------------------------------------------------------------------

test('a covered pincode pays the zone flat rate', () => {
  assert.equal(ship(shipSettings()), 1000);
  assert.equal(checkout.findZone(shipSettings(), '560999').id, 'z1');
});

test('an uncovered pincode is UNSERVICEABLE, not free', () => {
  assert.equal(ship(shipSettings(), { pincode: '700001' }), checkout.UNSERVICEABLE);
  assert.equal(checkout.findZone(shipSettings(), '700001'), null);
});

test('a free-shipping COUPON cannot make an uncovered pincode deliverable', () => {
  // This is the F3 case: before the fix this returned 0 and the order was accepted.
  assert.equal(ship(shipSettings(), { pincode: '700001', freeShippingCoupon: true }), checkout.UNSERVICEABLE);
  assert.equal(ship(shipSettings(), { pincode: '560001', freeShippingCoupon: true }), 0, 'inside the zone the coupon still works');
});

test('the store-wide promise, not a coupon, is what exempts an uncovered pincode', () => {
  // Deliberate: `freeShippingAbovePaise` reads as "we ship anywhere above this cart value", so a
  // large cart outside the zone table is a fulfilment decision the store has already made. A coupon
  // is a price discount and carries no such promise.
  assert.equal(ship(shipSettings({ freeShippingAbovePaise: 5000 }), { pincode: '700001' }), 0);
  assert.equal(ship(shipSettings({ freeShippingAbovePaise: 50000 }), { pincode: '700001' }), checkout.UNSERVICEABLE);
});

test('in-zone free-above thresholds beat the flat rate, and both are inclusive', () => {
  assert.equal(ship(shipSettings({ shippingZones: [{ ...ZONE, freeAbovePaise: 20000 }] }), { subtotalPaise: 10000 }), 1000);
  assert.equal(ship(shipSettings({ shippingZones: [{ ...ZONE, freeAbovePaise: 10000 }] }), { subtotalPaise: 10000 }), 0);
  assert.equal(ship(shipSettings({ freeShippingAbovePaise: 10000 }), { subtotalPaise: 10000 }), 0);
});

test('self-collect is always free and never needs an address', () => {
  assert.equal(ship(shipSettings(), { deliveryMode: 'pickup', pincode: '' }), 0);
  assert.equal(ship(shipSettings({ shippingZones: [] }), { deliveryMode: 'pickup' }), 0);
});

test('an inactive zone, a malformed prefix list and an empty table all mean "no cover"', () => {
  assert.equal(ship(shipSettings({ shippingZones: [{ ...ZONE, isActive: false }] })), checkout.UNSERVICEABLE);
  assert.equal(ship(shipSettings({ shippingZones: [{ ...ZONE, isActive: undefined }] })), 1000, 'only an explicit false disables a zone');
  assert.equal(ship(shipSettings({ shippingZones: [{ ...ZONE, pincodePrefixes: 'nope' }] }), { pincode: '560001' }), checkout.UNSERVICEABLE);
  assert.equal(ship(shipSettings({ shippingZones: undefined }), { pincode: '560001' }), checkout.UNSERVICEABLE);
});

test('the first covering zone wins, and a prefix is matched as a string', () => {
  const settings = shipSettings({
    shippingZones: [
      { id: 'near', pincodePrefixes: ['5600'], flatRatePaise: 500, isActive: true },
      { id: 'wide', pincodePrefixes: ['560', '571'], flatRatePaise: 1200, isActive: true },
    ],
  });
  assert.equal(checkout.findZone(settings, '560001').id, 'near');
  assert.equal(ship(settings, { pincode: '560001' }), 500);
  assert.equal(ship(settings, { pincode: '560111' }), 1200);
  assert.equal(ship(settings, { pincode: '571001' }), 1200);
  assert.equal(checkout.zoneCovers({ pincodePrefixes: [560], isActive: true }, '560001'), true, 'numeric prefixes are stringified');
});

test('a flat rate stored as a string is still integer paise', () => {
  assert.equal(ship(shipSettings({ shippingZones: [{ ...ZONE, flatRatePaise: '1500' }] })), 1500);
});

// ---- the pincode shape gate ----------------------------------------------------------------------

test('isValidPincode accepts exactly six digits, with the surrounding whitespace trimmed away', () => {
  for (const good of ['560001', ' 560001 ', 560001]) assert.equal(checkout.isValidPincode(good), true, `${good}`);
  for (const bad of ['', '   ', null, undefined, '56001', '5600010', '56000A', '560 001', '-560001']) {
    assert.equal(checkout.isValidPincode(bad), false, `${bad}`);
  }
});

// ---- the callable: what a buyer actually experiences ---------------------------------------------

async function createWith(key, overrides = {}) {
  return h.invoke('ordersCreate', h.draft({ key, email: 'a@example.test', ...overrides }), h.asSigned(UID_A));
}

function useSettings(overrides) {
  h.settings(overrides);
  h.reloadSettings();
}

test('a covered pincode stores the zone rate on the order', async () => {
  const receipt = await createWith('s-1', { pincode: '560001', shippingPaise: 1000 });
  assert.equal(receipt.totals.shippingPaise, 1000);
  assert.equal(receipt.totals.grandTotalPaise, 11000);
  assert.equal(h.read(`orders/${receipt.orderId}`).totals.shippingPaise, 1000);
});

test('an uncovered pincode is refused with UNSERVICEABLE and reserves nothing', async () => {
  const error = await createWith('s-2', { pincode: '700001' }).catch((e) => e);
  assert.equal(error.code, 'failed-precondition');
  assert.equal(error.details.code, 'UNSERVICEABLE');
  assert.equal((await h.db.collection('orders').get()).size, 0);
  assert.equal(h.read('products/p1').stockQty, 100);
  assert.equal(h.read('idempotency_keys/s-2'), null, 'a refused order must not leave a key behind');
});

test('a free-shipping coupon on an uncovered pincode is still refused', async () => {
  // The F3 case end to end: the client had already applied "FREE" and shows shipping 0, the server
  // must answer "we cannot deliver there", not "free, order accepted".
  h.coupon('SHIPFREE', { kind: 'freeShipping', valuePaise: 0 });
  const error = await createWith('s-3', { pincode: '700001', couponCode: 'SHIPFREE', shippingPaise: 0 }).catch((e) => e);
  assert.equal(error.code, 'failed-precondition');
  assert.equal(error.details.code, 'UNSERVICEABLE');
  assert.equal(h.read('coupons/SHIPFREE').usedCount, 0, 'a coupon cannot be burned by an order that never existed');
});

test('the same coupon inside the zone really is free', async () => {
  h.coupon('SHIPFREE', { kind: 'freeShipping', valuePaise: 0 });
  const receipt = await createWith('s-4', { pincode: '560111', couponCode: 'SHIPFREE', shippingPaise: 0 });
  assert.equal(receipt.totals.shippingPaise, 0);
  assert.equal(receipt.totals.grandTotalPaise, 10000);
  assert.equal(h.read(`orders/${receipt.orderId}`).couponCode, 'SHIPFREE');
  assert.equal(h.read('coupons/SHIPFREE').usedCount, 1);
});

test('a store-wide free-shipping promise lets a covered-rule-exempt outside pincode through', async () => {
  useSettings({ freeShippingAbovePaise: 5000 });
  const receipt = await createWith('s-5', { pincode: '700001', shippingPaise: 0 });
  assert.equal(receipt.totals.shippingPaise, 0);
  assert.equal(receipt.totals.grandTotalPaise, 10000);
});

test('a courier order with no usable pincode is refused before the zone table is consulted', async () => {
  for (const [label, pincode] of [['blank', ''], ['five digits', '56001'], ['seven digits', '5600001'], ['letters', '56A001'], ['missing key', undefined]]) {
    const error = await h
      .invoke('ordersCreate', { ...h.draft({ key: `s-pin-${label}`, email: 'a@example.test', pincode }), shipping: pincode === undefined ? null : { pincode, address: 'x' } }, h.asSigned(UID_A))
      .catch((e) => e);
    assert.equal(error.code, 'invalid-argument', `${label} must be rejected by shape, not by zone`);
    assert.match(error.message, /pincode/i);
  }
  assert.equal((await h.db.collection('orders').get()).size, 0);
});

test('the pincode-shape gate does not apply to self-collect', async () => {
  const receipt = await createWith('s-6', { deliveryMode: 'pickup', shippingPaise: 0 });
  assert.equal(receipt.totals.shippingPaise, 0);
  assert.equal(receipt.totals.grandTotalPaise, 10000);
  assert.equal(h.read(`orders/${receipt.orderId}`).shipping, null);
});

test('a pincode padded with spaces is delivered, not silently marked unserviceable', async () => {
  // `isValidPincode` trims, and the value used for the zone lookup is trimmed too, so the two can
  // never disagree about which string is being tested.
  const receipt = await createWith('s-7', { pincode: ' 560001 ', shippingPaise: 1000 });
  assert.equal(receipt.totals.shippingPaise, 1000);
});

test('an order to a pincode the store later stops serving still replays its own totals', async () => {
  // The zone table is read at create time only. A replay copies the STORED totals, so removing a zone
  // cannot re-price an existing order — and cannot turn a replay into a fresh serviceability check.
  const placed = await createWith('s-8', { pincode: '560001', shippingPaise: 1000 });
  useSettings({ shippingZones: [] });
  const replay = await createWith('s-8', { pincode: '560001', shippingPaise: 1000 });
  assert.equal(replay.wasReplay, true);
  assert.equal(replay.orderId, placed.orderId);
  assert.equal(replay.totals.shippingPaise, 1000);
});

test('a guest courier order needs a pincode too', async () => {
  const error = await h
    .invoke('ordersCreate', h.draft({ key: 's-9', pincode: '700001', email: 'g@example.test' }), h.asAnonymous())
    .catch((e) => e);
  assert.equal(error.details.code, 'UNSERVICEABLE');
  assert.equal((await h.db.collection('orders').get()).size, 0);
});
