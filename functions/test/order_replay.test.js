'use strict';

// F1 regression suite: idempotency-replay ownership on BOTH exits.
//
// `orderByIdempotency` was guarded first; `ordersCreate`'s own replay branch kept returning whatever
// order the presented key pointed at, with no comparison to the caller — and because it skips
// `requireCaller` for anonymous requests, a stranger holding a guest's key got the guest's contact
// email, phone and address back. These tests run the real handlers.

const test = require('node:test');
const assert = require('node:assert/strict');

const { createHarness } = require('./support/harness');
const { REPLAY_REFUSED } = require('../lib/order_access');

const h = createHarness();
const UID_A = 'uid-buyer-a';
const UID_B = 'uid-buyer-b';
const UID_STAFF = 'uid-staff';
const GUEST_EMAIL = 'guest@example.test';
const GUEST_PHONE = '+91 98765 43210';

test.beforeEach(() => {
  h.reset();
  h.settings();
  h.product('p1');
  h.user(UID_A, { email: 'a@example.test' });
  h.user(UID_B, { email: 'b@example.test' });
  h.user(UID_STAFF, { role: 'admin' });
});

async function createAsBuyer(key, overrides = {}) {
  return h.invoke('ordersCreate', h.draft({ key, email: 'a@example.test', phone: '9812345678', ...overrides }), h.asSigned(UID_A));
}

async function createAsGuest(key, email = GUEST_EMAIL, phone = GUEST_PHONE) {
  return h.invoke('ordersCreate', h.draft({ key, email, phone }), h.asAnonymous());
}

async function orderCount() {
  return (await h.db.collection('orders').get()).size;
}

async function stockOf(id = 'p1') {
  return h.read(`products/${id}`).stockQty;
}

test('authenticated create stores a ledger row naming its buyer', async () => {
  const receipt = await createAsBuyer('k-a-1');
  assert.ok(receipt.orderId, 'orderId must not be empty');
  assert.equal(receipt.wasReplay, false);
  assert.equal(receipt.totals.grandTotalPaise, 11000);
  assert.deepEqual(h.read(`idempotency_keys/k-a-1`).uid, UID_A);
  assert.equal(h.read(`orders/${receipt.orderId}`).userId, UID_A);
});

test("a legitimate retry replays the same order and does not charge or reserve twice", async () => {
  const first = await createAsBuyer('k-a-2');
  const stockAfterFirst = await stockOf();
  const second = await createAsBuyer('k-a-2');

  assert.equal(second.wasReplay, true);
  assert.equal(second.orderId, first.orderId, 'the replay must name the original order');
  assert.notEqual(second.orderId, '', 'regression: an empty orderId sent the buyer to /order-success/ with no order');
  assert.equal(await orderCount(), 1);
  assert.equal(await stockOf(), stockAfterFirst, 'a replay must not decrement stock again');
  assert.equal(second.message, 'This order already exists.');
});

test("another buyer's key is refused, and nothing is created", async () => {
  const mine = await createAsBuyer('k-victim');
  const before = await stockOf();

  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-victim', email: 'b@example.test' }), h.asSigned(UID_B)),
  );
  assert.equal(error.code, 'permission-denied');
  assert.equal(error.message, REPLAY_REFUSED);
  assert.equal(await orderCount(), 1, 'a refused replay must not mint a second order');
  assert.equal(await stockOf(), before);
  assert.equal(h.read(`orders/${mine.orderId}`).userId, UID_A);
});

test('an anonymous request bearing a signed-in buyer’s key gets the same uniform refusal', async () => {
  // Guest checkout is allowed by design, so `ordersCreate` never calls requireCaller for an anonymous
  // request: the refusal has to come from the ownership rule, and it must not read as "that key belongs
  // to somebody". Same code, same message as every other refused replay.
  await createAsBuyer('k-a-3');
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-a-3', email: 'someone@example.test' }), h.asAnonymous()),
  );
  assert.equal(error.code, 'permission-denied');
  assert.equal(error.message, REPLAY_REFUSED);
});

test('a signed-in buyer cannot claim a guest-placed key', async () => {
  await createAsGuest('k-guest-1');
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-guest-1', email: GUEST_EMAIL }), h.asSigned(UID_A)),
  );
  assert.equal(error.code, 'permission-denied');
  assert.equal(error.message, REPLAY_REFUSED);
});

test('guest replay is authorized by the order’s own contact detail, not by the key', async () => {
  const placed = await createAsGuest('k-guest-2');
  const again = await h.invoke('ordersCreate', h.draft({ key: 'k-guest-2', email: GUEST_EMAIL }), h.asAnonymous());

  assert.equal(again.wasReplay, true);
  assert.equal(again.orderId, placed.orderId);
  assert.equal(await orderCount(), 1);
});

