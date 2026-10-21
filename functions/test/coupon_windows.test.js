'use strict';

// F2 regression suite: every date-shaped value is read as an INSTANT, and both the preview
// (`couponsQuote`) and the charge (`ordersCreate`) obey the coupon window.
//
// The bug being pinned: `now < coupon.startsAt` compared a millisecond NUMBER against a Firestore
// Timestamp OBJECT. Comparisons against an object coerce to NaN, and every NaN comparison is false,
// so BOTH guards silently passed — an expired code and a code that has not started yet both kept
// discounting. The same class of bug sat in the price-override expiry test.
//
// Two halves on purpose:
//   * the pure rules, run against a fixed instant so no test depends on the wall clock, and
//   * the real callables, which only ever see `Date.now()`, so those cases use relative dates.

const test = require('node:test');
const assert = require('node:assert/strict');

const { createHarness } = require('./support/harness');
const { Timestamp } = require('./support/fake-firestore');
const checkout = require('../lib/checkout');
const { toMillis } = require('../lib/coerce');

const h = createHarness();

const UID_A = 'uid-buyer-a';
const UID_WHOLESALE = 'uid-wholesale';
const NOW = Date.UTC(2026, 10, 1, 12, 0, 0); // a fixed instant for the pure half
const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;

// The four shapes a window bound actually arrives in: a document written by the SDK carries a
// Timestamp, a callable payload carries an ISO string, a CSV import carries millis, and a test or a
// migration can hand over a Date. All four must mean the same instant.
const SHAPES = [
  ['a Firestore Timestamp', (ms) => Timestamp.fromDate(new Date(ms))],
  ['an ISO string', (ms) => new Date(ms).toISOString()],
  ['epoch milliseconds', (ms) => ms],
  ['a Date object', (ms) => new Date(ms)],
];

function couponDoc(overrides = {}) {
  return {
    code: 'PURE',
    kind: 'flat',
    valuePaise: 500,
    isActive: true,
    usedCount: 0,
    usageLimit: null,
    perUserLimit: 1,
    minQty: 1,
    minCartValuePaise: 0,
    startsAt: null,
    endsAt: null,
    ...overrides,
  };
}

const ONE_LINE = [{ productId: 'p1', categoryId: 'c1', qty: 1, lineTotalPaise: 10000 }];

function quote(coupon, opts = {}) {
  return checkout.couponDiscount(coupon, ONE_LINE, { wholesale: false, cartUnits: 1, now: NOW, ...opts });
}

test.beforeEach(() => {
  h.reset();
  h.settings();
  h.product('p1');
  h.user(UID_A, { email: 'a@example.test' });
  h.user(UID_WHOLESALE, { role: 'wholesale', wholesaleStatus: 'approved' });
});

// ---- the pure rule, one test per date shape -----------------------------------------------------

for (const [label, build] of SHAPES) {
  test(`${label} past its endsAt is not redeemable`, () => {
    assert.equal(checkout.couponIsRedeemable(couponDoc({ endsAt: build(NOW - MINUTE) }), NOW), false);
    assert.deepEqual(quote(couponDoc({ endsAt: build(NOW - MINUTE) })), {
      discountPaise: 0,
      freeShipping: false,
      reason: checkout.COUPON_INVALID,
    });
  });

  test(`${label} before its startsAt is not redeemable`, () => {
    assert.equal(checkout.couponIsRedeemable(couponDoc({ startsAt: build(NOW + MINUTE) }), NOW), false);
    assert.equal(quote(couponDoc({ startsAt: build(NOW + MINUTE) })).reason, checkout.COUPON_INVALID);
  });

  test(`${label} inside the window is redeemable, and both boundaries are inclusive`, () => {
    assert.equal(checkout.couponIsRedeemable(couponDoc({ startsAt: build(NOW - HOUR), endsAt: build(NOW + HOUR) }), NOW), true);
    assert.equal(checkout.couponIsRedeemable(couponDoc({ startsAt: build(NOW), endsAt: build(NOW) }), NOW), true);
    assert.equal(quote(couponDoc({ startsAt: build(NOW - HOUR), endsAt: build(NOW + HOUR) })).discountPaise, 500);
  });

  test(`${label} one millisecond past endsAt is already expired`, () => {
    assert.equal(checkout.couponIsRedeemable(couponDoc({ endsAt: build(NOW - 1) }), NOW), false);
  });
}

