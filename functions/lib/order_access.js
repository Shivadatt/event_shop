'use strict';

// Pure, Firebase-free decision helpers for reading a replayed order back to its buyer.
//
// Why this is a separate module: `functions/index.js` cannot be `require()`d outside the Functions
// runtime (it calls `initializeApp` and registers 42 exports), so the two rules that a security
// regression has to pin down — WHO may read a replay, and WHICH id the receipt carries — live here
// where `scripts/check_order_replay_guard.js` can assert them with plain Node and no emulator.
// index.js keeps the I/O; this file keeps the decision.
//
// Money rule (unchanged): every amount on the receipt is copied from the STORED order document.
// Nothing here reads a client-supplied total, so a replay can never be re-priced by the caller.
//
// OWNER RULINGS RECORDED (2026-10-21) — these three are settled, not open questions:
//   1. A staff/admin/owner role NEVER bypasses replay ownership. Not here, not in `ordersCreate`.
//   2. A guest order is replayable only by the guest who placed it, and key possession alone is not
//      authorisation: the retry must re-supply the contact detail stored on the order.
//   3. `lib/checkout.js` no longer carries a competing replay rule or `receiptFromOrder`; this module
//      is the only owner of both. Its remaining helpers (coupon scope, zones, pincode, price
//      agreement) are the authoritative copies that `index.js` now imports.

// Build the receipt the Dart `OrderReceipt.fromMap` expects.
//
// `orderId` is a required, explicit argument and is written LAST into nothing — it is never taken
// from `orderData`, so a stored (or attacker-written) `id`/`orderId` field inside the document
// cannot override the id the caller is actually being told about.
function receiptFromOrder(orderData, orderId, { wasReplay = false } = {}) {
  const o = orderData || {};
  return {
    orderId: String(orderId || ''),
    orderNumber: o.orderNumber,
    totals: o.totals,
    paymentStatus: o.paymentStatus,
    orderStatus: o.status,
    paymentClientSecret: '',
    paymentUrl: '',
    wasReplay: Boolean(wasReplay),
    priceChanged: false,
    message: wasReplay ? 'This order already exists.' : '',
  };
}

// Cheap first gate: does the key record itself point at an order this caller owns?
// Checked BEFORE the order document is read, so guessing keys cannot be turned into free Firestore
// reads (there is no rate limiting on these callables yet).
function keyPointsToOwnedOrder({ keyRecord, callerUid } = {}) {
  // A caller with no account cannot own anything. Guards against an accidental `undefined` match
  // against a legacy row whose `userId` is also empty.
  if (typeof callerUid !== 'string' || callerUid.length === 0) return false;
  if (!keyRecord) return false;
  // ordersCreate writes `uid: uid || null`, so a guest-placed key carries null. A guest order has no
  // account to authorise against and its receipt holds contact PII: never readable.
  if (typeof keyRecord.uid !== 'string' || keyRecord.uid.length === 0) return false;
  if (keyRecord.uid !== callerUid) return false;
  // The key points at something; it must still be a usable, non-blank order id.
  if (typeof keyRecord.orderId !== 'string' || keyRecord.orderId.length === 0) return false;
  return true;
}

// May `callerUid` be shown the receipt for this (key record, order document) pair?
//
// Every rejection answers the same way at the callable boundary (`{ found: false }`), so none of
// these branches can be used to probe whether a key or an order exists.
function mayReadReplay({ keyRecord, orderData, callerUid } = {}) {
  return signedInReplayAgrees({ keyRecord, orderData, callerUid });
}

// The single signed-in rule, shared by the `orderByIdempotency` lookup above and by `ordersCreate`'s
// replay branch, so the two can never disagree about who owns a key.
//
// Ledger, order document and caller must all name the SAME account. A role is deliberately not a
// parameter: being staff is not ownership, and a staff member replaying a buyer's key gets the same
// refusal as any stranger.
function signedInReplayAgrees({ keyRecord, orderData, callerUid } = {}) {
  if (!keyPointsToOwnedOrder({ keyRecord, callerUid })) return false;
  if (!orderData) return false;
  // Defence in depth: the order document must agree with the ledger. A key record that was written
  // for one order but now resolves to another buyer's document is refused, and a document flagged
  // `isGuest` is refused even if the ledger row somehow carries a uid.
  if (orderData.isGuest === true) return false;
  if (orderData.userId !== callerUid) return false;
  return true;
}

