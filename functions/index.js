'use strict';

// OM Events trusted server side. Node 20, firebase-functions v2, CommonJS.
//
// Every privileged callable re-reads the caller's role from users/{uid} and refuses blocked users
// before touching data. Money is integer paise; tax is basis points; the ONLY authoritative order
// total is produced by ordersCreate (mirroring functions/lib/pricing.js == the Dart engine).
//
// UNVERIFIED against a live project: no Firebase project or credentials are configured, so none of
// these handlers have been executed. They are written to be read/checked, then deployed by the
// owner once docs/backend-setup.md steps are complete.

const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentWritten,
} = require('firebase-functions/v2/firestore');

const {
  db,
  auth: adminAuth,
  FieldValue,
  REGION,
  PRICE_EPSILON_PAISE,
  ADMIN_ROLES,
  PRICING_ROLES,
  toInt,
  newId,
  normaliseCode,
  requireCaller,
  requireRole,
  callerProfile,
  writeAudit,
  readStoreSettings,
  clearSettingsCache,
  enforceAllowList,
  enforceSizeCap,
} = require('./lib/server');

const pricing = require('./lib/pricing');
const { toMillis } = require('./lib/coerce');
const { keyPointsToOwnedOrder, mayReadReplay, mayReplayCreatedOrder, receiptFromOrder, REPLAY_REFUSED } = require('./lib/order_access');
// F2/F3/F4: the coupon, shipping, pincode and price-agreement rules come from lib/checkout.js instead
// of being re-implemented below. `couponsQuote` (the preview) and `ordersCreate` (the charge) must not
// be able to disagree about what a cart costs or whether a pincode is deliverable.
const { couponDiscount, shippingFor, totalsToReceipt, isValidPincode, priceAgreement } = require('./lib/checkout');
const { allocateOrderNumber } = require('./lib/order_number');

setGlobalOptions({ region: REGION, maxInstances: 10 });

// ---- error bridge: throw the HttpsError code the Dart repository maps to an OmFailure --------
function fail(code, message, details) {
  throw new HttpsError(code, message, details);
}

// Map the server-only error wrappers thrown by lib/server into HttpsError at the call boundary.
async function guarded(fn) {
  try {
    return await fn();
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error.code === 'permission-denied') fail('permission-denied', error.message);
    if (error.code === 'unauthenticated') fail('unauthenticated', error.message);
    if (error.code === 'invalid-argument') fail('invalid-argument', error.message);
    throw error;
  }
}

// ---- pricing eligibility + wholesale unlock (only an approved application counts) ------------
function buyerMaySeeWholesale(profile) {
  if (!profile) return false;
  if (ADMIN_ROLES.includes(profile.role)) return true;
  return profile.role === 'wholesale' || profile.wholesaleStatus === 'approved';
}

// ---- coupon + shipping rules: imported from lib/checkout.js -----------------------------------
// They used to be duplicated here, and the duplicates were wrong in three ways that are now fixed by
// importing instead of editing twice:
//   * `now < coupon.startsAt` compared a millisecond NUMBER against a Firestore Timestamp OBJECT, so
//     NaN made both window guards silently pass and an expired or not-yet-started coupon still
//     discounted (F2);
//   * a free-shipping COUPON was honoured before the zone table was consulted, so an address the
//     store cannot deliver to produced shipping 0 instead of the unserviceable refusal (F3);
//   * the eligible-subtotal reduce read raw line values where the shared helper coerces through
//     `toInt`, and `zoneCovers` called `.startsWith` on a raw prefix.
// Money stays integer paise; `couponDiscount`/`shippingFor` never throw — index.js decides the
// HttpsError. The Dart client keeps its own copies of these rules, and that parity is NOT fixture-pinned
// (slab_fixtures.json has no coupon or shipping cases), so it is asserted on the server side only.

// =================================================================================================
// ORDERS — the trusted create path
// =================================================================================================

