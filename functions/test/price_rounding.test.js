'use strict';

// F4 regression suite: the payable the buyer was SHOWN is the payable the server compares against.
//
// The bug being pinned: the client sends `totals.payableRoundedPaise` (the rupee-rounded amount the
// cart displays — see CartTotals.payableRoundedPaise and OrderDraft), but the server compared it
// against the UNROUNDED `grandTotalPaise`. The rounding delta alone is up to 99 paise, so a 100-paise
// epsilon was almost entirely spent on display rounding: a genuine 1–2 paise price change then
// rejected a checkout that was actually fine, and the tolerance the buyer could not see decided
// whether their order went through. The fix compares like with like — the charged figure against the
// charged figure — and the epsilon is deliberately NOT widened to compensate.
//
// Money rule that must never move: the amount STORED is `payableRoundedPaise`, so the receipt, the
// stored document and the payment mark can never disagree by a fraction of a rupee.

const test = require('node:test');
const assert = require('node:assert/strict');

const { createHarness } = require('./support/harness');
const { priceAgreement } = require('../lib/checkout');
const pricing = require('../lib/pricing');

// Pinned so a stray OM_PRICE_EPSILON_PAISE in someone's shell cannot make these assertions trivial.
const h = createHarness({ env: { OM_PRICE_EPSILON_PAISE: '100' } });
const EPSILON = 100;
const UID_A = 'uid-buyer-a';

// subtotal 10000 + shipping 1000 + tax 1850 = 12850 -> charged 12900 (50 paise of rounding).
const DRIFTING = { grandTotalPaise: 12850, payableRoundedPaise: 12900 };

function agree(clientTotalPaise, totals = DRIFTING, epsilon = EPSILON) {
  return priceAgreement(clientTotalPaise, totals, epsilon);
}

test.beforeEach(() => {
  h.reset();
  h.settings();
  h.product('p1');
  h.user(UID_A, { email: 'a@example.test' });
});

// ---- the canonical rounding rule -----------------------------------------------------------------

test('payableRoundedPaise is the smallest whole rupee that is >= the grand total', () => {
  for (let grand = 0; grand <= 300; grand += 1) {
    const totals = pricing.cartTotals([{ qty: 1, lineTotalPaise: grand, savedPaise: 0 }], {});
    assert.equal(totals.grandTotalPaise, grand);
    assert.equal(totals.payableRoundedPaise, Math.ceil(grand / 100) * 100, `rounding ${grand}`);
    assert.ok(totals.payableRoundedPaise >= grand && totals.payableRoundedPaise - grand < 100);
  }
});

test('the two rounding boundaries that used to eat the epsilon', () => {
  const exact = pricing.cartTotals([{ qty: 1, lineTotalPaise: 11000, savedPaise: 0 }], { shippingPaise: 0 });
  assert.equal(exact.payableRoundedPaise - exact.grandTotalPaise, 0, 'a whole rupee needs no rounding');
  const worst = pricing.cartTotals([{ qty: 1, lineTotalPaise: 11001, savedPaise: 0 }], { shippingPaise: 0 });
  assert.equal(worst.payableRoundedPaise - worst.grandTotalPaise, 99, 'one paise over a rupee rounds up by 99');
});

// ---- the agreement rule --------------------------------------------------------------------------

test('the figure the buyer was shown agrees with itself', () => {
  const answer = agree(12900);
  assert.equal(answer.checked, true);
  assert.equal(answer.ok, true);
  assert.equal(answer.diffPaise, 0);
  assert.equal(answer.chargedPaise, 12900);
});

test('drift up to the epsilon is tolerated on either side of the charged amount', () => {
  for (const client of [13000, 12800]) {
    const answer = agree(client);
    assert.equal(answer.ok, true, `${client} is exactly ${EPSILON} away`);
    assert.equal(Math.abs(answer.diffPaise), EPSILON);
  }
  assert.equal(agree(13001).ok, false);
  assert.equal(agree(12799).ok, false);
});

