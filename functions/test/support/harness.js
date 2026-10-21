'use strict';

// Zero-dependency harness that runs the REAL handlers in `functions/index.js` under plain Node.
//
// Why it has to exist: `index.js` cannot be imported normally — `lib/server.js` calls
// `admin.initializeApp()` at module load and `index.js` registers 39 callables + 3 triggers, so
// requiring it outside the Functions runtime needs credentials. This file intercepts those five
// external specifiers with an in-memory stand-in, then requires `index.js` untouched. The handlers,
// their ownership checks, their arithmetic and their HttpsError codes are the real ones; only the
// transport, the ID-token verification and Firestore itself are substituted.
//
// What a green test here does NOT prove — say it out loud rather than implying it:
//   * that the emulator/deployed runtime accepts the request, or that a real Firebase ID token maps
//     to `request.auth`. `onCall` is stubbed to its handler, so auth verification is bypassed by
//     construction: `asSigned(uid)` merely hands the handler the shape it expects.
//   * Firestore security rules (never evaluated here — see the note in fake-firestore.js).
//   * transaction serialization under concurrency, real `serverTimestamp()` values, or query ordering.
//   * the Dart client contract, which lives in lib/** and is covered by Flutter tests instead.
//
// Node's built-in test runner (`node --test test/`) is used deliberately: `functions/package.json`
// has no devDependencies and nothing is installed for this. Adding jest or firebase-functions-test
// would be an owner decision, not a convenience for the test author.

const Module = require('node:module');
const path = require('node:path');

const { createFirestore } = require('./fake-firestore');

const FUNCTIONS_ROOT = path.resolve(__dirname, '..', '..');
const EXTERNAL = new Set([
  'firebase-admin',
  'firebase-admin/firestore',
  'firebase-functions/v2',
  'firebase-functions/v2/https',
  'firebase-functions/v2/firestore',
]);

class HttpsError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = 'HttpsError';
    this.code = code;
    this.details = details;
  }
}