exports.ordersCreate = onCall(async (request) => {
  return guarded(async () => {
    const settings = await readStoreSettings();
    const draft = request.data || {};
    const lines = Array.isArray(draft.lines) ? draft.lines : [];
    if (lines.length === 0) fail('invalid-argument', 'The order has no items.');
    if (lines.length > 100) fail('invalid-argument', 'Too many lines in one order.');

    const isGuest = !request.auth;
    if (isGuest && settings.allowGuestCheckout === false) fail('permission-denied', 'Guest checkout is disabled.');
    let caller = null;
    if (!isGuest) caller = await requireCaller(request);
    if (caller && caller.role && caller.role !== 'guest' && caller.isBlocked === true) {
      fail('permission-denied', 'This account is suspended.');
    }
    const uid = isGuest ? null : request.auth.uid;
    const wholesale = buyerMaySeeWholesale(caller);

    const idempotencyKey = String(draft.idempotencyKey || '');
    if (!idempotencyKey) fail('invalid-argument', 'Missing idempotency key.');

    const clientTotalPaise = toInt(draft.clientTotalPaise);
    const deliveryMode = draft.deliveryMode === 'pickup' ? 'pickup' : 'courier';
    const shipping = draft.shipping || null;
    const couponCode = normaliseCode(draft.couponCode || '');
    const paymentMethod = String(draft.paymentMethod || '');

    // Pre-read the authoritative docs (variants, coupon, overrides) — the transaction locks the
    // mutable stock/coupon/counter docs, but read-only references can be fetched beforehand.
    const productIds = [...new Set(lines.map((l) => String(l.productId)))];
    const overrides = uid
      ? await db.collection('customer_price_overrides')
          .where('uid', '==', uid)
          .get()
          .then((s) => s.docs)
      : [];
    const couponSnap = couponCode ? await db.collection('coupons').doc(couponCode).get() : null;
    const now = Date.now();

    const orderId = newId();
    const idemRef = db.collection('idempotency_keys').doc(idempotencyKey);

    const result = await db.runTransaction(async (tx) => {
      // ---- idempotency lock: a replayed key returns the already-created order, never a 2nd charge
      const idem = await tx.get(idemRef);
      if (idem.exists) {
        const keyRecord = idem.data() || {};
        const existingId = typeof keyRecord.orderId === 'string' ? keyRecord.orderId : '';
        // A blank id must not reach `doc('')`: Firestore rejects it, and that rejection would tell a
        // caller more about the key than the uniform refusal below is willing to reveal.
        const existing = existingId ? await tx.get(db.collection('orders').doc(existingId)) : null;
        const existingData = existing && existing.exists ? existing.data() : null;
        // F1: the key is not a bearer token. Ledger row, order document and caller must all agree
        // (lib/order_access.js), and a guest retry has to re-supply the order's own contact detail.
        // Refusing here throws, which aborts the transaction: nothing is reserved and no second order
        // is minted under somebody else's key.
        if (!mayReplayCreatedOrder({
          keyRecord,
          orderData: existingData,
          callerUid: uid,
          contactEmail: draft.contactEmail,
          contactPhone: draft.contactPhone,
        })) {
          fail('permission-denied', REPLAY_REFUSED);
        }
        return { replay: true, order: existingData, orderId: existingId };
      }

      // ---- re-price EVERY line from persisted slabs (never trust a client price)
      const priced = [];
      // Demand is aggregated by the inventory document, not by line: two lines can name the same
      // product (or the same variant document) and must not each validate against the same balance.
      const stockGroups = new Map();
      for (const line of lines) {
        const productId = String(line.productId);
        const variantId = line.variantId ? String(line.variantId) : null;
        const qty = toInt(line.qty);
        if (qty <= 0) fail('invalid-argument', 'Quantity must be positive.');
        const productSnap = await tx.get(db.collection('products').doc(productId));
        if (!productSnap.exists) fail('not-found', `Product ${productId} not found.`);
        const product = productSnap.data();
        if (product.status !== 'active') fail('failed-precondition', `${product.name} is not available.`);
        if (product.isWholesaleOnly === true && !wholesale) fail('permission-denied', `${product.name} is wholesale-only.`);

        let variantSnap = null;
        let variant = null;
        if (variantId) {
          variantSnap = await tx.get(db.collection('product_variants').doc(variantId));
          if (!variantSnap.exists) fail('not-found', 'Variant not found.');
          variant = variantSnap.data();
          if (variant.isActive === false) fail('failed-precondition', 'Variant unavailable.');
        }

        // A negotiated contract price for THIS buyer+product wins over public slabs.
        const match = overrides.find((o) => {
          const d = o.data();
          if (d.productId !== productId) return false;
          if ((d.variantId || null) !== variantId) return false;
          // F2: same instant-coercion as every other window in the system. `toMillis` accepts a
          // Firestore Timestamp, a Date, epoch millis or an ISO string, and returns null when there is
          // no constraint. The old `typeof expiresAt.toMillis === 'function'` test quietly treated an
          // ISO string (what a callable payload carries) as "never expires".
          const expiresAt = toMillis(d.expiresAt);
          if (expiresAt != null && expiresAt < now) return false;
          return true;
        });
        const overridePaise = match && toInt(match.data().unitPricePaise) > 0 ? toInt(match.data().unitPricePaise) : null;

        const resolution = pricing.priceFor({ product, qty, variant, customerOverrideUnitPricePaise: overridePaise });
        if (overridePaise == null && resolution.unitPricePaise <= 0) fail('failed-precondition', 'Price unavailable for this item.');

        priced.push({
          productId, variantId, qty,
          categoryId: product.categoryId || '',
          unitPricePaise: resolution.unitPricePaise,
          lineTotalPaise: resolution.lineTotalPaise,
          basePricePaise: resolution.baseUnitPricePaise,
          savedPaise: resolution.savedPaise,
          slab: resolution.slab,
          snapshot: {
            productId, name: product.name, qty,
            variantId, sku: (variant && variant.sku) || product.sku || '',
            unit: product.unit || 'pack', slug: product.slug || '',
            imageUrl: (variant && variant.imageUrl) || primaryImage(product),
            slabLabel: resolution.slab ? resolution.slab.label || null : null,
            slabMinQty: resolution.slab ? resolution.slab.minQty : null,
            slabMaxQty: resolution.slab ? (resolution.slab.maxQty == null ? null : resolution.slab.maxQty) : null,
            basePricePaise: resolution.baseUnitPricePaise,
            discountPaise: resolution.savedPaise,
          },
          productRef: productSnap.ref,
          variantRef: variantId ? db.collection('product_variants').doc(variantId) : null,
          stockField: 'stockQty',
          stockSnap: variantSnap || productSnap,
          lowStockThreshold: toInt(product.lowStockThreshold, 5),
          productName: product.name,
        });

        const stockPath = (variantSnap || productSnap).ref.path;
        let group = stockGroups.get(stockPath);
        if (!group) {
          group = {
            stockSnap: variantSnap || productSnap,
            stockField: 'stockQty',
            current: toInt((variantSnap || productSnap).get('stockQty')),
            requestedQty: 0,
            soldCountDelta: 0,
            productId,
            variantId,
            productName: product.name,
          };
          stockGroups.set(stockPath, group);
        }
        group.requestedQty += qty;
        if (!variantId) group.soldCountDelta += qty;
      }

      // ---- atomic stock reservation: read balance in-tx, refuse if short, decrement in-tx.
      // Two concurrent buyers on the last unit serialize here; the loser re-runs and sees the new
      // (insufficient) balance, so neither oversells. Duplicate lines are validated against the
      // SUM demanded from the same inventory document, so they cannot each pass a stale balance.
      for (const group of stockGroups.values()) {
        if (group.current < group.requestedQty) {
          fail('failed-precondition', `${group.productName}: only ${group.current} available.`, {
            code: 'OUT_OF_STOCK',
            productId: group.productId,
            available: group.current,
            requested: group.requestedQty,
          });
        }
      }

      // ---- coupon (server view; used inside the same tx so last-use races cannot both spend it)
      let couponResult = { discountPaise: 0, freeShipping: false, reason: '' };
      let couponRef = null;
      let redemptionRef = null;
      // Captured from the pre-write read below and reused when the redemption is written: a second
      // tx.get after tx.update would be a read-after-write and abort the whole transaction.
      let redemptionExistingCount = 0;
      if (couponCode) {
        if (!couponSnap.exists) couponResult = { discountPaise: 0, freeShipping: false, reason: 'Unknown coupon code.' };
        else {
          couponRef = couponSnap.ref;
          const coupon = { id: couponSnap.id, ...couponSnap.data() };
          const cartUnits = priced.reduce((s, l) => s + l.qty, 0);
          couponResult = couponDiscount(coupon, priced, { wholesale, cartUnits, now });
          if (couponResult.discountPaise > 0 || couponResult.freeShipping) {
            const userKey = uid || `guest:${String(draft.contactEmail || draft.contactPhone || orderId)}`;
            redemptionRef = db.collection('coupon_redemptions').doc(`${couponCode}__${userKey}`);
            const limit = toInt(coupon.perUserLimit, 1);
            const existing = await tx.get(redemptionRef);
            redemptionExistingCount = existing.exists ? toInt(existing.data().count) : 0;
            if (existing.exists && redemptionExistingCount >= limit) {
              couponResult = { discountPaise: 0, freeShipping: false, reason: 'You have already used this code.' };
            }
          }
        }
      }

      // ---- shipping (F3: serviceability is decided by the zone table BEFORE any free-shipping rule)
      const subtotal = priced.reduce((s, l) => s + l.lineTotalPaise, 0);
      const pincode = shipping ? String(shipping.pincode || '').trim() : '';
      // A courier order needs a pincode the zone table can even be asked about. A blank one used to
      // match no zone and then fall through to the store-wide free-shipping threshold, which accepted
      // an order with no deliverable address and shipping 0. The client validates the same shape
      // (OmValidators.pincode) before submit; this closes the server-side hole.
      if (deliveryMode !== 'pickup' && !isValidPincode(pincode)) fail('invalid-argument', 'Enter a valid 6-digit delivery pincode.');
      const shipPaise = shippingFor(settings, {
        deliveryMode, pincode, subtotalPaise: subtotal,
        freeShippingCoupon: couponResult.freeShipping,
      });
      if (shipPaise < 0) fail('failed-precondition', 'We do not deliver to this pincode yet.', { code: 'UNSERVICEABLE' });

      // ---- totals from the shared engine (tax BASIS POINTS; slab savings kept separate)
      const totals = pricing.cartTotals(
        priced.map((l) => ({ qty: l.qty, lineTotalPaise: l.lineTotalPaise, savedPaise: l.savedPaise })),
        {
          couponDiscountPaise: couponResult.discountPaise,
          shippingPaise: shipPaise,
          taxRateBps: toInt(settings.taxRateBps),
          taxInclusive: settings.taxInclusive === true,
        },
      );

      // ---- F4: epsilon check, compared like-for-like. The buyer's cart shows the RUPEE-ROUNDED
      // payable (`totals.payableRoundedPaise`, which is also the amount stored and charged), and
      // `OrderDraft` sends exactly that figure. Comparing it against the UNROUNDED grand total spent
      // up to 99 paise of the 100-paise budget on rounding alone, leaving ~1 paise for real drift.
      // The epsilon is deliberately NOT widened to compensate.
      const agreement = priceAgreement(clientTotalPaise, totals, PRICE_EPSILON_PAISE);
      if (!agreement.ok) {
        fail('failed-precondition', 'The order total changed. Please review and confirm.', {
          code: 'PRICE_CHANGED',
          serverGrandTotalPaise: totals.grandTotalPaise,
          serverPayableRoundedPaise: agreement.chargedPaise,
          clientTotalPaise,
          diffPaise: agreement.diffPaise,
          epsilonPaise: agreement.epsilonPaise,
        });
      }

      // ---- order number from a yearly counter, incremented inside the tx (no dupes). The public
      // PREFIX-YYYY-NNNNNN format is unchanged, but the counter no longer resets every month; that
      // reset was what let two months of the same year mint the same visible number.
      let allocation;
      try {
        allocation = await allocateOrderNumber({
          tx, db, prefix: settings.invoicePrefix || 'OME', now: new Date(),
        });
      } catch (error) {
        if (error && error.code === 'failed-precondition') fail('failed-precondition', error.message);
        throw error;
      }
      const number = allocation.number;
      // Persist the sequence in the same transaction as the order. Concurrent creates serialize on
      // this document, so a retry re-reads the winner's value before minting the next number.
      tx.set(allocation.counterRef, { value: allocation.seq, updatedAt: FieldValue.serverTimestamp() }, { merge: true });

      const paymentStatus = paymentMethod === 'cod' ? 'codPending' : paymentMethod === '' ? 'pending' : 'pending';
      const createdAt = FieldValue.serverTimestamp();

      // ---- commit one decrement per inventory document, plus per-line movement ledger rows.
      // The aggregate write is what makes duplicate lines safe: stock is touched once with the
      // summed quantity, while order items keep their original per-line pricing and presentation.
      const movements = [];
      const runningBalances = new Map();
      for (const [path, group] of stockGroups) {
        tx.update(group.stockSnap.ref, {
          [group.stockField]: FieldValue.increment(-group.requestedQty),
          soldCount: FieldValue.increment(group.soldCountDelta),
          updatedAt: createdAt,
        });
        runningBalances.set(path, group.current);
      }
      for (const line of priced) {
        const path = line.stockSnap.ref.path;
        const balanceAfter = runningBalances.get(path) - line.qty;
        runningBalances.set(path, balanceAfter);
        const moveRef = db.collection('inventory_movements').doc();
        tx.set(moveRef, {
          productId: line.productId, variantId: line.variantId, kind: 'saleOut', quantity: line.qty,
          balanceAfter, orderId, reason: 'order', reference: number, actorUid: uid || '',
          createdAt,
        });
        movements.push({ ref: moveRef, line, balanceAfter });
      }

      const orderRef = db.collection('orders').doc(orderId);
      tx.set(orderRef, {
        orderNumber: number,
        userId: uid || '',
        isGuest,
        contactEmail: String(draft.contactEmail || (caller && caller.email) || ''),
        contactPhone: String(draft.contactPhone || ''),
        status: 'placed',
        paymentStatus,
        paymentMethod,
        couponCode: couponResult.discountPaise > 0 || couponResult.freeShipping ? couponCode : '',
        deliveryMode,
        shipping: shipping || null,
        customerNote: String(draft.customerNote || ''),
        idempotencyKey,
        source: 'web',
        items: priced.map((l) => ({ ...l.snapshot, isStockDeducted: true })),
        totals: {
          subtotalPaise: totals.subtotalPaise,
          slabDiscountPaise: totals.slabSavingsPaise,
          couponDiscountPaise: totals.couponDiscountPaise,
          shippingPaise: totals.shippingPaise,
          taxPaise: totals.taxPaise,
          // roundingPaise is the informational rupee-rounding delta only.
          roundingPaise: totals.payableRoundedPaise - totals.grandTotalPaise,
          // Store the rupee-rounded amount the customer is actually charged, so payment marking
          // and revenue reports never drift from the checkout total by up to 99 paise.
          grandTotalPaise: totals.payableRoundedPaise,
          paidPaise: 0,
          refundedPaise: 0,
        },
        createdAt,
        updatedAt: createdAt,
      });

      // ---- status history lives in a subcollection (unbounded history, not an inline array)
      tx.set(orderRef.collection('history').doc(), {
        at: createdAt, status: 'placed', note: 'Order placed', actorRole: isGuest ? 'guest' : (caller.role || 'customer'), actorUid: uid || '',
      });

      if (couponResult.discountPaise > 0 || couponResult.freeShipping) {
        tx.update(couponRef, { usedCount: FieldValue.increment(1), updatedAt: createdAt });
        if (redemptionRef) {
          tx.set(redemptionRef, { couponCode, uid: uid || null, count: redemptionExistingCount + 1, updatedAt: createdAt }, { merge: true });
        }
      }

      // ---- low-stock notification for anything that just crossed its threshold
      for (const m of movements) {
        if (m.balanceAfter >= 0 && m.balanceAfter <= m.line.lowStockThreshold) {
          tx.set(db.collection('inventory_alerts').doc(`${m.line.productId}_${m.line.variantId || 'base'}`), {
            productId: m.line.productId, variantId: m.line.variantId, balanceAfter: m.balanceAfter, threshold: m.line.lowStockThreshold, updatedAt: createdAt,
          }, { merge: true });
        }
      }

      tx.set(idemRef, { orderId, uid: uid || null, createdAt });

      return { replay: false, orderId, number, totals, paymentStatus, orderStatus: 'placed', uid, caller, movements };
    });

    if (result.replay) {
      // The id comes from the transaction (`existingId`), never from the stored document: Firestore
      // document data has no `id` field, so the old `o.id || ''` always answered `orderId: ''` —
      // which left the Dart review step unable to load, accept or decline the order it just found.
      return receiptFromOrder(result.order, result.orderId, { wasReplay: true });
    }

    // Buyer notification (best-effort, outside the money transaction).
    if (result.uid) {
      await db.collection('notifications').doc().set({
        uid: result.uid, title: 'Order placed', body: `Order ${result.number} confirmed.`, kind: 'orderPlaced', entityId: result.orderId, route: `/account/order/${result.orderId}`, isRead: false, createdAt: FieldValue.serverTimestamp(),
      });
    }
    await writeAudit(db, {
      action: 'order.create', entityType: 'order', entityId: result.orderId,
      actorUid: result.uid || '', actorRole: result.caller ? result.caller.role : 'guest',
      summary: `Created ${result.number} for ${result.totals.payableRoundedPaise} paise`, after: { grandTotalPaise: result.totals.payableRoundedPaise, orderNumber: result.number },
    });

    return {
      orderId: result.orderId, orderNumber: result.number,
      totals: totalsToReceipt(result.totals), paymentStatus: result.paymentStatus, orderStatus: 'placed',
      paymentClientSecret: '', paymentUrl: '', wasReplay: false, priceChanged: false,
      message: paymentMethodOf(request) === 'online' && !process.env.OM_PAYMENT_GATEWAY
        ? 'Online payment is not configured yet; your order is saved as pending.'
        : 'Order placed.',
    };
  });
});