test('guest replay with a phone-only match works, because the order stored that phone', async () => {
  // The order stored `+91 98765 43210`; the retry types the same number with different punctuation.
  // `normalisePhone` compares digits, so formatting must not decide whether a buyer can retry.
  const placed = await createAsGuest('k-guest-3', '', GUEST_PHONE);
  const again = await h.invoke('ordersCreate', h.draft({ key: 'k-guest-3', email: '', phone: '91-98765-43210' }), h.asAnonymous());
  assert.equal(again.orderId, placed.orderId, 'the same number typed without its + must still match');
});

test('a phone that only shares a suffix is NOT a match', async () => {
  // Regression pin for the digit comparison: dropping the country code is a different number, and
  // a substring match would let anyone who knows the last 10 digits of a guest's phone retry it.
  await createAsGuest('k-guest-3b', '', GUEST_PHONE);
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-guest-3b', email: '', phone: '9876543210' }), h.asAnonymous()),
  );
  assert.equal(error.code, 'permission-denied');
});

test('guest replay with a different contact detail is refused', async () => {
  await createAsGuest('k-guest-4');
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-guest-4', email: 'attacker@example.test', phone: '1111111111' }), h.asAnonymous()),
  );
  assert.equal(error.code, 'permission-denied');
});

test('LIMITATION: a guest order stored without email or phone can never be replayed', async () => {
  const placed = await createAsGuest('k-guest-5', '', '');
  assert.ok(placed.orderId, 'the original create still succeeds');
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-guest-5', email: '', phone: '' }), h.asAnonymous()),
  );
  assert.equal(error.code, 'permission-denied');
  assert.equal(error.message, REPLAY_REFUSED);
});

test('a ledger row pointing at a missing order refuses uniformly instead of leaking "internal"', async () => {
  h.ledger('k-dangling', { orderId: 'order-that-is-gone', uid: UID_A });
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-dangling', email: 'a@example.test' }), h.asSigned(UID_A)),
  );
  assert.equal(error.code, 'permission-denied', 'the old answer was `internal`, which confirmed the key existed');
  assert.equal(error.message, REPLAY_REFUSED);
});

test('a blank orderId in the ledger never reaches doc("")', async () => {
  h.ledger('k-blank', { orderId: '', uid: UID_A });
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-blank', email: 'a@example.test' }), h.asSigned(UID_A)),
  );
  assert.equal(error.code, 'permission-denied');
});

test('ledger and order document that name different buyers are refused', async () => {
  h.order('o-mixed', { userId: UID_B, isGuest: false, contactEmail: 'b@example.test' });
  h.ledger('k-mixed', { orderId: 'o-mixed', uid: UID_A });
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-mixed', email: 'a@example.test' }), h.asSigned(UID_A)),
  );
  assert.equal(error.code, 'permission-denied');
  assert.equal(await orderCount(), 1);
});

test('a signed-in ledger row whose order is flagged isGuest is refused', async () => {
  h.order('o-guestflag', { userId: UID_A, isGuest: true, contactEmail: 'a@example.test' });
  h.ledger('k-guestflag', { orderId: 'o-guestflag', uid: UID_A });
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-guestflag', email: 'a@example.test' }), h.asSigned(UID_A)),
  );
  assert.equal(error.code, 'permission-denied');
});

test('a staff role is not ownership', async () => {
  await createAsBuyer('k-a-9');
  const error = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'a-staff-retry', email: 'staff@example.test' }), h.asSigned(UID_STAFF)),
  );
  // Staff with their OWN fresh key still get an order; the point is they cannot take a buyer's key.
  assert.equal(error, null);

  const stolen = await h.errorOf(() =>
    h.invoke('ordersCreate', h.draft({ key: 'k-a-9', email: 'staff@example.test' }), h.asSigned(UID_STAFF)),
  );
  assert.equal(stolen.code, 'permission-denied');
  assert.equal(await orderCount(), 2, 'one buyer order plus one staff order, never a buyer order twice');
});

test('a missing idempotency key is rejected before anything is read', async () => {
  const error = await h.errorOf(() => h.invoke('ordersCreate', h.draft({ key: '' }), h.asSigned(UID_A)));
  assert.equal(error.code, 'invalid-argument');
});

// ---- the lookup callable: same ownership rule, non-disclosing answer ----------------------------

test('orderByIdempotency returns the owner’s receipt with a usable orderId', async () => {
  const placed = await createAsBuyer('k-look-1');
  const found = await h.invoke('orderByIdempotency', { idempotencyKey: 'k-look-1' }, h.asSigned(UID_A));

  assert.equal(found.found, true);
  assert.equal(found.receipt.orderId, placed.orderId);
  assert.equal(found.receipt.wasReplay, true);
  assert.equal(found.receipt.paymentClientSecret, '');
});