test('this is the case the old basis got wrong', () => {
  // A 60-paise real price change on a cart that also carries a 50-paise rounding delta. Compared
  // against the charged figure this is 60 -> accepted. Compared against the unrounded total (the
  // pre-fix behaviour) it was 110 -> rejected, so an honest buyer was told "the total changed".
  const answer = agree(12960);
  assert.equal(answer.ok, true);
  assert.equal(answer.diffPaise, 60);
  assert.equal(Math.abs(12960 - DRIFTING.grandTotalPaise), 110, 'the figure the fix stopped comparing against');
});

test('a client that sends no usable total is not blocked by the epsilon', () => {
  // An older or non-web caller simply does not send the figure; the server's own amount is stored,
  // so there is nothing to disagree with. Re-checking instead of refusing is safe because the client
  // never sets a price.
  for (const client of [0, null, undefined, '', 'not a number']) {
    const answer = agree(client);
    assert.equal(answer.checked, false);
    assert.equal(answer.ok, true);
  }
  assert.equal(agree('12900').ok, true, 'a numeric string is read as the same amount');
});

test('with the epsilon at zero only an exact match survives', () => {
  assert.equal(agree(12900, DRIFTING, 0).ok, true);
  assert.equal(agree(12901, DRIFTING, 0).ok, false);
});

test('the epsilon was not widened to paper over the rounding bug', () => {
  assert.equal(h.server.PRICE_EPSILON_PAISE, EPSILON);
});

// ---- through the callable -------------------------------------------------------------------------

async function create(key, overrides = {}) {
  return h.invoke('ordersCreate', h.draft({ key, email: 'a@example.test', ...overrides }), h.asSigned(UID_A));
}

function useSettings(overrides) {
  h.settings(overrides);
  h.reloadSettings();
}

test('a fractional cart stores and charges the rupee-rounded amount', async () => {
  useSettings({ taxRateBps: 1850 });
  const receipt = await create('r-1', { taxRateBps: 1850, shippingPaise: 1000 });
  assert.equal(receipt.totals.grandTotalPaise, 12900);
  assert.equal(receipt.totals.taxPaise, 1850);
  assert.equal(receipt.totals.roundingPaise, 50);

  const stored = h.read(`orders/${receipt.orderId}`).totals;
  assert.equal(stored.grandTotalPaise, 12900, 'the stored total is what the buyer is charged, to the rupee');
  assert.equal(stored.roundingPaise, 50);
  assert.equal(stored.subtotalPaise - stored.couponDiscountPaise + stored.shippingPaise + stored.taxPaise, 12850);
});

test('a client that echoes the unrounded total still checks out, and is charged the rounded one', async () => {
  // diff = -50, inside the epsilon: a display difference of a few paise must not fail a real order.
  useSettings({ taxRateBps: 1850 });
  const receipt = await create('r-2', { taxRateBps: 1850, shippingPaise: 1000, totalOverride: 12850 });
  assert.equal(receipt.wasReplay, false);
  assert.equal(receipt.totals.grandTotalPaise, 12900);
  assert.equal(h.read(`orders/${receipt.orderId}`).totals.grandTotalPaise, 12900);
});

test('drift of exactly the epsilon past the charged amount is accepted', async () => {
  useSettings({ taxRateBps: 1850 });
  const receipt = await create('r-3', { taxRateBps: 1850, shippingPaise: 1000, totalOverride: 13000 });
  assert.equal(receipt.totals.grandTotalPaise, 12900, 'the client figure is advisory; the server figure is stored');
});

for (const [label, override, key] of [['above the charged amount', 13001, 'r-drift-high'], ['below it', 12799, 'r-drift-low']]) {
  test(`drift of 101 paise ${label} is refused with PRICE_CHANGED and nothing is written`, async () => {
    useSettings({ taxRateBps: 1850 });
    const error = await create(key, { taxRateBps: 1850, shippingPaise: 1000, totalOverride: override }).catch((e) => e);
    assert.equal(error.code, 'failed-precondition');
    assert.equal(error.details.code, 'PRICE_CHANGED');
    assert.equal(error.details.serverPayableRoundedPaise, 12900);
    assert.equal(error.details.serverGrandTotalPaise, 12850);
    assert.equal(error.details.clientTotalPaise, override);
    assert.equal(error.details.epsilonPaise, EPSILON);
    assert.equal((await h.db.collection('orders').get()).size, 0);
    assert.equal(h.read('products/p1').stockQty, 100);
    assert.equal((await h.db.collection('audit_logs').get()).size, 0, 'a rejected order is not worth an audit row');
    assert.equal(h.read(`idempotency_keys/${key}`), null);
  });
}