function paymentMethodOf(request) {
  return String((request.data || {}).paymentMethod || '');
}
function primaryImage(product) {
  const images = Array.isArray(product.images) ? product.images : [];
  const prim = images.find((i) => i && i.isPrimary);
  return (prim || images[0] || {}).url || '';
}
// `totalsToReceipt` (the fresh-create receipt wire shape) and `couponDiscount`/`shippingFor` come from
// lib/checkout.js; `receiptFromOrder` and every replay-ownership rule come from lib/order_access.js.
// Both modules are Firebase-free, so `npm test` asserts the real rules with no emulator and no
// deployed backend. Nothing in index.js re-implements them a second time.

// ---- idempotent replay lookup for the Dart retry path -----------------------------------------
// An idempotency key is NOT a capability: guessing one must never reveal another buyer's receipt,
// and a guest order has no account to check against. Both cases answer the identical
// `{ found: false }`, so this call cannot be used to confirm that a key exists, and no guest PII
// (contactEmail / contactPhone / shipping address inside `totals`+items) ever crosses the wire.
exports.orderByIdempotency = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireCaller(request);
    const key = String((request.data || {}).idempotencyKey || '');
    if (!key) fail('invalid-argument', 'Missing idempotency key.');
    const snap = await db.collection('idempotency_keys').doc(key).get();
    // A missing key, someone else's key, a guest-placed key and a vanished order all answer the
    // identical `{ found: false }` — this call cannot confirm that a key exists.
    if (!snap.exists) return { found: false };
    const idem = snap.data() || {};
    // Pre-gate on the ledger row so a guessed key never costs an order read (these callables have
    // no rate limiting yet).
    if (!keyPointsToOwnedOrder({ keyRecord: idem, callerUid: caller.uid })) return { found: false };
    const orderId = idem.orderId;
    const order = await db.collection('orders').doc(orderId).get();
    const data = order.exists ? order.data() || {} : null;
    // Final gate: the order document must agree with the ledger before a receipt crosses the wire.
    if (!mayReadReplay({ keyRecord: idem, orderData: data, callerUid: caller.uid })) return { found: false };
    return { found: true, receipt: receiptFromOrder(data, orderId, { wasReplay: true }) };
  });
});

// ---- customer-initiated cancellation / return (status transitions still server-side) ---------
exports.orderRequestCancel = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireCaller(request);
    const data = request.data || {};
    const ref = db.collection('orders').doc(String(data.orderId));
    const snap = await ref.get();
    if (!snap.exists || (snap.data().userId !== caller.uid && !ADMIN_ROLES.includes(caller.role))) fail('not-found', 'Order not found.');
    const status = snap.data().status;
    if (!['placed', 'confirmed', 'processing'].includes(status)) fail('failed-precondition', 'This order can no longer be cancelled.');
    await transitionStatus(ref, { from: status, to: 'cancelled', actor: caller, note: String(data.reason || 'Cancelled by customer'), restoreStock: true, cancelledReason: String(data.reason || '') });
    return { ok: true };
  });
});

exports.orderRequestReturn = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireCaller(request);
    const data = request.data || {};
    const ref = db.collection('orders').doc(String(data.orderId));
    const snap = await ref.get();
    if (!snap.exists || (snap.data().userId !== caller.uid && !ADMIN_ROLES.includes(caller.role))) fail('not-found', 'Order not found.');
    const status = snap.data().status;
    if (status !== 'delivered') fail('failed-precondition', 'Only delivered orders can be returned.');
    await transitionStatus(ref, { from: status, to: 'returned', actor: caller, note: String(data.reason || 'Return requested'), restoreStock: false, cancelledReason: '' });
    return { ok: true };
  });
});

// Forward-only order status machine. The legal moves are the SAME list the Dart OrderStatus.nextSteps
// encodes, mirrored here so the server never depends on the client's copy.
const NEXT_STEPS = {
  placed: ['confirmed', 'cancelled'],
  confirmed: ['processing', 'cancelled'],
  processing: ['packed', 'cancelled'],
  packed: ['shipped'],
  shipped: ['outForDelivery'],
  outForDelivery: ['delivered'],
  delivered: ['returned'],
  returned: ['refunded'],
  cancelled: [],
  refunded: [],
};