test('orderByIdempotency cannot be used to confirm that a key exists', async () => {
  // Four different reasons to refuse, and every one of them has to answer the byte-identical
  // `{ found: false }` — including "this key was never heard of". Any variation (a receipt, a not-found
  // code, a longer response) turns this callable into an oracle for "does this idempotency key exist".
  //
  // FIXTURE CAUTION, learned the hard way: each case carries its OWN caller. A case named "someone
  // else's key" that asks as the buyer who placed it is simply the owner reading their own receipt,
  // and `{ found: true }` there is correct behaviour, not a leak.
  const guestOrder = await createAsGuest('k-look-2');
  const alicesOwn = await createAsBuyer('k-look-alice');
  const bobsOwn = await h.invoke(
    'ordersCreate',
    h.draft({ key: 'k-look-bob', email: 'b@example.test' }),
    h.asSigned(UID_B),
  );
  assert.ok(bobsOwn.orderId, 'buyer B really placed an order, so the refusals below are about ownership, not absence');

  const cases = [
    ['a key that does not exist', 'k-does-not-exist', h.asSigned(UID_A)],
    ['a guest-placed key', 'k-look-2', h.asSigned(UID_A)],
    ['buyer B’s key presented by buyer A', 'k-look-bob', h.asSigned(UID_A)],
    ['buyer B’s key presented by a staff account', 'k-look-bob', h.asSigned(UID_STAFF)],
  ];
  for (const [label, key, request] of cases) {
    const answer = await h.invoke('orderByIdempotency', { idempotencyKey: key }, request);
    assert.deepEqual(answer, { found: false }, `${label} must answer the identical shape`);
  }

  // The mirror assertions: the very same keys ARE readable by the buyer who owns them. Without these,
  // the loop above could pass because the fixture never created anything, not because the rule works.
  const alicesRead = await h.invoke('orderByIdempotency', { idempotencyKey: 'k-look-alice' }, h.asSigned(UID_A));
  assert.equal(alicesRead.found, true);
  assert.equal(alicesRead.receipt.orderId, alicesOwn.orderId);

  const bobsRead = await h.invoke('orderByIdempotency', { idempotencyKey: 'k-look-bob' }, h.asSigned(UID_B));
  assert.equal(bobsRead.found, true);
  assert.equal(bobsRead.receipt.orderId, bobsOwn.orderId, 'B gets B’s own receipt, including the right order id');

  // And the guest's order stays unreachable through this callable, because it needs an account.
  assert.ok(guestOrder.orderId);
  const guestRead = await h.invoke('orderByIdempotency', { idempotencyKey: 'k-look-2' }, h.asSigned(UID_B));
  assert.deepEqual(guestRead, { found: false });
});

test('orderByIdempotency rejects a blank key before reading anything', async () => {
  const error = await h.errorOf(() =>
    h.invoke('orderByIdempotency', { idempotencyKey: '' }, h.asSigned(UID_A)),
  );
  assert.equal(error.code, 'invalid-argument');
});

test('orderByIdempotency refuses when the ledger and the order document disagree', async () => {
  h.order('o-look-3', { userId: UID_B, isGuest: false });
  h.ledger('k-look-3', { orderId: 'o-look-3', uid: UID_A });
  assert.deepEqual(await h.invoke('orderByIdempotency', { idempotencyKey: 'k-look-3' }, h.asSigned(UID_A)), { found: false });

  h.order('o-look-4', { userId: UID_A, isGuest: false });
  h.ledger('k-look-4', { orderId: 'o-look-4', uid: UID_A });
  assert.equal((await h.invoke('orderByIdempotency', { idempotencyKey: 'k-look-4' }, h.asSigned(UID_A))).found, true);
});

test('a stored document cannot override the orderId the receipt carries', async () => {
  h.order('o-real-id', { userId: UID_A, isGuest: false, id: 'THIS-MUST-NEVER-LEAK', orderId: 'THIS-MUST-NEVER-LEAK' });
  h.ledger('k-look-5', { orderId: 'o-real-id', uid: UID_A });
  const answer = await h.invoke('orderByIdempotency', { idempotencyKey: 'k-look-5' }, h.asSigned(UID_A));
  assert.equal(answer.found, true);
  assert.equal(answer.receipt.orderId, 'o-real-id');
});

test('orderByIdempotency requires a signed-in caller', async () => {
  const error = await h.errorOf(() => h.invoke('orderByIdempotency', { idempotencyKey: 'k-any' }, h.asAnonymous()));
  assert.equal(error.code, 'unauthenticated');
});
