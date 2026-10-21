'use strict';

// Coercion primitives shared by the pure contract modules (lib/pricing.js, lib/checkout.js) and
// by lib/server.js. Deliberately Firebase-free: `functions/test/**` imports them without an
// emulator, and `firebase-admin` must never become a dependency of a value-coercion helper.

// Firestore/JSON values arrive as numbers, numeric strings (CSV imports, --dart-define payloads),
// Firestore Timestamps, Dates, epoch millis, or null. Money is integer paise: truncate, never round
// a fraction of paise into a charged amount.
function toInt(value, fallback = 0) {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = parseInt(value, 10);
    if (!Number.isNaN(parsed)) return parsed;
  }
  return fallback;
}

// Millis for any date shape a document or a callable payload can hold, or null when there is no
// constraint. `null` means "unbounded", so an unreadable value must never become 0 (epoch) — that
// would make every sale/coupon window expire in 1970.
function toMillis(value) {
  if (value == null) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (value instanceof Date) return value.getTime();
  // Firestore Timestamp (admin and the emulator proxy both expose _seconds / toMillis).
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  // ISO-8601 strings: a callable payload from the Dart client carries DateTime as a string, while
  // a document written by the SDK carries a Timestamp. Both must mean the same instant.
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

module.exports = { toInt, toMillis };
