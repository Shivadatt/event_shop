'use strict';

// Focused regression for the order-replay receipt guard. Plain Node, zero dependencies, no
// emulator, no credentials: it asserts the pure decision helpers in lib/order_access.js, which is
// exactly the logic that (a) leaked another buyer's receipt through a guessed idempotency key and
// (b) answered every replay with `orderId: ''`.
//
//   cd functions && npm run check:replay-guard      (or: node scripts/check_order_replay_guard.js)
//
// Scope of this file: the decision only. It cannot prove that index.js wires the decision correctly,
// that requireCaller rejects an anonymous caller, or that the emulator behaves — those need the
// commands listed in the summary it prints. It exits 1 on the first failing group.

const { keyPointsToOwnedOrder, mayReadReplay, receiptFromOrder } = require('../lib/order_access');

let failures = 0;
let checks = 0;

function ok(condition, label, detail) {
  checks += 1;
  if (condition) {
    console.log(`  PASS  ${label}`);
    return;
  }
  failures += 1;
  console.log(`  FAIL  ${label}${detail ? `\n        ${detail}` : ''}`);
}

const OWNER = 'uid-owner-aaaaaaaaaaaaaaaaaaaaaaaa';
const OTHER = 'uid-other-bbbbbbbbbbbbbbbbbbbbbbbb';
const STAFF = 'uid-staff-cccccccccccccccccccccccc';
const ORDER_ID = 'ordcccccccccccccccccccccccc';

// A realistic stored order. `id` is deliberately present with a WRONG value: nothing in the receipt
// may ever be taken from the document body.
const orderDoc = {
  id: 'THIS-MUST-NEVER-LEAK',
  orderNumber: 'OME-2026-000123',
  userId: OWNER,
  isGuest: false,
  status: 'placed',
  paymentStatus: 'pending',
  totals: { grandTotalPaise: 456700, subtotalPaise: 370000, taxPaise: 86700 },
  contactEmail: 'buyer@example.test',
  contactPhone: '+910000000000',
};
const ownedKey = { orderId: ORDER_ID, uid: OWNER, createdAt: 'ts' };

console.log('keyPointsToOwnedOrder — the pre-read gate');
ok(keyPointsToOwnedOrder({ keyRecord: ownedKey, callerUid: OWNER }) === true, 'owned key is accepted');
ok(keyPointsToOwnedOrder({ keyRecord: { ...ownedKey, uid: OTHER }, callerUid: OWNER }) === false,
  "another customer's key is refused");
// PINNED SECURITY STANCE, asserted on purpose so a future "improvement" must be a decision:
// `lib/checkout.js` used to carry a second, permissive rule (`mayReplayKeyIdempotencyRecord`) that
// (a) let any staff role resolve ANY buyer's key and (b) bound guest-to-guest (`null === null`), so an
// anonymous caller could read a stranger's guest receipt. The owner ruled on both on 2026-10-21 and the
// permissive copy is deleted — these two assertions are the ruling, and flipping one is a decision.
ok(keyPointsToOwnedOrder({ keyRecord: ownedKey, callerUid: STAFF }) === false,
  'staff who is not the owner is refused (ruling 1: a role is not ownership)');
ok(keyPointsToOwnedOrder({ keyRecord: { orderId: ORDER_ID, uid: null }, callerUid: STAFF }) === false,
  'staff cannot claim a guest-placed key either');
ok(keyPointsToOwnedOrder({ keyRecord: { orderId: ORDER_ID, uid: null }, callerUid: '' }) === false,
  'an anonymous caller cannot claim a guest-placed key via this gate (ruling 2: the contact detail decides)');
ok(keyPointsToOwnedOrder({ keyRecord: { orderId: ORDER_ID, uid: null }, callerUid: OWNER }) === false,
  'guest-placed key (uid null, as ordersCreate writes it) is refused');
ok(keyPointsToOwnedOrder({ keyRecord: { orderId: ORDER_ID, uid: '' }, callerUid: OWNER }) === false,
  'guest-placed key (uid empty string) is refused');
ok(keyPointsToOwnedOrder({ keyRecord: { orderId: '', uid: OWNER }, callerUid: OWNER }) === false,
  'key with a blank order id is refused', 'detail: must not cause a doc("") read');
