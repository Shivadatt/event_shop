'use strict';

// Server-only helpers. This module runs in the Cloud Functions Node runtime with full Admin SDK
// privileges — it is the ONLY code that may read cost price, mutate stock/role/payment status, or
// write audit rows. Nothing here is shipped to the browser. Credentials come from the runtime's
// Application Default Credentials; see docs/backend-setup.md. No key is embedded in source.

const admin = require('firebase-admin');
// `FieldValue`/`Timestamp` come from the `firebase-admin/firestore` subpath, not off `admin.firestore`.
// The Functions emulator proxies `firebase-admin` and returns `admin.firestore` already `.bind()`ed,
// and a bound function keeps only `length`/`name` — so inside a running handler
// `FieldValue` is `undefined` while `admin.firestore()` still works.
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

// Shared coercion helpers (no Admin SDK dependency) so lib/pricing.js and lib/checkout.js and this
// module cannot drift on how a paise amount is read out of a document or a callable payload.
const { toInt } = require('./coerce');
const { orderNumber } = require('./order_number');

// The Functions runtime initialises the Admin SDK from ADC; do not hardcode a project id.
admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

// Region must match Env.functionsRegion on the client; read from runtime config, never a literal
// that could silently desync the client's function calls.
const REGION = process.env.OM_FUNCTIONS_REGION || 'us-central1';

// Client total may disagree with the server by this much (paise) before createOrder refuses and
// asks the buyer to confirm the recomputed figure. Covers display rounding only, not real drift.
const PRICE_EPSILON_PAISE = Number(process.env.OM_PRICE_EPSILON_PAISE || 100);

const ADMIN_ROLES = ['staff', 'admin', 'owner'];
const PRICING_ROLES = ['admin', 'owner'];

// `toInt` is the shared coercion helper (lib/coerce.js) — the same binding lib/pricing.js and
// lib/checkout.js use, so the three modules cannot drift on how a paise amount is read.

// nanoid-style id: short, url-safe, sortable-enough. Document ids are opaque.
function newId() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = Timestamp.now().nanoseconds;
  let out = '';
  let seed = Date.now() ^ bytes;
  for (let i = 0; i < 21; i += 1) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    out += alphabet[seed % alphabet.length];
  }
  return out;
}

function normaliseCode(input) {
  return String(input || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9_-]/g, '');
}

// ---- Caller authentication + role resolution ------------------------------------------------

async function callerProfile(uid) {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return null;
  return { uid, ...(snap.data() || {}), _ref: snap.ref };
}

// Any logged-in, non-blocked user. Blocked users are denied everywhere.
async function requireCaller(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsAuthError('Unauthenticated');
  }
  const profile = await callerProfile(request.auth.uid);
  if (!profile) {
    throw new HttpsPermissionError('Profile not found. Please sign in again.');
  }
  if (profile.isBlocked === true) {
    throw new HttpsPermissionError('This account is suspended.');
  }
  return profile;
}

// Privileged functions re-verify role from the users/{uid} DOCUMENT — never from a token claim
// the client could have influenced. Custom claims are advisory; the doc is authoritative.
async function requireRole(request, roles = ADMIN_ROLES) {
  const caller = await requireCaller(request);
  if (!roles.includes(caller.role)) {
    throw new HttpsPermissionError('You do not have permission to perform this action.');
  }
  return caller;
}

// Thin wrappers so handlers throw the canonical Functions error the Dart side maps to an
// OmFailure. HttpsError lives in firebase-functions/v2/https; require lazily to avoid a cycle.
class HttpsAuthError extends Error {
  constructor(message) {
    super(message);
    this.code = 'unauthenticated';
  }
}
class HttpsPermissionError extends Error {
  constructor(message) {
    super(message);
    this.code = 'permission-denied';
  }
}

// ---- Audit ----------------------------------------------------------------------------------

// Every sensitive mutation lands one append-only audit_logs row. Pass the active transaction so
// the audit commit is atomic with the change it describes.
async function writeAudit(handle, entry) {
  const ref = db.collection('audit_logs').doc();
  const record = {
    action: entry.action,
    entityType: entry.entityType,
    entityId: entry.entityId,
    actorUid: entry.actorUid || '',
    actorRole: entry.actorRole || '',
    summary: entry.summary || '',
    before: entry.before || {},
    after: entry.after || {},
    createdAt: FieldValue.serverTimestamp(),
  };
  if (handle && typeof handle.set === 'function') {
    handle.set(ref, record);
    return ref.id;
  }
  await ref.set(record);
  return ref.id;
}

// ---- Store settings (tax basis points, shipping, invoice prefix) -----------------------------

let _settingsCache = null;
let _settingsCacheAt = 0;
async function readStoreSettings(maxAgeMs = 15000) {
  const now = Date.now();
  if (_settingsCache && now - _settingsCacheAt < maxAgeMs) return _settingsCache;
  const snap = await db.collection('store_settings').doc('store').get();
  _settingsCache = snap.exists ? snap.data() || {} : {};
  _settingsCacheAt = now;
  return _settingsCache;
}

function clearSettingsCache() {
  _settingsCache = null;
  _settingsCacheAt = 0;
}

// ---- Field allow-lists + size caps for the two intentional public writes ---------------------

// A public write may ONLY set these fields, must be a primitive of bounded length, and must not
// smuggle privileged keys. Anything else is rejected before the document ever reaches Firestore.
function enforceAllowList(data, allowList, { maxArrayLength = 0 } = {}) {
  const errors = [];
  for (const key of Object.keys(data)) {
    if (!allowList.includes(key)) {
      errors.push(`Field "${key}" is not writable here.`);
      continue;
    }
    const value = data[key];
    if (typeof value === 'string' && value.length > 4000) {
      errors.push(`Field "${key}" is too long (max 4000 chars).`);
    }
    if (Array.isArray(value) && maxArrayLength > 0 && value.length > maxArrayLength) {
      errors.push(`Field "${key}" may hold at most ${maxArrayLength} items.`);
    }
    if (Array.isArray(value)) {
      for (const item of value) {
        if (item != null && typeof item === 'object') {
          errors.push(`Field "${key}" must contain only scalar values.`);
          break;
        }
      }
    }
  }
  if (errors.length) {
    throw new HttpsInvalidArgument(errors.join(' '));
  }
}

class HttpsInvalidArgument extends Error {
  constructor(message) {
    super(message);
    this.code = 'invalid-argument';
  }
}

// Total document size guard for public writes: keep a client from bloating a doc past the 1 MiB
// Firestore limit / our own conservative cap.
function enforceSizeCap(data, maxBytes = 32 * 1024) {
  const size = Buffer.byteLength(JSON.stringify(data), 'utf8');
  if (size > maxBytes) {
    throw new HttpsInvalidArgument(`Payload exceeds the ${maxBytes} byte limit.`);
  }
}

module.exports = {
  admin,
  db,
  auth,
  FieldValue,
  Timestamp,
  REGION,
  PRICE_EPSILON_PAISE,
  ADMIN_ROLES,
  PRICING_ROLES,
  toInt,
  newId,
  normaliseCode,
  orderNumber,
  callerProfile,
  requireCaller,
  requireRole,
  writeAudit,
  readStoreSettings,
  clearSettingsCache,
  enforceAllowList,
  enforceSizeCap,
  HttpsAuthError,
  HttpsPermissionError,
  HttpsInvalidArgument,
};
