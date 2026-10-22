'use strict';

const { toInt } = require('./coerce');

const MAX_COLLISION_PROBES = 100;

// Order numbers are minted server-side only, never by the browser. The visible year must stay in
// sync with the counter scope: a monthly counter restarts at 1 every month, so the old
// PREFIX-YYYY-NNNNNN format could repeat a number in two months of the same year.
function orderNumber(prefix, year, seq) {
  const padded = String(seq).padStart(6, '0');
  return `${prefix || 'OME'}-${year}-${padded}`;
}

function orderYear(now) {
  return now.getFullYear();
}

function annualCounterId(now) {
  return `order-${orderYear(now)}`;
}

function legacyMonthlyCounterIds(year) {
  return Array.from({ length: 12 }, (_, index) => `order-${year}-${String(index + 1).padStart(2, '0')}`);
}

// Reads only: the caller writes { value: seq } in the same transaction. All reads must happen
// before that write (Firestore transactions reject read-after-write).
async function allocateOrderNumber({ tx, db, prefix, now = new Date(), maxCollisionProbes = MAX_COLLISION_PROBES }) {
  const year = orderYear(now);
  const counterRef = db.collection('counters').doc(annualCounterId(now));
  const counterSnap = await tx.get(counterRef);
  let seq = counterSnap.exists ? toInt(counterSnap.data().value) : 0;

  if (!counterSnap.exists) {
    // Continue past the highest legacy monthly counter for this year instead of restarting at 1.
    for (const id of legacyMonthlyCounterIds(year)) {
      const legacy = await tx.get(db.collection('counters').doc(id));
      if (legacy.exists) seq = Math.max(seq, toInt(legacy.data().value));
    }
  }

  for (let probe = 0; probe <= maxCollisionProbes; probe += 1) {
    const candidateSeq = seq + 1 + probe;
    const candidate = orderNumber(prefix, year, candidateSeq);
    // Pre-fix rows may already share a visible number. Never mint one that an existing order
    // carries; equality-only lookup needs no composite index. `size` rather than `empty` keeps the
    // unit-test DocSnapshot (which has neither) on the no-clash path.
    const clash = await tx.get(db.collection('orders').where('orderNumber', '==', candidate).limit(1));
    if (!clash || !(clash.size > 0)) {
      return { counterRef, year, seq: candidateSeq, number: candidate };
    }
  }

  const error = new Error('Could not allocate a unique order number. Contact support.');
  error.code = 'failed-precondition';
  throw error;
}

module.exports = {
  orderNumber,
  orderYear,
  annualCounterId,
  legacyMonthlyCounterIds,
  allocateOrderNumber,
};