test('a null or absent bound means "unbounded", not "expired in 1970"', () => {
  assert.equal(toMillis(null), null);
  assert.equal(checkout.couponIsRedeemable(couponDoc(), NOW), true);
  assert.equal(checkout.couponIsRedeemable(couponDoc({ endsAt: null, startsAt: null }), NOW), true);
});

test('DOCUMENTED TOLERANCE: an unreadable date is treated as no constraint', () => {
  // Deliberate, and load-bearing: `toMillis('not a date')` returns null rather than 0. Coercing a
  // corrupt value to 0 would expire every coupon that touches it, which is a store-wide outage
  // disguised as a safety check. Fixing the document is the right response, not failing closed here.
  assert.equal(toMillis('not a date'), null);
  assert.equal(checkout.couponIsRedeemable(couponDoc({ endsAt: 'not a date' }), NOW), true);
});

test('an inactive coupon and an exhausted usageLimit are both invalid', () => {
  assert.equal(checkout.couponIsRedeemable(couponDoc({ isActive: false }), NOW), false);
  assert.equal(checkout.couponIsRedeemable(couponDoc({ usageLimit: 10, usedCount: 10 }), NOW), false);
  assert.equal(checkout.couponIsRedeemable(couponDoc({ usageLimit: 10, usedCount: 9 }), NOW), true);
});

// ---- the rest of the coupon contract, still pure ------------------------------------------------

test('flat, percentage and capped discounts are computed on the eligible slice only', () => {
  assert.equal(quote(couponDoc({ kind: 'flat', valuePaise: 500 })).discountPaise, 500);
  assert.equal(quote(couponDoc({ kind: 'flat', valuePaise: 999999 })).discountPaise, 10000, 'a flat code never exceeds the cart');
  assert.equal(quote(couponDoc({ kind: 'percentage', percentOff: 10 })).discountPaise, 1000);
  assert.equal(quote(couponDoc({ kind: 'percentage', percentOff: 50, maxDiscountPaise: 300 })).discountPaise, 300);
  assert.deepEqual(quote(couponDoc({ kind: 'freeShipping' })), { discountPaise: 0, freeShipping: true, reason: '' });
});

test('minQty and minCartValue gate the code before any money moves', () => {
  assert.equal(quote(couponDoc({ minQty: 2 })).reason, checkout.COUPON_MIN_QTY(2));
  assert.equal(quote(couponDoc({ minCartValuePaise: 20000 })).reason, checkout.COUPON_MIN_CART);
  assert.equal(quote(couponDoc({ minCartValuePaise: 10000 })).discountPaise, 500, 'the threshold is inclusive');
});

test('a scoped coupon only ever touches the lines it names', () => {
  const lines = [
    { productId: 'p1', categoryId: 'c1', qty: 1, lineTotalPaise: 10000 },
    { productId: 'p2', categoryId: 'c2', qty: 1, lineTotalPaise: 4000 },
  ];
  const byCategory = couponDoc({ appliesToCategoryIds: ['c2'] });
  assert.equal(checkout.couponHasScope(byCategory), true);
  assert.equal(checkout.eligibleSubtotalPaise(byCategory, lines), 4000);
  assert.equal(checkout.couponDiscount(byCategory, lines, { wholesale: false, cartUnits: 2, now: NOW }).discountPaise, 500);
  assert.equal(checkout.eligibleSubtotalPaise(couponDoc({ appliesToProductIds: ['p1'] }), lines), 10000);
  // A scoped code that matches nothing in this cart discounts nothing — and says so with no reason,
  // so the buyer still checks out at full price instead of getting an error.
  assert.equal(checkout.couponDiscount(couponDoc({ appliesToCategoryIds: ['c9'] }), lines, { wholesale: false, cartUnits: 2, now: NOW }).discountPaise, 0);
});