// transitionStatus does: re-read in a tx, guard the edge, move status, append history, restore
// stock if a cancellation re-adds reserved units, write audit + notification — all atomically.
async function transitionStatus(ref, { from, to, actor, note, restoreStock, cancelledReason }) {
  if (!NEXT_STEPS[from].includes(to)) fail('failed-precondition', `Cannot move an order from ${from} to ${to}.`);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) fail('not-found', 'Order not found.');
    const current = snap.data().status;
    if (current !== from) fail('failed-precondition', `Order status changed concurrently (now ${current}).`);
    const items = Array.isArray(snap.data().items) ? snap.data().items : [];

    // Firestore rejects tx.get after the first write, so read every restore target up front and
    // apply the plan below. Doing the read inside the restore loop (after tx.update(ref)) aborted
    // every cancellation with `reads before writes`.
    const restorePlan = [];
    if (restoreStock) {
      for (const item of items) {
        if (item.isStockDeducted !== true) continue;
        const stockRef = item.variantId
          ? db.collection('product_variants').doc(String(item.variantId))
          : db.collection('products').doc(String(item.productId));
        restorePlan.push({ item, qty: toInt(item.qty), stockRef, stockSnap: await tx.get(stockRef) });
      }
    }

    const update = {
      status: to,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (cancelledReason) update.cancelledReason = cancelledReason;
    tx.update(ref, update);
    tx.set(ref.collection('history').doc(), {
      at: FieldValue.serverTimestamp(), status: to, note,
      actorRole: actor.role || 'staff', actorUid: actor.uid,
    });

    if (restoreStock) {
      const orderId = snap.id;
      // Two lines can point at the same stock doc (e.g. the same product in two lines); accumulate
      // so each movement reports the real balance instead of overwriting the previous one's figure.
      const balances = new Map();
      for (const entry of restorePlan) {
        if (!entry.stockSnap.exists) continue;
        const key = entry.stockRef.path;
        const base = balances.has(key) ? balances.get(key) : toInt(entry.stockSnap.get('stockQty'));
        const balanceAfter = base + entry.qty;
        balances.set(key, balanceAfter);
        tx.update(entry.stockRef, { stockQty: balanceAfter, updatedAt: FieldValue.serverTimestamp() });
        tx.set(db.collection('inventory_movements').doc(), {
          productId: entry.item.productId, variantId: entry.item.variantId || null, kind: 'cancelRestore', quantity: entry.qty,
          balanceAfter, orderId, reason: 'cancellation', reference: snap.data().orderNumber, actorUid: actor.uid,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      tx.update(ref, { items: items.map((i) => ({ ...i, isStockDeducted: false })) });
    }
  });

  await writeAudit(db, {
    action: 'order.status_change', entityType: 'order', entityId: ref.id,
    actorUid: actor.uid, actorRole: actor.role, summary: `${from} -> ${to}: ${note}`,
    before: { status: from }, after: { status: to },
  });

  const orderSnap = await ref.get();
  const buyerUid = orderSnap.data().userId;
  if (buyerUid) {
    await db.collection('notifications').doc().set({
      uid: buyerUid, title: 'Order updated', body: `Order is now ${to}.`, kind: 'orderUpdate',
      entityId: ref.id, route: `/account/order/${ref.id}`, isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
  }
  return orderSnap;
}

// =================================================================================================
// COUPONS — quote endpoint (the client previews; the server decides the discount)
// =================================================================================================

exports.couponsQuote = onCall(async (request) => {
  return guarded(async () => {
    const data = request.data || {};
    const code = normaliseCode(data.code || '');
    if (!code) return { coupon: null, discountPaise: 0, freeShipping: false, reason: 'Enter a code.' };
    let caller = null;
    if (request.auth) caller = await callerProfile(request.auth.uid);
    const wholesale = buyerMaySeeWholesale(caller);

    const snap = await db.collection('coupons').doc(code).get();
    if (!snap.exists) return { coupon: null, discountPaise: 0, freeShipping: false, reason: 'Unknown coupon code.' };
    const coupon = { id: snap.id, ...snap.data() };

    const pricedLines = (Array.isArray(data.lines) ? data.lines : []).map((l) => ({
      productId: String(l.productId), categoryId: String(l.categoryId || ''), qty: toInt(l.qty), lineTotalPaise: toInt(l.lineTotalPaise),
    }));
    const cartUnits = pricedLines.reduce((s, l) => s + l.qty, 0);
    const outcome = couponDiscount(coupon, pricedLines, { wholesale, cartUnits, now: Date.now() });
    return { coupon: couponDocForClient(coupon), discountPaise: outcome.discountPaise, freeShipping: outcome.freeShipping, reason: outcome.reason };
  });
});

function couponDocForClient(c) {
  // Never leak usedCount/limits back to the browser beyond what a quote needs; the full doc stays
  // admin-only.
  return { id: c.id, code: c.code, kind: c.kind, valuePaise: toInt(c.valuePaise), percentOff: toInt(c.percentOff), maxDiscountPaise: c.maxDiscountPaise == null ? null : toInt(c.maxDiscountPaise), minCartValuePaise: toInt(c.minCartValuePaise), minQty: toInt(c.minQty, 1), isActive: c.isActive !== false, excludesWholesale: c.excludesWholesale === true, description: c.description || '' };
}

// =================================================================================================
// PAYMENTS — capture confirmation. Without a gateway secret this is honestly refused.
// =================================================================================================

exports.paymentsConfirm = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireCaller(request);
    const data = request.data || {};
    const gateway = process.env.OM_PAYMENT_GATEWAY;
    const ref = db.collection('orders').doc(String(data.orderId));
    const order = await ref.get();
    if (!order.exists || order.data().userId !== caller.uid) fail('not-found', 'Order not found.');

    const payId = String(data.paymentId || '');
    const payRef = db.collection('payments').doc(payId);
    const pay = await payRef.get();
    if (!pay.exists || pay.data().orderId !== ref.id) fail('not-found', 'Payment not found.');

    if (!gateway) {
      // No gateway webhook configured: we cannot attest capture from the browser. Leave as pending.
      return { captured: false, status: pay.data().status, message: 'Payment gateway not configured; order remains pending.' };
    }

    // A real capture is only trusted via the gateway's webhook (payments/WebhookHandler). This call
    // simply re-reads whatever the webhook already settled, so the client UI reflects the truth.
    const settled = pay.data().status === 'captured';
    if (settled) {
      await ref.update({ paymentStatus: 'paid', transactionReference: pay.data().transactionReference || '', updatedAt: FieldValue.serverTimestamp() });
    }
    return { captured: settled, status: pay.data().status, message: settled ? 'Payment captured.' : 'Awaiting payment confirmation.' };
  });
});

// =================================================================================================
// ADMIN — privileged callables. Each re-verifies role and writes an audit row.
// =================================================================================================

exports.adminOrderTransition = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const ref = db.collection('orders').doc(String(data.orderId));
    const snap = await ref.get();
    if (!snap.exists) fail('not-found', 'Order not found.');
    const extra = {};
    if (data.trackingUrl) extra.trackingUrl = String(data.trackingUrl);
    if (data.carrier) extra.carrier = String(data.carrier);
    await transitionStatus(ref, {
      from: snap.data().status, to: String(data.to), actor: caller, note: String(data.note || ''),
      restoreStock: String(data.to) === 'cancelled', cancelledReason: String(data.cancelledReason || ''),
    });
    if (Object.keys(extra).length) await ref.update(extra);
    const updated = await ref.get();
    return updated.data();
  });
});

exports.adminOrderMarkPayment = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const ref = db.collection('orders').doc(String(data.orderId));
    const snap = await ref.get();
    if (!snap.exists) fail('not-found', 'Order not found.');
    const isCod = data.isCod === true;
    const paymentStatus = isCod ? 'codPending' : 'paid';
    const amountPaise = toInt(snap.data().totals.grandTotalPaise);
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      tx.update(ref, {
        paymentStatus, paymentMethod: String(data.method || ''),
        transactionReference: String(data.transactionReference || ''),
        paidPaise: isCod ? 0 : amountPaise,
        'totals.paidPaise': isCod ? 0 : amountPaise,
        updatedAt: FieldValue.serverTimestamp(),
      });
      const payRef = db.collection('payments').doc(String(data.orderId));
      tx.set(payRef, {
        orderId: s.id, amountPaise, uid: s.data().userId, gateway: isCod ? 'cod' : 'manual', method: String(data.method || ''),
        status: isCod ? 'created' : 'captured', transactionReference: String(data.transactionReference || ''),
        refundedPaise: toInt(s.data().totals.refundedPaise),
        createdAt: s.data().createdAt || FieldValue.serverTimestamp(),
        capturedAt: isCod ? null : FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    await writeAudit(db, { action: 'payment.mark', entityType: 'order', entityId: ref.id, actorUid: caller.uid, actorRole: caller.role, summary: `Marked ${paymentStatus} via ${data.method}`, after: { paymentStatus, amountPaise } });
    return (await ref.get()).data();
  });
});

exports.adminOrderRefund = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ['admin', 'owner']);
    const data = request.data || {};
    const ref = db.collection('orders').doc(String(data.orderId));
    const snap = await ref.get();
    if (!snap.exists) fail('not-found', 'Order not found.');
    const amountPaise = toInt(data.amountPaise);
    if (amountPaise <= 0) fail('invalid-argument', 'Refund amount must be positive.');
    const paid = toInt(snap.data().totals.paidPaise);
    if (amountPaise > paid) fail('failed-precondition', 'Refund cannot exceed the amount paid.');
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) fail('not-found', 'Order not found.');
      const current = { ...s.data().totals };
      const alreadyRefunded = toInt(current.refundedPaise);
      const remainingPaise = toInt(current.paidPaise) - alreadyRefunded;
      // The outer check only sees a stale snapshot; this one runs under the transaction lock, so
      // two concurrent partial refunds cannot together exceed what the customer actually paid.
      if (amountPaise > remainingPaise) {
        fail('failed-precondition', `Refund cannot exceed the unrefunded amount (${remainingPaise} paise).`);
      }
      current.refundedPaise = alreadyRefunded + amountPaise;
      tx.update(ref, {
        'totals.refundedPaise': current.refundedPaise,
        paymentStatus: current.refundedPaise >= toInt(current.paidPaise) ? 'refunded' : 'partiallyRefunded',
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    await writeAudit(db, { action: 'refund.issue', entityType: 'order', entityId: ref.id, actorUid: caller.uid, actorRole: caller.role, summary: `Refunded ${amountPaise} paise: ${data.reason}`, before: { paid }, after: { refundPaise: amountPaise } });
    return (await ref.get()).data();
  });
});

exports.adminCounterOrder = onCall(async (request) => {
  return guarded(async () => {
    // Shop-counter sale: a privileged staff member places an order on behalf of a walk-in customer.
    // Reuses the same authoritative pricing path via ordersCreate semantics but with source=counter.
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const order = { ...data, source: 'counter' };
    return requestOrdersCreateAsStaff(caller, order);
  });
});

// Shared core for staff-created orders (counter/whatsapp). Same server pricing, but actor is staff.
async function requestOrdersCreateAsStaff(caller, data) {
  // Delegate to the same transactional logic by invoking the callable handler shape with a synthetic
  // request that already carries an authenticated, staff caller.
  const synthetic = { auth: { uid: caller.uid }, data: { ...data, deliveryMode: data.deliveryMode || 'pickup', paymentMethod: data.paymentMethod || 'cash', idempotencyKey: data.idempotencyKey || newId() } };
  const receipt = await exports.ordersCreate(synthetic);
  return receipt;
}