ok(keyPointsToOwnedOrder({ keyRecord: undefined, callerUid: OWNER }) === false, 'missing key is refused');
ok(keyPointsToOwnedOrder({ keyRecord: ownedKey, callerUid: '' }) === false,
  'caller with no uid cannot own anything');
ok(keyPointsToOwnedOrder({ keyRecord: ownedKey, callerUid: undefined }) === false,
  'undefined caller uid cannot own anything');

console.log('mayReadReplay — the final gate, after the order document is read');
ok(mayReadReplay({ keyRecord: ownedKey, orderData: orderDoc, callerUid: OWNER }) === true,
  'owned replay is allowed');
ok(mayReadReplay({ keyRecord: { ...ownedKey, uid: OTHER }, orderData: orderDoc, callerUid: OWNER }) === false,
  "another customer's key is refused");
ok(mayReadReplay({ keyRecord: { orderId: ORDER_ID, uid: null }, orderData: orderDoc, callerUid: OWNER }) === false,
  'guest-owned key is refused');
ok(mayReadReplay({ keyRecord: ownedKey, orderData: null, callerUid: OWNER }) === false,
  'missing order is refused', 'detail: order.exists === false arrives here as null');
ok(mayReadReplay({ keyRecord: ownedKey, orderData: { ...orderDoc, isGuest: true }, callerUid: OWNER }) === false,
  'order flagged isGuest is refused even when the ledger carries a uid');
ok(mayReadReplay({ keyRecord: ownedKey, orderData: { ...orderDoc, userId: OTHER }, callerUid: OWNER }) === false,
  'ledger/order disagreement is refused (key rewritten at another order)');
ok(mayReadReplay({ keyRecord: ownedKey, orderData: { ...orderDoc, userId: undefined }, callerUid: OWNER }) === false,
  'order with no userId is refused');
ok(mayReadReplay({}) === false, 'empty arguments are refused, not thrown');

console.log('receiptFromOrder — the id an empty-string regression');
const receipt = receiptFromOrder(orderDoc, ORDER_ID, { wasReplay: true });
ok(receipt.orderId === ORDER_ID, 'receipt carries the authoritative order id',
  `got "${receipt.orderId}"`);
ok(receipt.orderId !== '', 'receipt orderId is never the empty string again');
ok(receipt.orderId !== orderDoc.id, 'a stored id field cannot override the resolved id');
ok(receipt.wasReplay === true, 'wasReplay is preserved');
ok(receipt.message === 'This order already exists.', 'replay message is preserved');
ok(receipt.priceChanged === false, 'priceChanged stays false (the Dart side owns that flag)');
ok(receipt.paymentClientSecret === '' && receipt.paymentUrl === '', 'no payment material is invented');
ok(JSON.stringify(receipt.totals) === JSON.stringify(orderDoc.totals),
  'totals are copied from the stored document, never from the caller');
ok(receiptFromOrder(orderDoc, undefined).orderId === '', 'a missing id degrades to empty rather than throwing');

// The Dart side reads this exact field set (lib/data/models/payment.dart `OrderReceipt.fromMap`).
// A renamed or dropped key here silently becomes an empty string on the client, so the shape is
// pinned deliberately.
const expectedKeys = [
  'message', 'orderId', 'orderNumber', 'orderStatus', 'paymentClientSecret',
  'paymentStatus', 'paymentUrl', 'priceChanged', 'totals', 'wasReplay',
].sort().join(',');
ok(Object.keys(receipt).sort().join(',') === expectedKeys,
  'receipt shape is unchanged for OrderReceipt.fromMap', `got ${Object.keys(receipt).sort().join(',')}`);

console.log(`\n${checks - failures}/${checks} assertions passed.`);
if (failures > 0) {
  console.log(`${failures} FAILED — do not deploy or migrate on top of this.`);
} else {
  console.log([
    'All assertions passed. Still NOT proven by this script:',
    '  1. index.js actually calls these helpers (needs: node --check index.js + a functions emulator run).',
    '  2. requireCaller rejects an anonymous callable request (needs the emulator + no auth header).',
    '  3. guest checkout retries: they now get { found: false } by design — see the open decision.',
  ].join('\n'));
}
process.exit(failures > 0 ? 1 : 0);