test('excludesWholesale refuses the code for a wholesale buyer and allows it for a retail one', () => {
  const coupon = couponDoc({ excludesWholesale: true });
  assert.equal(checkout.couponDiscount(coupon, ONE_LINE, { wholesale: true, cartUnits: 1, now: NOW }).reason, checkout.COUPON_WHOLESALE);
  assert.equal(checkout.couponDiscount(coupon, ONE_LINE, { wholesale: false, cartUnits: 1, now: NOW }).discountPaise, 500);
});

// ---- the preview callable: same rule, no second implementation -----------------------------------

async function preview(code, request = h.asSigned(UID_A)) {
  return h.invoke('couponsQuote', { code, lines: ONE_LINE }, request);
}

test('couponsQuote discounts a live code', async () => {
  const recent = new Date(Date.now() - HOUR).toISOString();
  const ahead = new Date(Date.now() + HOUR).toISOString();
  h.coupon('LIVE', { startsAt: recent, endsAt: ahead });
  const answer = await preview('LIVE');
  assert.equal(answer.discountPaise, 500);
  assert.equal(answer.reason, '');
  assert.equal(answer.coupon.code, 'LIVE');
});

for (const [label, build] of SHAPES) {
  test(`couponsQuote rejects a code whose window has closed (${label})`, async () => {
    h.coupon('EXPIRED', { endsAt: build(Date.now() - MINUTE) });
    const answer = await preview('EXPIRED');
    assert.equal(answer.discountPaise, 0, 'before F2 this returned 500 for every shape but a number');
    assert.equal(answer.reason, checkout.COUPON_INVALID);
  });

  test(`couponsQuote rejects a code that has not started (${label})`, async () => {
    h.coupon('FUTURE', { startsAt: build(Date.now() + HOUR) });
    const answer = await preview('FUTURE');
    assert.equal(answer.discountPaise, 0);
    assert.equal(answer.reason, checkout.COUPON_INVALID);
  });
}

test('couponsQuote answers an unknown code without inventing a discount', async () => {
  const answer = await preview('NOPE');
  assert.equal(answer.coupon, null);
  assert.equal(answer.discountPaise, 0);
  assert.equal(answer.reason, 'Unknown coupon code.');
});