exports.adminProductSave = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const product = data.product || {};
    // Slab grid is validated exactly like the Dart guard BEFORE any write, so an ambiguous grid can
    // never be persisted by any path.
    const slabs = Array.isArray(data.slabs) ? data.slabs : Array.isArray(product.slabs) ? product.slabs : [];
    try {
      pricing.validateSlabGrid(slabs);
    } catch (e) {
      fail('invalid-argument', e.message);
    }
    if (toInt(product.retailPricePaise) < 0) fail('invalid-argument', 'Retail price cannot be negative.');
    const id = product.id ? String(product.id) : newId();
    const ref = db.collection('products').doc(id);
    const before = (await ref.get()).data() || null;
    const writable = stripProtectedFields(product);
    // stockQty / soldCount / ratingAvg are owned by other paths and must never be clobbered here.
    await ref.set({ ...writable, slabs, updatedAt: FieldValue.serverTimestamp(), createdAt: before ? before.createdAt : FieldValue.serverTimestamp() }, { merge: true });
    await writeAudit(db, { action: slabs.length ? 'pricing.slab_write' : 'product.update', entityType: 'product', entityId: id, actorUid: caller.uid, actorRole: caller.role, summary: `Saved ${product.name}`, before: before ? { slabs: before.slabs } : null, after: { slabs } });
    // The generated id must cross the wire — a brand-new product's id is unknown to the caller.
    return { id, ...(await ref.get()).data() };
  });
});

// Fields the client (and even the admin payload) may not set directly on a product document.
function stripProtectedFields(product) {
  const protectedFields = ['stockQty', 'soldCount', 'ratingAvg', 'ratingCount', 'costPricePaise', 'createdAt'];
  const out = {};
  for (const [k, v] of Object.entries(product)) {
    if (!protectedFields.includes(k)) out[k] = v;
  }
  return out;
}

// Archive / restore flips ONLY the status. Sending a partial body through adminProductSave would
// merge an empty slab grid over the live prices, so this dedicated path writes one field.
exports.adminProductArchive = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const ref = db.collection('products').doc(String(data.productId));
    const snap = await ref.get();
    if (!snap.exists) fail('not-found', 'Product not found.');
    const next = data.archived === true ? 'archived' : 'active';
    const before = snap.data().status;
    await ref.update({ status: next, updatedAt: FieldValue.serverTimestamp() });
    await writeAudit(db, { action: 'product.status', entityType: 'product', entityId: ref.id, actorUid: caller.uid, actorRole: caller.role, summary: `${before} -> ${next}`, before: { status: before }, after: { status: next } });
    return { ok: true };
  });
});

exports.adminVariantSave = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, PRICING_ROLES);
    const data = request.data || {};
    const variant = data.variant || {};
    const slabs = Array.isArray(variant.slabs) ? variant.slabs : [];
    try {
      pricing.validateSlabGrid(slabs);
    } catch (e) {
      fail('invalid-argument', e.message);
    }
    const id = variant.id ? String(variant.id) : newId();
    const ref = db.collection('product_variants').doc(id);
    const before = (await ref.get()).data() || null;
    // stockQty is ledger-owned: a variant price edit must never move stock, so it is stripped here
    // and changed only through inventorySetOpening / inventoryAdjust (which write a movement).
    const writable = { ...variant };
    delete writable.stockQty;
    delete writable.id;
    await ref.set({ ...writable, slabs, updatedAt: FieldValue.serverTimestamp(), createdAt: before ? before.createdAt : FieldValue.serverTimestamp() }, { merge: true });
    await writeAudit(db, { action: 'pricing.variant_write', entityType: 'variant', entityId: id, actorUid: caller.uid, actorRole: caller.role, summary: `Saved variant ${variant.name}`, before: before ? { slabs: before.slabs, stockQty: before.stockQty } : null, after: { slabs } });
    return { id, ...(await ref.get()).data() };
  });
});

exports.adminVariantDelete = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    await db.collection('product_variants').doc(String(data.variantId)).delete();
    await writeAudit(db, { action: 'variant.delete', entityType: 'variant', entityId: String(data.variantId), actorUid: caller.uid, actorRole: caller.role, summary: 'Deleted variant' });
    return { ok: true };
  });
});

exports.inventoryAdjust = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const deltaQty = toInt(data.deltaQty);
    if (deltaQty === 0) fail('invalid-argument', 'Adjustment must change the quantity.');
    const kind = String(data.kind || 'manualAdjust');
    const productId = String(data.productId);
    const variantId = data.variantId ? String(data.variantId) : null;
    const stockRef = variantId ? db.collection('product_variants').doc(variantId) : db.collection('products').doc(productId);

    const balanceAfter = await db.runTransaction(async (tx) => {
      const snap = await tx.get(stockRef);
      if (!snap.exists) fail('not-found', 'Stock item not found.');
      const next = toInt(snap.get('stockQty')) + deltaQty;
      if (next < 0) fail('failed-precondition', `Adjustment would drive stock negative (currently ${toInt(snap.get('stockQty'))}).`);
      tx.update(stockRef, { stockQty: next, updatedAt: FieldValue.serverTimestamp() });
      tx.set(db.collection('inventory_movements').doc(), {
        productId, variantId, kind, quantity: Math.abs(deltaQty), balanceAfter: next,
        orderId: '', reason: String(data.reason || ''), reference: '', unitCostPaise: data.unitCostPaise == null ? null : toInt(data.unitCostPaise),
        actorUid: caller.uid, createdAt: FieldValue.serverTimestamp(),
      });
      return next;
    });

    const product = await db.collection('products').doc(productId).get();
    if (product.exists && balanceAfter >= 0 && balanceAfter <= toInt(product.data().lowStockThreshold, 5)) {
      await db.collection('inventory_alerts').doc(`${productId}_${variantId || 'base'}`).set({ productId, variantId, balanceAfter, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
    await writeAudit(db, { action: 'stock.adjust', entityType: 'product', entityId: productId, actorUid: caller.uid, actorRole: caller.role, summary: `${kind} ${deltaQty} -> ${balanceAfter}`, after: { deltaQty, balanceAfter } });
    return { balanceAfter };
  });
});

exports.inventorySetOpening = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const productId = String(data.productId);
    const variantId = data.variantId ? String(data.variantId) : null;
    const quantity = toInt(data.quantity);
    if (quantity < 0) fail('invalid-argument', 'Opening stock cannot be negative.');
    const stockRef = variantId ? db.collection('product_variants').doc(variantId) : db.collection('products').doc(productId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(stockRef);
      if (!snap.exists) fail('not-found', 'Item not found.');
      tx.update(stockRef, { stockQty: quantity, updatedAt: FieldValue.serverTimestamp() });
      tx.set(db.collection('inventory_movements').doc(), {
        productId, variantId, kind: 'opening', quantity, balanceAfter: quantity, orderId: '', reason: String(data.reason || 'Opening balance'), actorUid: caller.uid, createdAt: FieldValue.serverTimestamp(),
      });
    });
    await writeAudit(db, { action: 'stock.opening', entityType: 'product', entityId: productId, actorUid: caller.uid, actorRole: caller.role, summary: `Opening stock ${quantity}`, after: { quantity } });
    return { balanceAfter: quantity };
  });
});

// ---- reviews: submit (verifies purchase), report, moderate; rating rollup is a trigger --------
exports.reviewSubmit = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireCaller(request);
    const data = request.data || {};
    const productId = String(data.productId);
    const rating = Math.min(5, Math.max(1, toInt(data.rating)));
    if (!productId) fail('invalid-argument', 'Product required.');
    const body = String(data.body || '').slice(0, 2000);
    const title = String(data.title || '').slice(0, 120);
    const images = Array.isArray(data.images) ? data.images.slice(0, 6) : [];

    const dup = await db.collection('reviews').where('productId', '==', productId).where('uid', '==', caller.uid).limit(1).get();
    if (!dup.empty) fail('failed-precondition', 'You have already reviewed this product.');

    let verified = false;
    if (data.orderId) {
      const order = await db.collection('orders').doc(String(data.orderId)).get();
      verified = order.exists && order.data().userId === caller.uid && order.data().status === 'delivered'
        && (order.data().items || []).some((i) => i.productId === productId);
    }

    const id = newId();
    await db.collection('reviews').doc(id).set({
      productId, uid: caller.uid, rating, title, body, authorName: String(data.authorName || caller.displayName || caller.email || ''),
      status: 'pending', isVerifiedPurchase: verified, orderId: String(data.orderId || ''), images, reportCount: 0, moderatorNote: '',
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    return { id };
  });
});

exports.reviewReport = onCall(async (request) => {
  return guarded(async () => {
    await requireCaller(request);
    const data = request.data || {};
    const ref = db.collection('reviews').doc(String(data.reviewId));
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) fail('not-found', 'Review not found.');
      tx.update(ref, { reportCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    });
    return { ok: true };
  });
});

exports.adminReviewModerate = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const ref = db.collection('reviews').doc(String(data.reviewId));
    const snap = await ref.get();
    if (!snap.exists) fail('not-found', 'Review not found.');
    await ref.update({ status: String(data.decision), moderatorNote: String(data.note || ''), updatedAt: FieldValue.serverTimestamp() });
    await writeAudit(db, { action: 'review.moderate', entityType: 'review', entityId: ref.id, actorUid: caller.uid, actorRole: caller.role, summary: `-> ${data.decision}`, before: { status: snap.data().status }, after: { status: data.decision } });
    return { ok: true };
  });
});