test('a whole-rupee total needs no rounding and reports roundingPaise 0', async () => {
  const receipt = await create('r-4', { shippingPaise: 1000 });
  assert.equal(receipt.totals.grandTotalPaise, 11000);
  assert.equal(receipt.totals.roundingPaise, 0);
});

test('the worst-case rounding boundary is accepted and stored rounded up', async () => {
  // A zone rate of 1001 paise makes the server grand total 11001, i.e. 99 paise under the next rupee
  // — the largest gap the old basis could spend on rounding alone. A client that presents the
  // unrounded 11001 sits at diff -99 and is let through, and what gets stored is 11100.
  useSettings({ shippingZones: [{ id: 'z1', pincodePrefixes: ['560'], flatRatePaise: 1001, isActive: true }] });
  const receipt = await create('r-5', { shippingPaise: 1001 });
  assert.equal(receipt.totals.grandTotalPaise, 11100);
  assert.equal(receipt.totals.shippingPaise, 1001);
  assert.equal(receipt.totals.roundingPaise, 99);
  assert.equal(h.read(`orders/${receipt.orderId}`).totals.grandTotalPaise, 11100);

  const unrounded = await create('r-6', { shippingPaise: 1001, totalOverride: 11001 });
  assert.equal(unrounded.totals.grandTotalPaise, 11100, 'the buyer is charged the rounded amount either way');
});

test('a tax-inclusive store keeps tax at zero rather than adding it on top', async () => {
  useSettings({ taxRateBps: 1850, taxInclusive: true });
  const receipt = await create('r-7', { taxRateBps: 0, shippingPaise: 1000 });
  assert.equal(receipt.totals.taxPaise, 0);
  assert.equal(receipt.totals.grandTotalPaise, 11000);
  assert.equal(receipt.totals.roundingPaise, 0);
});

test('replay, receipt and stored document all carry the same charged amount', async () => {
  // F4 and F1 meet here: a replayed receipt is copied from the stored document, so the buyer who
  // retries must see the identical rupee amount, not a re-rounded or re-priced one.
  useSettings({ taxRateBps: 1850 });
  const placed = await create('r-8', { taxRateBps: 1850, shippingPaise: 1000 });
  const replay = await create('r-8', { taxRateBps: 1850, shippingPaise: 1000 });
  assert.equal(replay.wasReplay, true);
  assert.equal(replay.orderId, placed.orderId);
  assert.deepEqual(replay.totals, placed.totals);
  assert.equal(replay.totals.grandTotalPaise, 12900);
});

test('a client that sends no total at all still gets the server’s own amount', async () => {
  const draft = h.draft({ key: 'r-9', email: 'a@example.test' });
  delete draft.clientTotalPaise;
  const receipt = await h.invoke('ordersCreate', draft, h.asSigned(UID_A));
  assert.equal(receipt.totals.grandTotalPaise, 11000);
  assert.equal(h.read(`orders/${receipt.orderId}`).totals.grandTotalPaise, 11000);
});

test('the client line price is ignored even when the totals happen to match', async () => {
  // `draft()` ships `lineTotalPaise: 1` on purpose. If any path trusted it, every assertion above
  // about 11000 would instead be about 1001, and the order snapshot would show a 1-paise item.
  const receipt = await create('r-10', { shippingPaise: 1000 });
  assert.equal(receipt.totals.subtotalPaise, 10000);
  assert.equal(receipt.totals.slabDiscountPaise, 1000, 'the slab saving is computed from the stored retail price');
  const item = h.read(`orders/${receipt.orderId}`).items[0];
  assert.equal(item.qty, 1);
  assert.equal(item.basePricePaise, 11000);
  assert.equal(item.discountPaise, 1000);
});