test('couponsQuote does not leak usage counters to the browser', async () => {
  h.coupon('LEAK', { usageLimit: 500, usedCount: 499, perUserLimit: 3 });
  const answer = await preview('LEAK');
  assert.equal(Object.prototype.hasOwnProperty.call(answer.coupon, 'usedCount'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(answer.coupon, 'usageLimit'), false);
});

test('couponsQuote applies the wholesale rule from the users/{uid} document, not the token', async () => {
  h.coupon('TRADE', { excludesWholesale: true });
  assert.equal((await preview('TRADE', h.asSigned(UID_WHOLESALE))).reason, checkout.COUPON_WHOLESALE);
  assert.equal((await preview('TRADE', h.asSigned(UID_A))).discountPaise, 500);
});

// ---- the charge path: a dead code never moves money ---------------------------------------------

async function createWithCoupon(key, couponCode, discountPaise, request = h.asSigned(UID_A)) {
  return h.invoke('ordersCreate', h.draft({ key, couponCode, discountPaise, email: 'a@example.test' }), request);
}

test('an expired code creates the order at FULL price and spends nothing', async () => {
  h.coupon('DEAD', { endsAt: new Date(Date.now() - MINUTE).toISOString() });
  const receipt = await createWithCoupon('c-expired-1', 'DEAD', 0);

  assert.equal(receipt.totals.couponDiscountPaise, 0);
  assert.equal(receipt.totals.grandTotalPaise, 11000);
  const stored = h.read(`orders/${receipt.orderId}`);
  assert.equal(stored.couponCode, '', 'a refused code must not be recorded on the order');
  assert.equal(h.read('coupons/DEAD').usedCount, 0);
  assert.equal(h.read(`coupon_redemptions/DEAD__${UID_A}`), null);
});

test('a stale client still showing an expired discount is refused instead of honouring it', async () => {
  // The buyer's cart was quoted before the window closed, so it presents 10500. The server prices
  // 11000. The mismatch is rejected outright — a client can never impose a discount the server denied.
  h.coupon('DEAD2', { endsAt: new Date(Date.now() - MINUTE).toISOString() });
  const error = await h.errorOf(() => createWithCoupon('c-expired-2', 'DEAD2', 500));
  assert.equal(error.code, 'failed-precondition');
  assert.equal(error.details.code, 'PRICE_CHANGED');
  assert.equal((await h.db.collection('orders').get()).size, 0, 'a refused price must not leave an order behind');
  assert.equal(h.read('products/p1').stockQty, 100);
});

test('a not-yet-started code is refused at create time too', async () => {
  h.coupon('EARLY', { startsAt: new Date(Date.now() + HOUR).toISOString() });
  const receipt = await createWithCoupon('c-future-1', 'EARLY', 0);
  assert.equal(receipt.totals.couponDiscountPaise, 0);
  assert.equal(h.read('coupons/EARLY').usedCount, 0);
});

test('a live code discounts, records itself and counts once', async () => {
  h.coupon('SAVE500', { startsAt: new Date(Date.now() - HOUR).toISOString(), endsAt: new Date(Date.now() + HOUR).toISOString() });
  const receipt = await createWithCoupon('c-live-1', 'SAVE500', 500);

  assert.equal(receipt.totals.couponDiscountPaise, 500);
  assert.equal(receipt.totals.grandTotalPaise, 10500);
  assert.equal(h.read(`orders/${receipt.orderId}`).couponCode, 'SAVE500');
  assert.equal(h.read('coupons/SAVE500').usedCount, 1);
  assert.equal(h.read(`coupon_redemptions/SAVE500__${UID_A}`).count, 1);
});

test("perUserLimit is enforced server-side: the second order gets no discount", async () => {
  h.coupon('ONCE', { perUserLimit: 1 });
  const first = await createWithCoupon('c-limit-1', 'ONCE', 500);
  assert.equal(first.totals.couponDiscountPaise, 500);

  // Fresh idempotency key, same buyer, same code — and the client total sent is the FULL price,
  // because that is what a re-quote would now return.
  const second = await createWithCoupon('c-limit-2', 'ONCE', 0);
  assert.equal(second.totals.couponDiscountPaise, 0);
  assert.equal(h.read('coupons/ONCE').usedCount, 1, 'a spent code must not be counted twice');

  // A client that still claims the discount is refused rather than quietly discounted.
  const error = await h.errorOf(() => createWithCoupon('c-limit-3', 'ONCE', 500));
  assert.equal(error.details.code, 'PRICE_CHANGED');
});

test('perUserLimit above 1 allows that many uses and no more', async () => {
  h.coupon('TWICE', { perUserLimit: 2 });
  assert.equal((await createWithCoupon('c-two-1', 'TWICE', 500)).totals.couponDiscountPaise, 500);
  assert.equal((await createWithCoupon('c-two-2', 'TWICE', 500)).totals.couponDiscountPaise, 500);
  assert.equal((await createWithCoupon('c-two-3', 'TWICE', 0)).totals.couponDiscountPaise, 0);
});

test('usageLimit stops the whole store once the last code is spent', async () => {
  h.coupon('GLOBAL', { usageLimit: 1, perUserLimit: null });
  assert.equal((await createWithCoupon('c-g-1', 'GLOBAL', 500, h.asSigned(UID_A))).totals.couponDiscountPaise, 500);
  // A different buyer, so the per-user ledger cannot be what stopped it.
  assert.equal((await createWithCoupon('c-g-2', 'GLOBAL', 0, h.asSigned(UID_WHOLESALE))).totals.couponDiscountPaise, 0);
  assert.equal(h.read('coupons/GLOBAL').usedCount, 1);
});

test('a buyer with no users/{uid} profile cannot reach the coupon branch at all', async () => {
  h.coupon('ANY');
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'c-noprofile', couponCode: 'ANY', discountPaise: 0 }), h.asSigned('uid-stranger')),
  );
  assert.equal(error.code, 'permission-denied');
  assert.equal(h.read('coupons/ANY').usedCount, 0);
});