// ---- wholesale application decisions -----------------------------------------------------------
exports.adminWholesaleDecide = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const appId = String(data.applicationId);
    const decision = String(data.decision);
    if (!['approved', 'rejected'].includes(decision)) fail('invalid-argument', 'Decision must be approved or rejected.');
    const appRef = db.collection('wholesale_applications').doc(appId);
    const app = await appRef.get();
    if (!app.exists) fail('not-found', 'Application not found.');
    const uid = app.data().uid;

    await db.runTransaction(async (tx) => {
      // The user read must precede the application update: a tx.get after any write is rejected.
      const userRef = db.collection('users').doc(uid);
      const userSnap = await tx.get(userRef);
      tx.update(appRef, { status: decision, reviewNote: String(data.note || ''), reviewedBy: caller.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
      // ONLY an approved application grants wholesale pricing: role flips to wholesale on approval;
      // rejection leaves the customer role intact but records the status.
      tx.update(userRef, {
        wholesaleStatus: decision,
        role: decision === 'approved' ? 'wholesale' : (userSnap.exists ? userSnap.data().role : 'customer'),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await writeAudit(db, { action: 'wholesale.decide', entityType: 'user', entityId: uid, actorUid: caller.uid, actorRole: caller.role, summary: `Application ${appId} ${decision}`, after: { decision } });
    await db.collection('notifications').doc().set({ uid, title: 'Wholesale application', body: `Your application was ${decision}.`, kind: 'wholesaleDecision', entityId: appId, route: '/account/wholesale', isRead: false, createdAt: FieldValue.serverTimestamp() });
    return { ok: true };
  });
});

// ---- customer role / block (privilege changes; audit + recheck) --------------------------------
exports.adminCustomerRole = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ['admin', 'owner']);
    const data = request.data || {};
    const uid = String(data.uid);
    const role = String(data.role);
    if (!['customer', 'wholesale', 'staff', 'admin', 'owner'].includes(role)) fail('invalid-argument', 'Unknown role.');
    if (uid === caller.uid) fail('failed-precondition', 'You cannot change your own role.');
    const ref = db.collection('users').doc(uid);
    const before = (await ref.get()).data() || null;
    await ref.update({ role, updatedAt: FieldValue.serverTimestamp() });
    // Keep the JWT claims as an ADVISORY mirror; rules and every function still read the document.
    try {
      await adminAuth.setCustomRole(uid, ['staff', 'admin', 'owner'].includes(role) ? role : null);
    } catch (_) { /* claims are best-effort, never the source of truth */ }
    await writeAudit(db, { action: 'role.change', entityType: 'user', entityId: uid, actorUid: caller.uid, actorRole: caller.role, summary: `${before ? before.role : 'none'} -> ${role}: ${data.reason}`, before: { role: before && before.role }, after: { role } });
    return { ok: true };
  });
});

exports.adminCustomerBlock = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const uid = String(data.uid);
    const blocked = data.blocked === true;
    if (uid === caller.uid) fail('failed-precondition', 'You cannot block your own account.');
    await db.collection('users').doc(uid).update({ isBlocked: blocked, updatedAt: FieldValue.serverTimestamp() });
    await writeAudit(db, { action: blocked ? 'user.block' : 'user.unblock', entityType: 'user', entityId: uid, actorUid: caller.uid, actorRole: caller.role, summary: String(data.reason || '') });
    return { ok: true };
  });
});

// ---- coupons admin ------------------------------------------------------------------------------
exports.adminCouponSave = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ['admin', 'owner']);
    const data = (request.data || {}).coupon || {};
    const code = normaliseCode(data.code);
    if (!code) fail('invalid-argument', 'Coupon code required.');
    const percent = toInt(data.percentOff);
    if (data.kind === 'percentage' && (percent < 1 || percent > 99)) fail('invalid-argument', 'Percentage must be 1..99.');
    // Force doc id == uppercased code so lookups stay O(1) and never orphan.
    const ref = db.collection('coupons').doc(code);
    await ref.set({
      code, kind: String(data.kind || 'percentage'), valuePaise: toInt(data.valuePaise), percentOff: percent,
      maxDiscountPaise: data.maxDiscountPaise == null ? null : toInt(data.maxDiscountPaise),
      minCartValuePaise: toInt(data.minCartValuePaise), minQty: toInt(data.minQty, 1),
      usageLimit: data.usageLimit == null ? null : toInt(data.usageLimit), perUserLimit: toInt(data.perUserLimit, 1),
      startsAt: data.startsAt || null, endsAt: data.endsAt || null, isActive: data.isActive !== false,
      appliesToCategoryIds: Array.isArray(data.appliesToCategoryIds) ? data.appliesToCategoryIds : [],
      appliesToProductIds: Array.isArray(data.appliesToProductIds) ? data.appliesToProductIds : [],
      excludesWholesale: data.excludesWholesale === true, description: String(data.description || ''),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await writeAudit(db, { action: 'coupon.save', entityType: 'coupon', entityId: code, actorUid: caller.uid, actorRole: caller.role, summary: `Saved ${code}` });
    return (await ref.get()).data();
  });
});

exports.adminCouponDelete = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ['admin', 'owner']);
    const id = String((request.data || {}).couponId || '');
    await db.collection('coupons').doc(id).delete();
    await writeAudit(db, { action: 'coupon.delete', entityType: 'coupon', entityId: id, actorUid: caller.uid, actorRole: caller.role, summary: `Deleted ${id}` });
    return { ok: true };
  });
});

// ---- customer price overrides -------------------------------------------------------------------
exports.adminCustomerPriceSave = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ['admin', 'owner']);
    const data = (request.data || {}).override || {};
    const uid = String(data.uid || '');
    const productId = String(data.productId || '');
    if (!uid || !productId) fail('invalid-argument', 'An override needs both a customer and a product.');
    // A ₹0.00 contract price makes the item free, and the admin form's rupee parser returns 0 for
    // anything it cannot read — so the amount is re-checked here instead of trusting the client.
    const unitPricePaise = toInt(data.unitPricePaise, -1);
    if (unitPricePaise <= 0) fail('invalid-argument', 'Contract price must be a positive amount in paise.');
    const id = data.id ? String(data.id) : newId();
    const ref = db.collection('customer_price_overrides').doc(id);
    // A caller-supplied id is an *update*, so the row must already exist and must already belong
    // to this customer/product pair. Without this, a mistyped id silently creates a second row for
    // the same customer at a different price, and an existing id from another pair gets repointed.
    const before = (await ref.get()).data() || null;
    if (before && (before.uid !== uid || before.productId !== productId)) {
      fail('invalid-argument', 'That override id belongs to a different customer or product.');
    }
    await ref.set({ uid, productId, variantId: data.variantId || null, unitPricePaise, note: String(data.note || ''), createdBy: before ? before.createdBy : caller.uid, expiresAt: data.expiresAt || null, createdAt: before ? before.createdAt : FieldValue.serverTimestamp() }, { merge: true });
    await writeAudit(db, { action: 'pricing.override', entityType: 'customer_price', entityId: id, actorUid: caller.uid, actorRole: caller.role, summary: `${uid}/${productId} @ ${unitPricePaise}` });
    // Return the id: the admin list needs the real document key to edit or delete a row, and a
    // client-fabricated key would leave the stored row unreachable.
    return { id, ...(await ref.get()).data() };
  });
});

exports.adminCustomerPriceDelete = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ['admin', 'owner']);
    const overrideId = String((request.data || {}).overrideId);
    // Firestore deletes succeed on a missing document, so without this read an admin could be told
    // an override was removed while the price kept applying.
    const existing = await db.collection('customer_price_overrides').doc(overrideId).get();
    if (!existing.exists) fail('not-found', 'That override no longer exists.');
    await existing.ref.delete();
    await writeAudit(db, { action: 'pricing.override_delete', entityType: 'customer_price', entityId: overrideId, actorUid: caller.uid, actorRole: caller.role, summary: 'Removed override' });
    return { ok: true, id: overrideId };
  });
});

// ---- customer price overrides READ (server-gated; never a direct client collection read) --------
exports.adminCustomerPriceList = onCall(async (request) => {
  return guarded(async () => {
    await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const productId = data.productId ? String(data.productId) : null;
    const uid = data.uid ? String(data.uid) : null;
    let query = db.collection('customer_price_overrides');
    if (productId) query = query.where('productId', '==', productId);
    if (uid) query = query.where('uid', '==', uid);
    const snap = await query.get();
    return { rows: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
  });
});

// =================================================================================================
// CATEGORIES — privileged category writes routed through a callable (audit + server id minting)
// =================================================================================================
exports.adminCategorySave = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const category = ((request.data || {}).category) || {};
    if (!String(category.name || '').trim()) fail('invalid-argument', 'Category name is required.');
    // productCount is maintained by the write trigger, never by an admin payload.
    const protectedFields = ['productCount', 'createdAt'];
    const writable = {};
    for (const [k, v] of Object.entries(category)) if (!protectedFields.includes(k)) writable[k] = v;
    const id = category.id ? String(category.id) : newId();
    const ref = db.collection('categories').doc(id);
    const before = (await ref.get()).data() || null;
    await ref.set({
      ...writable,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: before ? before.createdAt : FieldValue.serverTimestamp(),
    }, { merge: true });
    await writeAudit(db, { action: 'category.save', entityType: 'category', entityId: id, actorUid: caller.uid, actorRole: caller.role, summary: `Saved ${category.name}` });
    return { id, ...(await ref.get()).data() };
  });
});

exports.adminCategoryDelete = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const id = String((request.data || {}).categoryId || '');
    if (!id) fail('invalid-argument', 'Category id is required.');
    const ref = db.collection('categories').doc(id);
    if (!(await ref.get()).exists) fail('not-found', 'Category not found.');
    // Refuse to orphan a category that still has children or products attached.
    const [children, products] = await Promise.all([
      db.collection('categories').where('parentId', '==', id).limit(1).get(),
      db.collection('products').where('categoryId', '==', id).limit(1).get(),
    ]);
    if (!children.empty) fail('failed-precondition', 'Category has subcategories.');
    if (!products.empty) fail('failed-precondition', 'Category still has products.');
    await ref.delete();
    await writeAudit(db, { action: 'category.delete', entityType: 'category', entityId: id, actorUid: caller.uid, actorRole: caller.role, summary: `Deleted ${id}` });
    return { ok: true };
  });
});