// `require('../index.js')` returns the registered handlers because `onCall` is the identity here.
//
// The epsilon default is the documented production default from `lib/server.js`
// (`Number(process.env.OM_PRICE_EPSILON_PAISE || 100)`). Pinning it here means a stray value in the
// shell of whoever runs `npm test` cannot make a rejection test pass by accident, or a tolerance test
// fail by accident. Pass `{ env: { OM_PRICE_EPSILON_PAISE: '...' } }` to exercise another value.
function createHarness({ env = {} } = {}) {
  const db = createFirestore();

  const adminStub = {
    initializeApp: () => adminStub,
    applicationDefault: 'test-firebase-adminsdk-creds',
    cert: () => 'test-cert',
    firestore: Object.assign(() => db, { FieldValue: db.FieldValue, Timestamp: db.Timestamp }),
    auth: () => new Proxy({}, { get: () => async () => ({ uid: 'test-uid' }) }),
  };
  const firestoreSubpathStub = { FieldValue: db.FieldValue, Timestamp: db.Timestamp };
  const functionsV2Stub = { setGlobalOptions: () => {} };
  const httpsStub = { onCall: (handler) => handler, HttpsError };
  const firestoreTriggerStub = {
    onDocumentCreated: (pattern, handler) => handler,
    onDocumentWritten: (pattern, handler) => handler,
  };
  const stubFor = (request) => {
    if (request === 'firebase-admin') return adminStub;
    if (request === 'firebase-admin/firestore') return firestoreSubpathStub;
    if (request === 'firebase-functions/v2') return functionsV2Stub;
    if (request === 'firebase-functions/v2/https') return httpsStub;
    if (request === 'firebase-functions/v2/firestore') return firestoreTriggerStub;
    return null;
  };

  const previousEnv = {};
  const envToApply = { OM_PRICE_EPSILON_PAISE: '100', ...env };
  for (const [key, value] of Object.entries(envToApply)) {
    previousEnv[key] = process.env[key];
    if (value === null) delete process.env[key];
    else process.env[key] = String(value);
  }

  const originalLoad = Module._load;
  Module._load = function patchedLoad(request, parent, isMain) {
    if (EXTERNAL.has(request) && parent && parent.filename && parent.filename.startsWith(FUNCTIONS_ROOT)) {
      return stubFor(request);
    }
    return originalLoad.call(this, request, parent, isMain);
  };

  let callables;
  let server;
  try {
    server = require(path.join(FUNCTIONS_ROOT, 'lib', 'server.js'));
    callables = require(path.join(FUNCTIONS_ROOT, 'index.js'));
  } finally {
    Module._load = originalLoad;
    for (const [key, value] of Object.entries(previousEnv)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }

  const { toInt } = require(path.join(FUNCTIONS_ROOT, 'lib', 'coerce'));
  const pricing = require(path.join(FUNCTIONS_ROOT, 'lib', 'pricing'));

  return new Harness({ db, server, callables, toInt, pricing });
}

class Harness {
  constructor({ db, server, callables, toInt, pricing }) {
    this.db = db;
    this.store = db.store;
    this.server = server;
    this.callables = callables;
    this.pricing = pricing;
    this.toInt = toInt;
  }

  // ---- lifecycle -------------------------------------------------------------------------

  reset() {
    this.store.clear();
    this.server.clearSettingsCache();
    return this;
  }

  put(docPath, data) {
    this.store.seed(docPath, data);
    return this;
  }

  read(docPath) {
    return this.store.snapshot(docPath);
  }

  reloadSettings() {
    this.server.clearSettingsCache();
    return this;
  }

  // ---- requests -------------------------------------------------------------------------

  asSigned(uid, token = {}) {
    return { auth: { uid, token: { email: `${uid}@example.test`, ...token } } };
  }

  asAnonymous() {
    return { auth: null };
  }

  async invoke(name, data, request = this.asAnonymous()) {
    const handler = this.callables[name];
    if (typeof handler !== 'function') throw new Error(`harness: ${name} is not a registered callable`);
    return handler({ ...request, data });
  }

  // Run `fn` and return the HttpsError the callable threw, or null when it resolved.
  async errorOf(fn) {
    try {
      await fn();
      return null;
    } catch (error) {
      return error;
    }
  }

  // ---- fixtures -------------------------------------------------------------------------

  settings(overrides = {}) {
    return this.put('store_settings/store', {
      taxRateBps: 0,
      taxInclusive: false,
      allowGuestCheckout: true,
      invoicePrefix: 'OME',
      freeShippingAbovePaise: null,
      shippingZones: [
        { id: 'z1', name: 'Bengaluru', pincodePrefixes: ['560'], flatRatePaise: 1000, freeAbovePaise: null, isActive: true },
      ],
      ...overrides,
    });
  }

  product(id = 'p1', overrides = {}) {
    return this.put(`products/${id}`, {
      name: `Product ${id}`,
      status: 'active',
      isWholesaleOnly: false,
      retailPricePaise: 11000,
      salePricePaise: null,
      stockQty: 100,
      lowStockThreshold: 2,
      categoryId: 'c1',
      slabs: [{ minQty: 1, maxQty: null, unitPricePaise: 10000, label: '1+' }],
      ...overrides,
    });
  }

  user(uid, overrides = {}) {
    return this.put(`users/${uid}`, {
      uid,
      email: `${uid}@example.test`,
      role: 'customer',
      isBlocked: false,
      wholesaleStatus: 'none',
      ...overrides,
    });
  }

  coupon(code, overrides = {}) {
    return this.put(`coupons/${code}`, {
      code,
      kind: 'flat',
      valuePaise: 500,
      percentOff: 0,
      maxDiscountPaise: null,
      minCartValuePaise: 0,
      minQty: 1,
      isActive: true,
      excludesWholesale: false,
      usedCount: 0,
      usageLimit: null,
      perUserLimit: 1,
      startsAt: null,
      endsAt: null,
      ...overrides,
    });
  }

  // A guest-placed or signed-in order document, exactly as `ordersCreate` writes it: guest rows carry
  // `userId: ''` and `isGuest: true`, and the ledger row carries `uid: null`.
  order(id, overrides = {}) {
    return this.put(`orders/${id}`, {
      orderNumber: 'OME-2026-000001',
      userId: '',
      isGuest: true,
      contactEmail: '',
      contactPhone: '',
      status: 'placed',
      paymentStatus: 'pending',
      totals: {
        subtotalPaise: 10000,
        slabDiscountPaise: 1000,
        couponDiscountPaise: 0,
        shippingPaise: 1000,
        taxPaise: 0,
        roundingPaise: 0,
        grandTotalPaise: 11000,
        paidPaise: 0,
        refundedPaise: 0,
      },
      ...overrides,
    });
  }

  ledger(key, overrides = {}) {
    return this.put(`idempotency_keys/${key}`, { orderId: '', uid: null, createdAt: null, ...overrides });
  }

  // A checkout draft the server will agree with: `clientTotalPaise` is derived from the same engine
  // the server uses, so a passing test proves the rule under test and not a total mismatch.
  // `discountPaise` lets a coupon test mirror the discount the server is about to grant; leave it at
  // 0 to assert the server REFUSES a discount (expired code, wrong scope) — the order then still
  // creates at full price, which is exactly what a client that re-quoted would send.
  // `totalOverride` exists for the epsilon tests: it replaces the derived figure with a stale one.
  draft({ key, qty = 1, productId = 'p1', pincode = '560001', deliveryMode = 'courier', couponCode = '', email = '', phone = '', shippingPaise = 1000, taxRateBps = 0, discountPaise = 0, unitPricePaise = 10000, totalOverride = null } = {}) {
    const totals = this.pricing.cartTotals(
      [{ qty, lineTotalPaise: unitPricePaise * qty, savedPaise: 0 }],
      { couponDiscountPaise: discountPaise, shippingPaise, taxRateBps },
    );
    return {
      idempotencyKey: key,
      // A deliberately wrong line price: the server must re-price from the stored slab and never read
      // this field as authoritative.
      lines: [{ productId, qty, lineTotalPaise: 1 }],
      deliveryMode,
      shipping: deliveryMode === 'pickup' ? null : { pincode, address: 'Test address' },
      couponCode,
      paymentMethod: 'cod',
      contactEmail: email,
      contactPhone: phone,
      clientTotalPaise: totalOverride == null ? totals.payableRoundedPaise : totalOverride,
    };
  }
}

module.exports = { createHarness, HttpsError };