// ---- guest replay ------------------------------------------------------------------------------

// A guest order has no account to authorise against, so `ordersCreate` cannot use the rule above —
// and key possession must not become the fallback authenticator, because a key in a support ticket,
// a browser log or an analytics payload would then be a bearer token onto somebody's name, phone,
// address and totals. The retry therefore has to re-supply a contact detail that only the original
// buyer has: the email or the phone recorded on the order at create time.
//
// Consequence (and a real limitation, not a bug to paper over): a guest who retries with a DIFFERENT
// contact detail cannot get their existing order back, and a guest order stored with neither an email
// nor a phone is permanently unreplayable. Both answer REPLAY_REFUSED, and the buyer starts a fresh
// checkout with a fresh key. No signed-in lookup can help either, because `orderByIdempotency`
// requires an account.
function guestReplayAgrees({ keyRecord, orderData, contactEmail, contactPhone } = {}) {
  if (!keyRecord) return false;
  // Only a key that was placed anonymously may be replayed anonymously. `uid: null` is not
  // authorisation on its own — it merely opens this gate; the contact match below decides.
  if (normaliseUid(keyRecord.uid) !== null) return false;
  if (!orderData) return false;
  if (orderData.isGuest !== true) return false;
  // Guest documents store `userId: ''` (index.js writes `uid || ''`), never a real uid.
  if (normaliseUid(orderData.userId) !== null) return false;
  const storedEmail = normaliseContact(orderData.contactEmail);
  const givenEmail = normaliseContact(contactEmail);
  if (storedEmail !== null && givenEmail !== null && storedEmail === givenEmail) return true;
  const storedPhone = normalisePhone(orderData.contactPhone);
  const givenPhone = normalisePhone(contactPhone);
  if (storedPhone !== null && givenPhone !== null && storedPhone === givenPhone) return true;
  return false;
}

// `ordersCreate` entry point. `callerUid` is null for an anonymous request, so the caller's own
// authenticated/guest state selects the rule — a signed-in buyer can never take the guest path and a
// guest can never take the signed-in path.
function mayReplayCreatedOrder({ keyRecord, orderData, callerUid, contactEmail, contactPhone } = {}) {
  return normaliseUid(callerUid) === null
    ? guestReplayAgrees({ keyRecord, orderData, contactEmail, contactPhone })
    : signedInReplayAgrees({ keyRecord, orderData, callerUid });
}

// Used for EVERY refused replay in `ordersCreate` — somebody else's key, a guest-placed key presented
// by a signed-in buyer, a ledger row whose order no longer exists, a document that disagrees with its
// ledger row, and a guest retry whose contact proof does not match. One string, no sub-case in it, so
// the response cannot be read as "yes, that key exists".
const REPLAY_REFUSED = 'This order could not be confirmed for the current buyer. Please start a new checkout to continue.';

function normaliseUid(value) {
  if (value == null) return null;
  const text = String(value);
  return text === '' ? null : text;
}

// Trim + case-fold: `firestore_order_repository.byOrderNumber` already compares guest emails
// case-insensitively, and Firestore stores what the buyer typed.
function normaliseContact(value) {
  if (value == null) return null;
  const text = String(value).trim().toLowerCase();
  return text === '' ? null : text;
}

// Digits only, then an EXACT comparison: "+91 98765 43210" and "+91-98765-43210" match, while
// "9876543210" does not match "+919876543210". Trimming a country code or comparing suffixes would
// widen what counts as proof of contact, so the buyer has to re-supply the number as typed.
function normalisePhone(value) {
  if (value == null) return null;
  const digits = String(value).replace(/\D+/g, '');
  return digits === '' ? null : digits;
}

module.exports = {
  receiptFromOrder,
  keyPointsToOwnedOrder,
  mayReadReplay,
  signedInReplayAgrees,
  guestReplayAgrees,
  mayReplayCreatedOrder,
  REPLAY_REFUSED,
};