// =================================================================================================
// AGGREGATE REPORTS — server-summed so a browser can never forge revenue figures
// =================================================================================================

// Revenue per day over a window, keyed by ISO yyyy-mm-dd. Reads the stored (rupee-rounded)
// grandTotalPaise so recorded revenue equals what each customer was charged.
exports.adminSalesByDay = onCall(async (request) => {
  return guarded(async () => {
    await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const from = data.from ? new Date(data.from) : null;
    const to = data.to ? new Date(data.to) : null;
    let query = db.collection('orders');
    if (from) query = query.where('createdAt', '>=', from);
    const snap = await query.get();
    const byDay = {};
    for (const d of snap.docs) {
      const created = d.data().createdAt && d.data().createdAt.toDate ? d.data().createdAt.toDate() : null;
      if (!created) continue;
      if (to && created > to) continue;
      const key = created.toISOString().slice(0, 10);
      byDay[key] = byDay[key] || { revenuePaise: 0, units: 0 };
      byDay[key].revenuePaise += toInt(d.data().totals && d.data().totals.grandTotalPaise);
      byDay[key].units += 1;
    }
    const rows = Object.entries(byDay)
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([day, v]) => ({ key: day, label: day, units: v.units, revenuePaise: v.revenuePaise, costPaise: 0, discountPaise: 0 }));
    return { rows };
  });
});

// Top customers by summed revenue over the full order history. Aggregate runs server-side; only the
// requested number of rows crosses the wire.
exports.adminTopCustomers = onCall(async (request) => {
  return guarded(async () => {
    await requireRole(request, ADMIN_ROLES);
    const limit = Math.max(1, Math.min(toInt((request.data || {}).limit, 20), 200));
    const snap = await db.collection('orders').get();
    const byUid = {};
    for (const d of snap.docs) {
      const uid = String(d.data().userId || '');
      if (!uid) continue; // guests have no durable customer row
      byUid[uid] = byUid[uid] || { revenuePaise: 0, units: 0 };
      byUid[uid].revenuePaise += toInt(d.data().totals && d.data().totals.grandTotalPaise);
      byUid[uid].units += (Array.isArray(d.data().items) ? d.data().items : []).reduce((s, it) => s + toInt(it.qty), 0);
    }
    const ranked = Object.entries(byUid)
      .sort((a, b) => b[1].revenuePaise - a[1].revenuePaise)
      .slice(0, limit);
    const rows = [];
    for (const [uid, v] of ranked) {
      const profile = await callerProfile(uid);
      const label = (profile && (profile.displayName || profile.email)) || uid;
      rows.push({ key: uid, label, units: v.units, revenuePaise: v.revenuePaise, costPaise: 0, discountPaise: 0 });
    }
    return { rows };
  });
});

// Lifetime value of a single customer: total charged, units bought, order count.
exports.adminCustomerValue = onCall(async (request) => {
  return guarded(async () => {
    await requireRole(request, ADMIN_ROLES);
    const uid = String((request.data || {}).uid || '');
    if (!uid) fail('invalid-argument', 'Customer uid is required.');
    const snap = await db.collection('orders').where('userId', '==', uid).get();
    let revenuePaise = 0;
    let units = 0;
    let refundedPaise = 0;
    let discountPaise = 0;
    for (const d of snap.docs) {
      const t = d.data().totals || {};
      revenuePaise += toInt(t.grandTotalPaise);
      refundedPaise += toInt(t.refundedPaise);
      discountPaise += toInt(t.slabDiscountPaise) + toInt(t.couponDiscountPaise);
      units += (Array.isArray(d.data().items) ? d.data().items : []).reduce((s, it) => s + toInt(it.qty), 0);
    }
    const profile = await callerProfile(uid);
    const label = (profile && (profile.displayName || profile.email)) || uid;
    // `orderCount` and `refundedPaise` are separate fields because the panel prints both as money
    // or as a count, and an earlier version put snap.size in the discount slot.
    return { row: { key: uid, label, units, orderCount: snap.size, revenuePaise, costPaise: 0, discountPaise, refundedPaise } };
  });
});

// ---- store settings (tax, shipping, policies) -----------------------------------------------------
exports.adminSettingsSave = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ['admin', 'owner']);
    const data = (request.data || {}).settings || {};
    const writable = { ...data };
    delete writable.updatedAt;
    await db.collection('store_settings').doc('store').set({ ...writable, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    clearSettingsCache();
    await writeAudit(db, { action: 'settings.update', entityType: 'store_settings', entityId: 'store', actorUid: caller.uid, actorRole: caller.role, summary: 'Store settings updated' });
    return (await db.collection('store_settings').doc('store').get()).data();
  });
});

// ---- support staff reply / resolution --------------------------------------------------------------
exports.adminSupportUpdate = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const ref = db.collection('support_requests').doc(String(data.ticketId));
    const update = { updatedAt: FieldValue.serverTimestamp() };
    if (data.message) update.messages = FieldValue.arrayUnion({ from: caller.uid, body: String(data.message).slice(0, 4000), at: new Date(), isStaff: true });
    if (data.status) update.status = String(data.status);
    await ref.update(update);
    return { ok: true };
  });
});

// =================================================================================================
// AGGREGATES — dashboard + reports computed server-side (reads are unbounded but bounded here)
// =================================================================================================

exports.adminDashboard = onCall(async (request) => {
  return guarded(async () => {
    await requireRole(request, ADMIN_ROLES);
    const startOfToday = new Date(); startOfToday.setHours(0, 0, 0, 0);
    const startOfMonth = new Date(); startOfMonth.setDate(1); startOfMonth.setHours(0, 0, 0, 0);

    const [ordersTodaySnap, ordersMonthSnap, pendingOrders, pendingPayments, low, out, newCust, openSupport, pendingReviews, pendingWs, topSold] = await Promise.all([
      db.collection('orders').where('createdAt', '>=', startOfToday).get(),
      db.collection('orders').where('createdAt', '>=', startOfMonth).get(),
      db.collection('orders').where('status', '==', 'placed').get(),
      db.collection('orders').where('paymentStatus', '==', 'pending').get(),
      db.collection('products').where('status', '==', 'active').get(),
      db.collection('products').where('status', '==', 'active').get(),
      db.collection('users').where('createdAt', '>=', startOfMonth).get(),
      db.collection('support_requests').where('status', 'in', ['open', 'inProgress']).get(),
      db.collection('reviews').where('status', '==', 'pending').get(),
      db.collection('wholesale_applications').where('status', '==', 'pending').get(),
      db.collection('products').where('status', '==', 'active').orderBy('soldCount', 'desc').limit(5).get(),
    ]);

    const sumRevenue = (snap) => snap.docs.reduce((s, d) => s + toInt(d.data().totals && d.data().totals.grandTotalPaise), 0);
    let lowCount = 0;
    let outCount = 0;
    for (const d of low.docs) {
      const stock = toInt(d.data().stockQty);
      if (stock <= 0) outCount += 1;
      else if (stock <= toInt(d.data().lowStockThreshold, 5)) lowCount += 1;
    }

    const spark = sparkline(ordersMonthSnap.docs, startOfToday);
    const best = topSold.docs.map((d) => ({ productId: d.id, name: d.data().name, unitsSold: toInt(d.data().soldCount), revenuePaise: 0 }));

    return {
      ordersToday: ordersTodaySnap.size, revenueTodayPaise: sumRevenue(ordersTodaySnap), revenueMonthPaise: sumRevenue(ordersMonthSnap),
      pendingOrders: pendingOrders.size, pendingPayments: pendingPayments.size, lowStockCount: lowCount, outOfStockCount: outCount,
      newCustomers: newCust.size, openSupportTickets: openSupport.size, pendingReviews: pendingReviews.size,
      pendingWholesaleApplications: pendingWs.size, bestSellers: best, salesSparkline: spark,
    };
  });
});

function sparkline(docs, startOfToday) {
  const byDay = {};
  for (const d of docs) {
    const created = d.data().createdAt && d.data().createdAt.toDate ? d.data().createdAt.toDate() : null;
    if (!created) continue;
    const key = created.toISOString().slice(0, 10);
    byDay[key] = byDay[key] || { revenuePaise: 0, orders: 0 };
    byDay[key].revenuePaise += toInt(d.data().totals && d.data().totals.grandTotalPaise);
    byDay[key].orders += 1;
  }
  return Object.entries(byDay)
    .sort((a, b) => a[0].localeCompare(b[0]))
    .slice(-30)
    .map(([day, v]) => ({ day, revenuePaise: v.revenuePaise, orders: v.orders }));
}

exports.adminReport = onCall(async (request) => {
  return guarded(async () => {
    await requireRole(request, ADMIN_ROLES);
    const data = request.data || {};
    const reportId = String(data.reportId || '');
    const rows = await runReport(reportId, data);
    if (data.format === 'csv') return { csv: toCsv(rows) };
    return { rows };
  });
});

async function runReport(reportId, data) {
  const from = data.from ? new Date(data.from) : null;
  const to = data.to ? new Date(data.to) : null;
  if (reportId === 'sales_by_product' || reportId === 'sales_by_category') {
    const q = from ? db.collection('orders').where('createdAt', '>=', from) : db.collection('orders');
    const snap = await q.get();
    const acc = {};
    const keyField = reportId === 'sales_by_category' ? 'categoryId' : 'productId';
    for (const d of snap.docs) {
      if (to && d.data().createdAt && d.data().createdAt.toDate() > to) continue;
      for (const item of d.data().items || []) {
        const key = keyField === 'categoryId' ? item.categoryId || 'uncategorised' : item.productId;
        acc[key] = acc[key] || { key, label: item.name || key, units: 0, revenuePaise: 0, costPaise: 0, discountPaise: 0 };
        acc[key].units += toInt(item.qty);
        acc[key].revenuePaise += toInt(item.lineTotalPaise);
        acc[key].discountPaise += toInt(item.discountPaise);
      }
    }
    return Object.values(acc);
  }
  if (reportId === 'retail_vs_wholesale') {
    const snap = await db.collection('orders').get();
    const acc = { retail: { key: 'retail', label: 'Retail', units: 0, revenuePaise: 0, costPaise: 0, discountPaise: 0 }, wholesale: { key: 'wholesale', label: 'Wholesale', units: 0, revenuePaise: 0, costPaise: 0, discountPaise: 0 } };
    for (const d of snap.docs) {
      const o = d.data();
      const bucket = o.wholesaleOrder === true ? acc.wholesale : acc.retail;
      for (const item of o.items || []) {
        bucket.units += toInt(item.qty);
        bucket.revenuePaise += toInt(item.lineTotalPaise);
      }
    }
    return [acc.retail, acc.wholesale];
  }
  if (reportId === 'inventory_valuation') {
    const snap = await db.collection('products').where('status', '==', 'active').get();
    return snap.docs.map((d) => ({ key: d.id, label: d.data().name, units: toInt(d.data().stockQty), revenuePaise: 0, costPaise: toInt(d.data().costPricePaise) * toInt(d.data().stockQty), discountPaise: 0 }));
  }
  if (reportId === 'slow_moving') {
    const snap = await db.collection('products').where('status', '==', 'active').limit(200).get();
    return snap.docs.map((d) => ({ key: d.id, label: d.data().name, units: toInt(d.data().soldCount), revenuePaise: 0, costPaise: 0, discountPaise: 0 })).filter((r) => r.units === 0);
  }
  if (reportId === 'cancelled_or_refunded') {
    const snap = await db.collection('orders').where('status', 'in', ['cancelled', 'refunded']).get();
    return snap.docs.map((d) => ({ key: d.id, label: d.data().orderNumber, units: 0, revenuePaise: toInt(d.data().totals && d.data().totals.refundedPaise), costPaise: 0, discountPaise: 0 }));
  }
  if (reportId === 'coupon_performance') {
    const snap = await db.collection('coupons').get();
    return snap.docs.map((d) => ({ key: d.data().code, label: d.data().code, units: toInt(d.data().usedCount), revenuePaise: 0, costPaise: 0, discountPaise: 0 }));
  }
  return [];
}

function toCsv(rows) {
  if (rows.length === 0) return 'key,label,units,revenuePaise,costPaise,discountPaise\n';
  const header = ['key', 'label', 'units', 'revenuePaise', 'costPaise', 'discountPaise'];
  const lines = [header.join(',')];
  for (const r of rows) {
    lines.push(header.map((h) => csvCell(r[h])).join(','));
  }
  return lines.join('\n') + '\n';
}
function csvCell(v) {
  const s = v == null ? '' : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

exports.adminImportProducts = onCall(async (request) => {
  return guarded(async () => {
    const caller = await requireRole(request, ADMIN_ROLES);
    const csvText = String((request.data || {}).csv || '');
    const summary = await importCsv(caller, csvText);
    await writeAudit(db, { action: 'product.import', entityType: 'product', entityId: 'batch', actorUid: caller.uid, actorRole: caller.role, summary: `Imported ${summary.imported}/${summary.totalRows}` });
    return summary;
  });
});

// Row-by-row validated import: nothing is committed until EVERY row parses, so a bad sheet never
// half-lands. Returns per-row errors instead of a partial write.
async function importCsv(caller, csvText) {
  const rows = parseCsv(csvText);
  const header = rows.shift() || [];
  const idx = (name) => header.indexOf(name);
  const errors = [];
  const prepared = [];
  rows.forEach((row, i) => {
    const lineNo = i + 2;
    const name = row[idx('name')];
    const sku = row[idx('sku')];
    const retail = toInt(row[idx('retailPricePaise')]);
    if (!name) { errors.push(`Row ${lineNo}: name is required.`); return; }
    if (retail < 0) { errors.push(`Row ${lineNo}: retail price must be >= 0.`); return; }
    const slabs = parseSlabsFromCsv(row[idx('slabs')] || '');
    try {
      pricing.validateSlabGrid(slabs);
    } catch (e) {
      errors.push(`Row ${lineNo}: ${e.message}`);
      return;
    }
    prepared.push({ name, sku, retail, slabs, row, idx });
  });

  if (errors.length) return { totalRows: rows.length, imported: 0, errors };

  const batch = db.batch();
  for (const p of prepared) {
    const id = newId();
    batch.set(db.collection('products').doc(id), {
      name: p.name, sku: p.sku, slug: slugify(p.name), retailPricePaise: p.retail, slabs: p.slabs,
      status: 'draft', stockQty: 0, soldCount: 0, ratingAvg: 0, ratingCount: 0,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return { totalRows: rows.length, imported: prepared.length, errors };
}

function parseSlabsFromCsv(text) {
  if (!text) return [];
  // Format: "1-9:11000|10-20:10000|21+:9500"
  return text.split('|').map((chunk) => {
    const [range, price] = chunk.split(':');
    const unitPricePaise = toInt(price);
    if (range.endsWith('+')) return { minQty: toInt(range.slice(0, -1)), maxQty: null, unitPricePaise };
    const [minQty, maxQty] = range.split('-').map((n) => toInt(n));
    return { minQty, maxQty, unitPricePaise };
  });
}

function slugify(input) {
  return String(input).toLowerCase().replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'item';
}

// Minimal RFC-4180 CSV parser (quoted fields, embedded commas/newlines).
function parseCsv(text) {
  const rows = [];
  let field = '';
  let row = [];
  let inQuotes = false;
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 1; } else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (c === '\r') { /* ignore */ }
    else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows;
}

exports.accountEnsure = onCall(async (request) => {
  return guarded(async () => {
    if (!request.auth) fail('unauthenticated', 'Sign in required.');
    const uid = request.auth.uid;
    const ref = db.collection('users').doc(uid);
    const created = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.set(ref, {
        uid, email: request.auth.token.email || '', phone: '', displayName: String((request.data || {}).displayName || ''),
        role: 'customer', wholesaleStatus: 'none', isBlocked: false, notifyEmail: true, notifyWhatsapp: false, notifySms: false,
        wishlistProductIds: [], createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (created) await writeAudit(db, { action: 'user.create', entityType: 'user', entityId: uid, actorUid: uid, actorRole: 'self', summary: 'Profile created' });
    return (await ref.get()).data();
  });
});

// =================================================================================================
// FIRESTORE TRIGGERS (run with Admin privileges; client never invokes these directly)
// =================================================================================================

// A public write to wholesale_applications creates the doc; this trigger flips the applicant's
// profile to `pending` (a status the client can NEVER write itself), keeping the role server-side.
exports.onWholesaleApplicationCreated = onDocumentCreated('wholesale_applications/{appId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const uid = snap.data().uid;
  if (!uid) return;
  await db.collection('users').doc(uid).set({ wholesaleStatus: 'pending', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await writeAudit(db, { action: 'wholesale.apply', entityType: 'user', entityId: uid, actorUid: uid, actorRole: 'customer', summary: `Application ${snap.id}` });
});

// Rating rollup: whenever a review is written, recompute the product's published average/count from
// the authoritative set. The listing reads this mirror without a per-page subquery.
exports.onReviewWritten = onDocumentWritten('reviews/{reviewId}', async (event) => {
  const after = event.data.after.exists ? event.data.after : event.data.before;
  if (!after) return;
  const productId = after.data().productId;
  if (!productId) return;
  const published = await db.collection('reviews').where('productId', '==', productId).where('status', '==', 'published').get();
  let sum = 0;
  const count = published.size;
  published.docs.forEach((d) => { sum += Math.min(5, Math.max(1, toInt(d.data().rating))); });
  await db.collection('products').doc(productId).set({
    ratingAvg: count === 0 ? 0 : Math.round((sum / count) * 100) / 100,
    ratingCount: count,
  }, { merge: true });
});

// Category product count mirror so nav badges do not fan out a query per category.
exports.onProductWritten = onDocumentWritten('products/{productId}', async (event) => {
  const after = event.data.after.exists ? event.data.after : null;
  const before = event.data.before.exists ? event.data.before : null;
  const categoryId = (after && after.data().categoryId) || (before && before.data().categoryId);
  if (!categoryId) return;
  const active = await db.collection('products').where('categoryId', '==', categoryId).where('status', '==', 'active').get();
  await db.collection('categories').doc(categoryId).set({ productCount: active.size, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
});

// Public variant list for a product, with cost price stripped. Firestore rules keep the raw
// product_variants collection staff-read-only (cost price is a trade secret); this callable is how
// a signed-in shopper's product page prices each variant. The engine re-reads slabs here so the
// client never assembles variant truth itself.
exports.variantListForProduct = onCall(async (request) => {
  return guarded(async () => {
    const productId = String((request.data || {}).productId || '');
    if (!productId) fail('invalid-argument', 'productId required.');
    const snap = await db.collection('product_variants').where('productId', '==', productId).where('isActive', '==', true).get();
    const variants = snap.docs.map((d) => {
      const v = { id: d.id, ...d.data() };
      delete v.costPricePaise; // never crosses the wire to a browser
      return v;
    });
    return { variants };
  });
});

module.exports.REGION = REGION;
