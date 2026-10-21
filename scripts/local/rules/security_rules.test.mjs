// Firestore security-rules tests against the local emulator, with no npm dependencies.
//
// Prerequisites (see docs/local-demo.md):
//   npx --yes firebase-tools@13.35.1 emulators:start \
//     --config firebase.local.strict.json --project demo-om-events --only auth,firestore
// Then:  node --test scripts/local/rules/security_rules.test.mjs
//
// The harness reloads ../../../firestore.rules with ignore_errors=false first, so a syntax error
// fails the run immediately. Fixtures are written with the emulator's `Bearer owner` bypass; every
// assertion is made with a real Auth-emulator ID token (or no token for anonymous).
//
// Identities are created fresh per run, and every seeded document id carries a run suffix, so
// repeated runs cannot collide.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { before, test } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT = process.env.OM_PROJECT ?? 'demo-om-events';
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const AUTH_HOST = process.env.AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const FS = `http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
const AUTH = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1`;
const RULES_PATH = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'firestore.rules');
const runId = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;

// ---------- Firestore REST value shapes ----------
const S = (v) => ({ stringValue: v });
const B = (v) => ({ booleanValue: v });
const I = (v) => ({ integerValue: String(v) });
const T = (v = new Date()) => ({ timestampValue: v.toISOString() });
const A = (...values) => ({ arrayValue: { values } });
const M = (fields) => ({ mapValue: { fields } });
const msg = (from, body, isStaff = false) =>
  M({ from: S(from), body: S(body), at: T(), isStaff: B(isStaff) });

async function call(url, { method = 'GET', token, body } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    // empty body is fine
  }
  return { status: res.status, json };
}

const docPath = (path) => `${FS}/${path}`;

async function seed(path, fields) {
  const res = await call(docPath(path), { method: 'PATCH', token: 'owner', body: { fields } });
  if (res.status !== 200) {
    throw new Error(`seed ${path} failed: ${res.status} ${JSON.stringify(res.json)}`);
  }
  return res;
}

const read = (path, token) => call(docPath(path), { token });

async function ownerFields(path) {
  const res = await call(docPath(path), { token: 'owner' });
  if (res.status !== 200) throw new Error(`owner read ${path} failed: ${res.status}`);
  return res.json.fields;
}
const write = (path, fields, token) =>
  call(docPath(path), { method: 'PATCH', token, body: { fields } });
const writeMasked = (path, fields, mask, token) => {
  const params = mask.map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join('&');
  return call(`${docPath(path)}?${params}`, { method: 'PATCH', token, body: { fields } });
};
const remove = (path, token) => call(docPath(path), { method: 'DELETE', token });

async function runQuery(collection, { filters = [], orderBy = [], limit, token } = {}) {
  const structuredQuery = { from: [{ collectionId: collection }] };
  if (filters.length > 0) {
    const parts = filters.map(([field, op, value]) => ({
      fieldFilter: { field: { fieldPath: field }, op, value },
    }));
    structuredQuery.where =
      parts.length === 1 ? parts[0] : { compositeFilter: { op: 'AND', filters: parts } };
  }
  if (orderBy.length > 0) structuredQuery.orderBy = orderBy;
  if (limit) structuredQuery.limit = limit;
  return call(`${FS}:runQuery`, { method: 'POST', token, body: { structuredQuery } });
}

function ok(res, label) {
  assert.equal(res.status, 200, `${label}: expected allow (200), got ${res.status} ${JSON.stringify(res.json)}`);
}
function denied(res, label) {
  assert.equal(res.status, 403, `${label}: expected deny (403), got ${res.status} ${JSON.stringify(res.json)}`);
}
function missing(res, label) {
  assert.equal(res.status, 404, `${label}: expected 404, got ${res.status} ${JSON.stringify(res.json)}`);
}

// ---------- identities ----------
let n = 0;
async function signUp(label) {
  n += 1;
  const email = `rules.${runId}.${n}.${label}@example.test`;
  const res = await call(`${AUTH}/accounts:signUp?key=fake-api-key`, {
    method: 'POST',
    body: { email, password: 'rules-test-password', returnSecureToken: true },
  });
  if (res.status !== 200) throw new Error(`auth signUp failed: ${res.status} ${JSON.stringify(res.json)}`);
  return { uid: res.json.localId, token: res.json.idToken, email };
}

const profile = (uid, email, { role = 'customer', wholesaleStatus = 'none', blocked = false } = {}) => ({
  uid: S(uid),
  email: S(email),
  displayName: S(`Rules ${role}`),
  phone: S(''),
  role: S(role),
  wholesaleStatus: S(wholesaleStatus),
  isBlocked: B(blocked),
  notifyEmail: B(true),
  notifyWhatsapp: B(false),
  notifySms: B(false),
  wishlistProductIds: A(),
  createdAt: T(),
  updatedAt: T(),
});

const ids = {};
let seedCounter = 0;
const fresh = (base) => {
  seedCounter += 1;
  return `${base}_${runId}_${seedCounter}`;
};

before(async () => {
  // A syntax/compile failure must fail the run before any assertion pretends the rules are live.
  const rules = readFileSync(RULES_PATH, 'utf8');
  const compile = await call(`http://${FS_HOST}/emulator/v1/projects/${PROJECT}:securityRules`, {
    method: 'PUT',
    body: { ignore_errors: false, rules: { files: [{ name: 'security.rules', content: rules }] } },
  });
  assert.equal(compile.status, 200, `rules compile failed: ${compile.status} ${JSON.stringify(compile.json)}`);

  ids.anon = null;
  ids.a = await signUp('a');
  ids.b = await signUp('b');
  ids.staff = await signUp('staff');
  ids.admin = await signUp('admin');
  ids.wholesale = await signUp('wholesale');
  ids.blocked = await signUp('blocked');
  ids.noProfile = await signUp('noprofile');

  await seed(`users/${ids.a.uid}`, profile(ids.a.uid, ids.a.email));
  await seed(`users/${ids.b.uid}`, profile(ids.b.uid, ids.b.email));
  await seed(`users/${ids.staff.uid}`, profile(ids.staff.uid, ids.staff.email, { role: 'staff' }));
  await seed(`users/${ids.admin.uid}`, profile(ids.admin.uid, ids.admin.email, { role: 'admin' }));
  await seed(
    `users/${ids.wholesale.uid}`,
    profile(ids.wholesale.uid, ids.wholesale.email, { wholesaleStatus: 'approved' }),
  );
  await seed(`users/${ids.blocked.uid}`, profile(ids.blocked.uid, ids.blocked.email, { blocked: true }));

  ids.productPublic = fresh('prod_public');
  ids.productWholesale = fresh('prod_wholesale');
  ids.productDraft = fresh('prod_draft');
  ids.productArchived = fresh('prod_archived');
  ids.categoryActive = fresh('cat_active');
  ids.categoryInactive = fresh('cat_inactive');
  ids.variant = fresh('variant');
  ids.variantWholesale = fresh('variant_wholesale');
  ids.orderA = fresh('order_a');
  ids.orderB = fresh('order_b');
  ids.historyA = fresh('history_a');
  ids.historyB = fresh('history_b');
  ids.paymentA = fresh('pay_a');
  ids.paymentB = fresh('pay_b');
  ids.reviewPublished = fresh('review_pub');
  ids.reviewPendingB = fresh('review_pending_b');
  ids.coupon = fresh('coupon');
  ids.redemption = fresh('redemption');
  ids.addressA = fresh('addr_a');
  ids.addressB = fresh('addr_b');
  ids.wholesaleAppA = fresh('wholesale_a');
  ids.ticketA = fresh('ticket_a');
  ids.ticketB = fresh('ticket_b');
  ids.notificationA = fresh('notif_a');
  ids.notificationB = fresh('notif_b');
  ids.movement = fresh('movement');
  ids.alert = fresh('alert');
  ids.audit = fresh('audit');
  ids.media = fresh('media');
  ids.override = fresh('override');
  ids.counter = fresh('counter');
  ids.idempotency = fresh('idempotency');
  ids.unknown = fresh('unknown');

  const product = (extra) => ({
    name: S('Test product'),
    slug: S(ids.productPublic),
    sku: S(ids.productPublic),
    categorySlug: S('test'),
    categoryId: S(ids.categoryActive),
    status: S('active'),
    isWholesaleOnly: B(false),
    retailPricePaise: I(10000),
    wholesalePricePaise: I(8000),
    stockQty: I(10),
    soldCount: I(0),
    ratingAvg: { doubleValue: 0 },
    keywords: A(S('test'), S('product')),
    createdAt: T(),
    ...extra,
  });
  await seed(`products/${ids.productPublic}`, product({}));
  await seed(
    `products/${ids.productWholesale}`,
    product({ isWholesaleOnly: B(true), slug: S(ids.productWholesale), sku: S(ids.productWholesale) }),
  );
  await seed(
    `products/${ids.productDraft}`,
    product({ status: S('draft'), slug: S(ids.productDraft), sku: S(ids.productDraft) }),
  );
  await seed(
    `products/${ids.productArchived}`,
    product({
      status: S('archived'),
      isWholesaleOnly: B(true),
      slug: S(ids.productArchived),
      sku: S(ids.productArchived),
    }),
  );
  await seed(`categories/${ids.categoryActive}`, {
    name: S('Active category'),
    slug: S('active-cat'),
    isActive: B(true),
    order: I(1),
  });
  await seed(`categories/${ids.categoryInactive}`, {
    name: S('Inactive category'),
    slug: S('inactive-cat'),
    isActive: B(false),
    order: I(2),
  });
  await seed(`product_variants/${ids.variant}`, {
    productId: S(ids.productPublic),
    label: S('10 inch'),
    retailPricePaise: I(10000),
    costPricePaise: I(6000),
    stockQty: I(5),
    order: I(1),
  });
  await seed(`product_variants/${ids.variantWholesale}`, {
    productId: S(ids.productWholesale),
    label: S('Bulk'),
    retailPricePaise: I(8000),
    costPricePaise: I(5000),
    stockQty: I(5),
    order: I(1),
  });
  await seed(`orders/${ids.orderA}`, {
    userId: S(ids.a.uid),
    orderNumber: S('OM-TEST-1'),
    status: S('placed'),
    totalPaise: I(10000),
    isGuest: B(false),
    createdAt: T(),
  });
  await seed(`orders/${ids.orderB}`, {
    userId: S(ids.b.uid),
    orderNumber: S('OM-TEST-2'),
    status: S('placed'),
    totalPaise: I(20000),
    isGuest: B(false),
    createdAt: T(),
  });
  await seed(`orders/${ids.orderA}/history/${ids.historyA}`, { event: S('placed'), at: T() });
  await seed(`orders/${ids.orderB}/history/${ids.historyB}`, { event: S('placed'), at: T() });
  await seed(`payments/${ids.paymentA}`, { uid: S(ids.a.uid), amountPaise: I(10000), status: S('captured') });
  await seed(`payments/${ids.paymentB}`, { uid: S(ids.b.uid), amountPaise: I(20000), status: S('captured') });
  await seed(`reviews/${ids.reviewPublished}`, {
    uid: S(ids.b.uid),
    productId: S(ids.productPublic),
    rating: I(5),
    status: S('published'),
    createdAt: T(),
  });
  await seed(`reviews/${ids.reviewPendingB}`, {
    uid: S(ids.b.uid),
    productId: S(ids.productPublic),
    rating: I(4),
    status: S('pending'),
    createdAt: T(),
  });
  await seed(`coupons/${ids.coupon}`, { code: S('TEST10'), isActive: B(true), percentOff: I(10) });
  await seed(`coupon_redemptions/${ids.redemption}`, { couponId: S(ids.coupon), uid: S(ids.a.uid) });
  await seed(`addresses/${ids.addressA}`, {
    uid: S(ids.a.uid),
    name: S('Buyer A'),
    phone: S('9876543210'),
    line1: S('1 Test Street'),
    line2: S(''),
    city: S('Pune'),
    state: S('MH'),
    pincode: S('411001'),
    gstNumber: S(''),
    isDefaultShipping: B(true),
    isDefaultBilling: B(false),
    isWorkAddress: B(false),
    createdAt: T(),
    updatedAt: T(),
  });
  await seed(`addresses/${ids.addressB}`, {
    uid: S(ids.b.uid),
    name: S('Buyer B'),
    phone: S('9876543211'),
    line1: S('2 Test Street'),
    line2: S(''),
    city: S('Pune'),
    state: S('MH'),
    pincode: S('411001'),
    gstNumber: S(''),
    isDefaultShipping: B(true),
    isDefaultBilling: B(false),
    isWorkAddress: B(false),
    createdAt: T(),
    updatedAt: T(),
  });
  await seed(`wholesale_applications/${ids.wholesaleAppA}`, {
    uid: S(ids.a.uid),
    companyName: S('A Traders'),
    contactName: S('Buyer A'),
    phone: S('9876543210'),
    email: S(ids.a.email),
    gstNumber: S(''),
    address: S(''),
    reason: S(''),
    expectedMonthlyVolume: S(''),
    status: S('pending'),
    createdAt: T(),
  });
  await seed(`support_requests/${ids.ticketA}`, {
    uid: S(ids.a.uid),
    subject: S('Where is my order?'),
    orderId: S(ids.orderA),
    productId: S(''),
    topic: S('orderIssue'),
    status: S('open'),
    messages: A(msg(ids.a.uid, 'First message')),
    createdAt: T(),
    updatedAt: T(),
  });
  await seed(`support_requests/${ids.ticketB}`, {
    uid: S(ids.b.uid),
    subject: S('B ticket'),
    orderId: S(''),
    productId: S(''),
    topic: S('other'),
    status: S('open'),
    messages: A(msg(ids.b.uid, 'B first message')),
    createdAt: T(),
    updatedAt: T(),
  });
  await seed(`notifications/${ids.notificationA}`, {
    uid: S(ids.a.uid),
    title: S('Order update'),
    body: S('Your order moved'),
    isRead: B(false),
    createdAt: T(),
  });
  await seed(`notifications/${ids.notificationB}`, {
    uid: S(ids.b.uid),
    title: S('Order update'),
    body: S('B order moved'),
    isRead: B(false),
    createdAt: T(),
  });
  await seed(`inventory_movements/${ids.movement}`, { sku: S('TEST'), delta: I(5), at: T() });
  await seed(`inventory_alerts/${ids.alert}`, { sku: S('TEST'), level: S('low'), at: T() });
  await seed(`audit_logs/${ids.audit}`, { action: S('test'), actorRole: S('admin'), at: T() });
  await seed(`media_objects/${ids.media}`, { url: S('https://example.test/a.jpg'), alt: S('Test') });
  await seed(`customer_price_overrides/${ids.override}`, { uid: S(ids.a.uid), pricePaise: I(9000) });
  await seed(`counters/${ids.counter}`, { value: I(1) });
  await seed(`idempotency_keys/${ids.idempotency}`, { key: S('k'), result: S('ok') });
  await seed(`store_settings/store`, { storeName: S('Test store'), taxMode: S('inclusive') });
  await seed(`probe_unknown_${runId}/${ids.unknown}`, { foo: S('bar') });
});

// =====================================================================================
// Compilation and live enforcement
// =====================================================================================

test('rules compile and are live: a signed-in token reaches the catch-all, not a 404', async () => {
  // If the reload in before() had been ignored, the emulator would still answer; the assertion
  // below proves the file that was compiled is the one evaluating requests.
  const res = await read(`probe_unknown_${runId}/${ids.unknown}`, ids.a.token);
  denied(res, 'unknown collection read');
});

// =====================================================================================
// Unauthenticated access
// =====================================================================================

test('anonymous: public catalogue rows are readable', async () => {
  ok(await read(`products/${ids.productPublic}`, ids.anon), 'active retail product');
  ok(await read(`categories/${ids.categoryActive}`, ids.anon), 'active category');
  ok(await read(`reviews/${ids.reviewPublished}`, ids.anon), 'published review');
  ok(await read('store_settings/store', ids.anon), 'store settings');
  ok(await read(`media_objects/${ids.media}`, ids.anon), 'media metadata');
});

test('anonymous: wholesale-only, draft and archived products are not readable', async () => {
  denied(await read(`products/${ids.productWholesale}`, ids.anon), 'wholesale-only product');
  denied(await read(`products/${ids.productDraft}`, ids.anon), 'draft product');
  denied(await read(`products/${ids.productArchived}`, ids.anon), 'archived product');
});

test('anonymous: private collections are not readable', async () => {
  denied(await read(`users/${ids.a.uid}`, ids.anon), 'user profile');
  denied(await read(`addresses/${ids.addressA}`, ids.anon), 'address');
  denied(await read(`orders/${ids.orderA}`, ids.anon), 'order');
  denied(await read(`orders/${ids.orderA}/history/${ids.historyA}`, ids.anon), 'order history');
  denied(await read(`payments/${ids.paymentA}`, ids.anon), 'payment');
  denied(await read(`support_requests/${ids.ticketA}`, ids.anon), 'support ticket');
  denied(await read(`notifications/${ids.notificationA}`, ids.anon), 'notification');
  denied(await read(`product_variants/${ids.variant}`, ids.anon), 'variant');
  denied(await read(`coupons/${ids.coupon}`, ids.anon), 'coupon');
  denied(await read(`audit_logs/${ids.audit}`, ids.anon), 'audit log');
  denied(await read(`inventory_movements/${ids.movement}`, ids.anon), 'inventory movement');
  denied(await read(`categories/${ids.categoryInactive}`, ids.anon), 'inactive category');
});

test('anonymous: no writes are accepted', async () => {
  const address = {
    uid: S(ids.a.uid),
    name: S('Anon'),
    phone: S('1'),
    line1: S('x'),
    city: S('x'),
    state: S('x'),
    pincode: S('x'),
    isDefaultShipping: B(false),
    isDefaultBilling: B(false),
    isWorkAddress: B(false),
    createdAt: T(),
    updatedAt: T(),
  };
  denied(await write(`addresses/anon_${runId}`, address, ids.anon), 'create address anonymously');
  denied(
    await write(`support_requests/anon_${runId}`, {
      uid: S(ids.a.uid),
      subject: S('x'),
      orderId: S(''),
      productId: S(''),
      topic: S('other'),
      status: S('open'),
      messages: A(),
      createdAt: T(),
      updatedAt: T(),
    }, ids.anon),
    'create support ticket anonymously',
  );
  denied(await write(`products/${ids.productPublic}`, { status: S('draft') }, ids.anon), 'update product');
  denied(await write(`users/${ids.a.uid}`, { role: S('admin') }, ids.anon), 'update profile');
  denied(await write(`notifications/${ids.notificationA}`, { isRead: B(true) }, ids.anon), 'ack notification');
  denied(await write(`orders/${ids.orderA}`, { status: S('cancelled') }, ids.anon), 'update order');
});

test('anonymous: unconstrained list queries are denied, constrained catalogue queries are allowed', async () => {
  denied(await runQuery('products', { token: ids.anon }), 'unconstrained product list');
  denied(
    await runQuery('products', {
      token: ids.anon,
      filters: [['status', 'EQUAL', S('active')]],
    }),
    'product list without the wholesale-only constraint',
  );
  ok(
    await runQuery('products', {
      token: ids.anon,
      filters: [
        ['status', 'EQUAL', S('active')],
        ['isWholesaleOnly', 'EQUAL', B(false)],
      ],
    }),
    'retail catalogue list',
  );
  denied(await runQuery('categories', { token: ids.anon }), 'unconstrained category list');
  ok(
    await runQuery('categories', {
      token: ids.anon,
      filters: [['isActive', 'EQUAL', B(true)]],
    }),
    'active category list',
  );
  ok(
    await runQuery('reviews', {
      token: ids.anon,
      filters: [['status', 'EQUAL', S('published')]],
    }),
    'published review list',
  );
  denied(await runQuery('reviews', { token: ids.anon }), 'unconstrained review list');
});

// =====================================================================================
// Customer A vs customer B
// =====================================================================================

test('customer A reads own profile, not B profile, and cannot list users', async () => {
  ok(await read(`users/${ids.a.uid}`, ids.a.token), 'own profile');
  denied(await read(`users/${ids.b.uid}`, ids.a.token), 'B profile');
  denied(await runQuery('users', { token: ids.a.token }), 'user list');
});

test('customer A cannot read or write B addresses', async () => {
  ok(await read(`addresses/${ids.addressA}`, ids.a.token), 'own address');
  denied(await read(`addresses/${ids.addressB}`, ids.a.token), 'B address');
  denied(
    await writeMasked(`addresses/${ids.addressB}`, { city: S('Mumbai') }, ['city'], ids.a.token),
    'update B address',
  );
  denied(await remove(`addresses/${ids.addressB}`, ids.a.token), 'delete B address');
});

test('customer order reads are owner-scoped; lists must constrain userId', async () => {
  ok(await read(`orders/${ids.orderA}`, ids.a.token), 'own order');
  denied(await read(`orders/${ids.orderB}`, ids.a.token), 'B order');
  ok(await read(`orders/${ids.orderA}/history/${ids.historyA}`, ids.a.token), 'own order history');
  denied(await read(`orders/${ids.orderB}/history/${ids.historyB}`, ids.a.token), 'B order history');
  ok(
    await runQuery('orders', {
      token: ids.a.token,
      filters: [['userId', 'EQUAL', S(ids.a.uid)]],
    }),
    'own order list',
  );
  denied(
    await runQuery('orders', {
      token: ids.a.token,
      filters: [['userId', 'EQUAL', S(ids.b.uid)]],
    }),
    'B order list',
  );
  denied(await runQuery('orders', { token: ids.a.token }), 'unconstrained order list');
});

test('customer A cannot read B payments, support thread, notification or application', async () => {
  ok(await read(`payments/${ids.paymentA}`, ids.a.token), 'own payment');
  denied(await read(`payments/${ids.paymentB}`, ids.a.token), 'B payment');
  ok(await read(`support_requests/${ids.ticketA}`, ids.a.token), 'own support ticket');
  denied(await read(`support_requests/${ids.ticketB}`, ids.a.token), 'B support ticket');
  ok(await read(`notifications/${ids.notificationA}`, ids.a.token), 'own notification');
  denied(await read(`notifications/${ids.notificationB}`, ids.a.token), 'B notification');
  ok(await read(`wholesale_applications/${ids.wholesaleAppA}`, ids.a.token), 'own wholesale application');
  denied(
    await runQuery('support_requests', {
      token: ids.b.token,
      filters: [['uid', 'EQUAL', S(ids.a.uid)]],
    }),
    "B listing A's support tickets",
  );
});

test('customer A sees only published reviews or its own pending review', async () => {
  ok(await read(`reviews/${ids.reviewPublished}`, ids.a.token), 'published review');
  denied(await read(`reviews/${ids.reviewPendingB}`, ids.a.token), "B's pending review");
  ok(await read(`reviews/${ids.reviewPendingB}`, ids.b.token), 'own pending review');
});

// =====================================================================================
// Role escalation
// =====================================================================================

test('profile self-update cannot escalate role, approval or block state', async () => {
  // Reuse the stored document verbatim; only createdAt is immutable and a fresh timestamp would
  // make every write fail for the wrong reason (an allow-list diff, not the field under test).
  const stored = await ownerFields(`users/${ids.a.uid}`);
  const update = (fields) =>
    call(docPath(`users/${ids.a.uid}`), {
      method: 'PATCH',
      token: ids.a.token,
      body: {
        fields: { ...stored, ...fields },
      },
    });

  denied(await update({ role: S('admin') }), 'role escalation');
  denied(await update({ role: S('staff') }), 'staff escalation');
  denied(await update({ wholesaleStatus: S('approved') }), 'self approval');
  denied(await update({ isBlocked: B(true) }), 'self block-state change');
  denied(await update({ unknownField: S('x') }), 'extra field');
  denied(await update({ notifyEmail: S('yes') }), 'notifyEmail wrong type');
  denied(await update({ displayName: I(42) }), 'displayName wrong type');

  const wishlist = Array.from({ length: 501 }, (_, i) => S(`p${i}`));
  denied(await update({ wishlistProductIds: A(...wishlist) }), 'wishlist over cap');
});

test('profile self-update allows the personal fields the app writes', async () => {
  const stored = await ownerFields(`users/${ids.a.uid}`);
  const res = await call(docPath(`users/${ids.a.uid}`), {
    method: 'PATCH',
    token: ids.a.token,
    body: {
      fields: {
        ...stored,
        displayName: S('Buyer A updated'),
        phone: S('9999999999'),
        notifyEmail: B(false),
        wishlistProductIds: A(S(ids.productPublic)),
        updatedAt: T(),
      },
    },
  });
  ok(res, 'personal profile update');
  ok(await read(`users/${ids.a.uid}`, ids.a.token), 'read after update');
});

test('blocked and profile-less accounts cannot perform user writes', async () => {
  const blockedUpdate = await call(docPath(`users/${ids.blocked.uid}`), {
    method: 'PATCH',
    token: ids.blocked.token,
    body: { fields: profile(ids.blocked.uid, ids.blocked.email, { blocked: true }) },
  });
  denied(blockedUpdate, 'blocked profile update');

  const unblock = await call(docPath(`users/${ids.blocked.uid}`), {
    method: 'PATCH',
    token: ids.blocked.token,
    body: {
      fields: {
        ...profile(ids.blocked.uid, ids.blocked.email, { blocked: true }),
        isBlocked: B(false),
      },
    },
  });
  denied(unblock, 'blocked account self-unblock');

  const noProfileCreate = await write(`addresses/${fresh('addr_noprofile')}`, {
    uid: S(ids.noProfile.uid),
    name: S('No Profile'),
    phone: S('1'),
    line1: S('x'),
    city: S('x'),
    state: S('x'),
    pincode: S('x'),
    isDefaultShipping: B(false),
    isDefaultBilling: B(false),
    isWorkAddress: B(false),
    createdAt: T(),
    updatedAt: T(),
  }, ids.noProfile.token);
  denied(noProfileCreate, 'profile-less address create');

  denied(
    await write(`support_requests/${fresh('ticket_noprofile')}`, {
      uid: S(ids.noProfile.uid),
      subject: S('x'),
      orderId: S(''),
      productId: S(''),
      topic: S('other'),
      status: S('open'),
      messages: A(),
      createdAt: T(),
      updatedAt: T(),
    }, ids.noProfile.token),
    'profile-less support create',
  );
});

// =====================================================================================
// Address book
// =====================================================================================

const addressFields = (uid, overrides = {}) => ({
  uid: S(uid),
  name: S('Buyer A'),
  phone: S('9876543210'),
  line1: S('3 Test Street'),
  line2: S(''),
  city: S('Pune'),
  state: S('MH'),
  pincode: S('411002'),
  gstNumber: S(''),
  isDefaultShipping: B(false),
  isDefaultBilling: B(false),
  isWorkAddress: B(false),
  createdAt: T(),
  updatedAt: T(),
  ...overrides,
});

test('address create: own valid data works; forged uid, extra fields and wrong types are denied', async () => {
  ok(await write(`addresses/${fresh('addr_create')}`, addressFields(ids.a.uid), ids.a.token), 'valid create');
  denied(
    await write(`addresses/${fresh('addr_forged')}`, addressFields(ids.b.uid), ids.a.token),
    'create for another uid',
  );
  denied(
    await write(`addresses/${fresh('addr_extra')}`, addressFields(ids.a.uid, { adminNote: S('x') }), ids.a.token),
    'create with extra field',
  );
  denied(
    await write(`addresses/${fresh('addr_type')}`, addressFields(ids.a.uid, { isDefaultShipping: S('yes') }), ids.a.token),
    'create with non-boolean flag',
  );
  denied(
    await write(`addresses/${fresh('addr_long')}`, addressFields(ids.a.uid, { line1: S('x'.repeat(301)) }), ids.a.token),
    'create with over-length field',
  );
});

test('address update: owner can edit, cannot change uid, add fields or edit another book', async () => {
  ok(
    await writeMasked(`addresses/${ids.addressA}`, { city: S('Mumbai') }, ['city'], ids.a.token),
    'own address update',
  );
  denied(
    await write(`addresses/${ids.addressA}`, addressFields(ids.b.uid), ids.a.token),
    'uid swap',
  );
  denied(
    await write(`addresses/${ids.addressA}`, addressFields(ids.a.uid, { secret: S('x') }), ids.a.token),
    'extra field',
  );
  denied(
    await writeMasked(`addresses/${ids.addressB}`, { city: S('Delhi') }, ['city'], ids.a.token),
    "B's address",
  );
});

test('address delete: owner works, other users are denied', async () => {
  const own = fresh('addr_delete');
  ok(await write(`addresses/${own}`, addressFields(ids.a.uid), ids.a.token), 'create for delete');
  ok(await remove(`addresses/${own}`, ids.a.token), 'delete own');
  denied(await remove(`addresses/${ids.addressB}`, ids.a.token), "delete B's address");
});

// =====================================================================================
// Wholesale applications
// =====================================================================================

const wholesaleFields = (uid, overrides = {}) => ({
  uid: S(uid),
  companyName: S('A Traders'),
  contactName: S('Buyer A'),
  phone: S('9876543210'),
  email: S(ids.a.email),
  gstNumber: S(''),
  address: S(''),
  city: S(''),
  state: S(''),
  pincode: S(''),
  reason: S(''),
  expectedMonthlyVolume: S(''),
  status: S('pending'),
  createdAt: T(),
  ...overrides,
});

test('wholesale create: exact allow-list accepted; updatedAt, approval and extra fields denied', async () => {
  ok(
    await write(`wholesale_applications/${fresh('wholesale_ok')}`, wholesaleFields(ids.a.uid), ids.a.token),
    'valid application',
  );
  denied(
    await write(
      `wholesale_applications/${fresh('wholesale_updated')}`,
      wholesaleFields(ids.a.uid, { updatedAt: T() }),
      ids.a.token,
    ),
    'application with updatedAt',
  );
  denied(
    await write(
      `wholesale_applications/${fresh('wholesale_approved')}`,
      wholesaleFields(ids.a.uid, { status: S('approved') }),
      ids.a.token,
    ),
    'self-approved application',
  );
  denied(
    await write(
      `wholesale_applications/${fresh('wholesale_extra')}`,
      wholesaleFields(ids.a.uid, { adminNote: S('x') }),
      ids.a.token,
    ),
    'extra field',
  );
  denied(
    await write(`wholesale_applications/${fresh('wholesale_forged')}`, wholesaleFields(ids.b.uid), ids.a.token),
    'forged uid',
  );
  denied(
    await write(
      `wholesale_applications/${fresh('wholesale_type')}`,
      wholesaleFields(ids.a.uid, { createdAt: S('now') }),
      ids.a.token,
    ),
    'createdAt wrong type',
  );
});

test('wholesale applications are staff-readable and never client-updatable', async () => {
  ok(await read(`wholesale_applications/${ids.wholesaleAppA}`, ids.staff.token), 'staff read');
  denied(
    await writeMasked(
      `wholesale_applications/${ids.wholesaleAppA}`,
      { status: S('approved') },
      ['status'],
      ids.a.token,
    ),
    'self decision',
  );
  denied(await remove(`wholesale_applications/${ids.wholesaleAppA}`, ids.a.token), 'client delete');
});

// =====================================================================================
// Support requests
// =====================================================================================

const ticketFields = (uid, overrides = {}) => ({
  uid: S(uid),
  subject: S('Support subject'),
  orderId: S(''),
  productId: S(''),
  topic: S('other'),
  status: S('open'),
  messages: A(msg(uid, 'First message')),
  createdAt: T(),
  updatedAt: T(),
  ...overrides,
});

async function newTicket(uid, messages, overrides = {}) {
  const id = fresh('ticket');
  const res = await write(
    `support_requests/${id}`,
    ticketFields(uid, { messages: A(...messages), ...overrides }),
    ids.a.token,
  );
  ok(res, 'seed ticket through the public create path');
  return id;
}

test('support create: the app shape works; forged turns and extra fields are denied', async () => {
  const id = fresh('ticket_create');
  ok(await write(`support_requests/${id}`, ticketFields(ids.a.uid), ids.a.token), 'valid create');
  denied(
    await write(
      `support_requests/${fresh('ticket_staffmsg')}`,
      ticketFields(ids.a.uid, { messages: A(msg(ids.a.uid, 'fake staff', true)) }),
      ids.a.token,
    ),
    'staff turn from client',
  );
  denied(
    await write(
      `support_requests/${fresh('ticket_forgedmsg')}`,
      ticketFields(ids.a.uid, { messages: A(msg(ids.b.uid, 'forged')) }),
      ids.a.token,
    ),
    'message from another uid',
  );
  denied(
    await write(
      `support_requests/${fresh('ticket_status')}`,
      ticketFields(ids.a.uid, { status: S('resolved') }),
      ids.a.token,
    ),
    'create already resolved',
  );
  denied(
    await write(
      `support_requests/${fresh('ticket_extra')}`,
      ticketFields(ids.a.uid, { internalNote: S('x') }),
      ids.a.token,
    ),
    'extra field',
  );
  denied(
    await write(
      `support_requests/${fresh('ticket_many')}`,
      ticketFields(ids.a.uid, { messages: A(msg(ids.a.uid, 'one'), msg(ids.a.uid, 'two')) }),
      ids.a.token,
    ),
    'two messages at create',
  );
  denied(
    await write(
      `support_requests/${fresh('ticket_badtype')}`,
      ticketFields(ids.a.uid, { messages: A(M({ from: S(ids.a.uid), body: S('x'), at: S('not-a-time'), isStaff: B(false) })) }),
      ids.a.token,
    ),
    'message with string timestamp',
  );
});

test('support reply: one correctly-shaped append works', async () => {
  const id = await newTicket(ids.a.uid, [msg(ids.a.uid, 'First')]);
  const appended = [msg(ids.a.uid, 'First'), msg(ids.a.uid, 'Second')];
  ok(
    await writeMasked(
      `support_requests/${id}`,
      { messages: A(...appended), status: S('open'), updatedAt: T() },
      ['messages', 'status', 'updatedAt'],
      ids.a.token,
    ),
    'append one message',
  );
});

test('support reply: same-size rewrite, two-message growth and forged elements are denied', async () => {
  const id = await newTicket(ids.a.uid, [msg(ids.a.uid, 'First')]);
  denied(
    await writeMasked(
      `support_requests/${id}`,
      { messages: A(msg(ids.a.uid, 'Edited first')) },
      ['messages'],
      ids.a.token,
    ),
    'same-size rewrite',
  );
  denied(
    await writeMasked(
      `support_requests/${id}`,
      {
        messages: A(msg(ids.a.uid, 'First'), msg(ids.a.uid, 'Second'), msg(ids.a.uid, 'Third')),
      },
      ['messages'],
      ids.a.token,
    ),
    'two-message append',
  );
  denied(
    await writeMasked(
      `support_requests/${id}`,
      { messages: A(msg(ids.a.uid, 'First'), msg(ids.b.uid, 'Not me')) },
      ['messages'],
      ids.a.token,
    ),
    'appended element from another uid',
  );
  denied(
    await writeMasked(
      `support_requests/${id}`,
      { messages: A(msg(ids.a.uid, 'First'), msg(ids.a.uid, 'Fake staff', true)) },
      ['messages'],
      ids.a.token,
    ),
    'appended staff turn',
  );
  denied(
    await writeMasked(
      `support_requests/${id}`,
      {
        messages: A(
          msg(ids.a.uid, 'First'),
          M({ from: S(ids.a.uid), body: S('x'), at: T(), isStaff: B(false), admin: B(true) }),
        ),
      },
      ['messages'],
      ids.a.token,
    ),
    'appended element with extra key',
  );
});

test('support status: customer may reopen, cannot claim staff states', async () => {
  const awaiting = await newTicket(ids.a.uid, [msg(ids.a.uid, 'First')]);
  ok(
    await writeMasked(
      `support_requests/${awaiting}`,
      { status: S('awaitingCustomer'), updatedAt: T() },
      ['status', 'updatedAt'],
      ids.a.token,
    ),
    'awaitingCustomer',
  );
  const inProgress = await newTicket(ids.a.uid, [msg(ids.a.uid, 'First')]);
  denied(
    await writeMasked(
      `support_requests/${inProgress}`,
      { status: S('inProgress'), updatedAt: T() },
      ['status', 'updatedAt'],
      ids.a.token,
    ),
    'inProgress',
  );
  const resolved = await newTicket(ids.a.uid, [msg(ids.a.uid, 'First')]);
  denied(
    await writeMasked(
      `support_requests/${resolved}`,
      { status: S('resolved'), updatedAt: T() },
      ['status', 'updatedAt'],
      ids.a.token,
    ),
    'resolved',
  );
  denied(
    await writeMasked(
      `support_requests/${resolved}`,
      { status: S('open'), resolvedAt: T() },
      ['status', 'resolvedAt'],
      ids.a.token,
    ),
    'adding resolvedAt',
  );
});

test('support: staff can read the thread but cannot write it through the client', async () => {
  ok(await read(`support_requests/${ids.ticketA}`, ids.staff.token), 'staff read');
  denied(
    await writeMasked(
      `support_requests/${ids.ticketA}`,
      { status: S('resolved'), updatedAt: T() },
      ['status', 'updatedAt'],
      ids.staff.token,
    ),
    'staff direct write',
  );
  denied(await remove(`support_requests/${ids.ticketA}`, ids.a.token), 'customer delete');
});

test('LIMITATION: an append that also edits an older turn is accepted by rules', async () => {
  // Firestore Rules cannot iterate a list. The rule proves the *appended* element is the caller's
  // own turn, but it cannot compare elements 0..n-1 against the stored list. Rejecting all growth
  // would break replies; accepting growth means an attacker can submit a modified old turn in the
  // same write. Documented residual; the mitigation is the server-side append callable described
  // in the report, not a stronger rule here.
  const id = await newTicket(ids.a.uid, [msg(ids.a.uid, 'Original first')]);
  const res = await writeMasked(
    `support_requests/${id}`,
    {
      messages: A(msg(ids.a.uid, 'Tampered first'), msg(ids.a.uid, 'Legitimate append')),
      status: S('open'),
      updatedAt: T(),
    },
    ['messages', 'status', 'updatedAt'],
    ids.a.token,
  );
  ok(res, 'append plus rewrite of an older turn (known limitation)');
});

// =====================================================================================
// Notifications
// =====================================================================================

test('notifications: owner acks, cannot change payload or touch another owner', async () => {
  ok(
    await writeMasked(`notifications/${ids.notificationA}`, { isRead: B(true) }, ['isRead'], ids.a.token),
    'ack own',
  );
  denied(
    await writeMasked(`notifications/${ids.notificationA}`, { title: S('Changed') }, ['title'], ids.a.token),
    'edit title',
  );
  denied(
    await writeMasked(`notifications/${ids.notificationB}`, { isRead: B(true) }, ['isRead'], ids.a.token),
    "ack B's",
  );
  denied(
    await writeMasked(`notifications/${ids.notificationA}`, { isRead: S('yes') }, ['isRead'], ids.a.token),
    'isRead wrong type',
  );
  denied(await write(`notifications/${fresh('notif_forged')}`, {
    uid: S(ids.a.uid),
    title: S('x'),
    body: S('x'),
    isRead: B(false),
    createdAt: T(),
  }, ids.a.token), 'client-created notification');
});

// =====================================================================================
// Server-owned collections and money/stock
// =====================================================================================

test('orders, payments and coupon redemptions reject every client write', async () => {
  denied(
    await writeMasked(`orders/${ids.orderA}`, { status: S('cancelled') }, ['status'], ids.a.token),
    'customer cancel',
  );
  denied(
    await writeMasked(`orders/${ids.orderA}`, { status: S('cancelled') }, ['status'], ids.staff.token),
    'staff status write',
  );
  denied(
    await writeMasked(`orders/${ids.orderA}`, { totalPaise: I(1) }, ['totalPaise'], ids.a.token),
    'total rewrite',
  );
  denied(await remove(`orders/${ids.orderA}`, ids.admin.token), 'admin delete');
  denied(await write(`payments/${fresh('pay_forged')}`, { uid: S(ids.a.uid), status: S('captured') }, ids.a.token), 'payment create');
  denied(await write(`coupon_redemptions/${fresh('redemption_forged')}`, { couponId: S(ids.coupon) }, ids.a.token), 'redemption create');
});

test('catalogue, stock, settings and review internals are function-only', async () => {
  denied(await writeMasked(`products/${ids.productPublic}`, { stockQty: I(999) }, ['stockQty'], ids.admin.token), 'admin stock write');
  denied(await writeMasked(`product_variants/${ids.variant}`, { costPricePaise: I(1) }, ['costPricePaise'], ids.admin.token), 'admin cost write');
  denied(await write(`categories/${fresh('cat_forged')}`, { name: S('x'), isActive: B(true) }, ids.admin.token), 'admin category create');
  denied(await writeMasked('store_settings/store', { taxMode: S('exclusive') }, ['taxMode'], ids.admin.token), 'admin settings write');
  denied(await write(`reviews/${fresh('review_forged')}`, { uid: S(ids.a.uid), status: S('published') }, ids.a.token), 'review create');
  denied(await write(`inventory_movements/${fresh('movement_forged')}`, { delta: I(1) }, ids.staff.token), 'inventory write');
  denied(await write(`audit_logs/${fresh('audit_forged')}`, { action: S('x') }, ids.admin.token), 'audit write');
  denied(await write(`media_objects/${fresh('media_forged')}`, { url: S('x') }, ids.admin.token), 'media write');
});

test('staff-only reads: variants, inventory, audit, orders, payments, all users', async () => {
  ok(await read(`product_variants/${ids.variant}`, ids.staff.token), 'staff variant');
  ok(await read(`inventory_movements/${ids.movement}`, ids.staff.token), 'staff movement');
  ok(await read(`inventory_alerts/${ids.alert}`, ids.staff.token), 'staff alert');
  ok(await read(`audit_logs/${ids.audit}`, ids.staff.token), 'staff audit');
  ok(await read(`orders/${ids.orderB}`, ids.staff.token), 'staff order');
  ok(await read(`payments/${ids.paymentB}`, ids.staff.token), 'staff payment');
  ok(await read(`users/${ids.a.uid}`, ids.staff.token), 'staff profile');
  ok(await runQuery('users', { token: ids.staff.token }), 'staff user list');
  ok(await read(`reviews/${ids.reviewPendingB}`, ids.staff.token), "staff pending review");
  ok(await runQuery('products', { token: ids.staff.token }), 'staff product list including drafts');
  ok(await read(`products/${ids.productDraft}`, ids.staff.token), 'staff draft');
});

test('non-staff cannot read variants, inventory, audit or coupons', async () => {
  denied(await read(`product_variants/${ids.variant}`, ids.a.token), 'customer variant');
  denied(await read(`inventory_movements/${ids.movement}`, ids.a.token), 'customer movement');
  denied(await read(`audit_logs/${ids.audit}`, ids.a.token), 'customer audit');
  denied(await read(`coupons/${ids.coupon}`, ids.a.token), 'customer coupon');
  denied(await read(`coupons/${ids.coupon}`, ids.staff.token), 'staff coupon (pricing admin only)');
  ok(await read(`coupons/${ids.coupon}`, ids.admin.token), 'admin coupon');
});

test('internal collections are invisible to every client, including admins', async () => {
  for (const [label, path] of [
    ['price override', `customer_price_overrides/${ids.override}`],
    ['counter', `counters/${ids.counter}`],
    ['idempotency key', `idempotency_keys/${ids.idempotency}`],
    ['redemption', `coupon_redemptions/${ids.redemption}`],
    ['unknown collection', `probe_unknown_${runId}/${ids.unknown}`],
  ]) {
    denied(await read(path, ids.admin.token), `${label} read`);
    denied(await write(path, { x: S('y') }, ids.admin.token), `${label} write`);
  }
});

// =====================================================================================
// Wholesale entitlement and catalogue query shapes used by the app
// =====================================================================================

test('wholesale buyer: active wholesale-only and retail products are readable, drafts are not', async () => {
  ok(await read(`products/${ids.productWholesale}`, ids.wholesale.token), 'wholesale-only product');
  ok(await read(`products/${ids.productPublic}`, ids.wholesale.token), 'retail product');
  denied(await read(`products/${ids.productDraft}`, ids.wholesale.token), 'draft product');
  denied(await read(`products/${ids.productArchived}`, ids.wholesale.token), 'archived product');
});

test('catalogue list: wholesale buyer needs only the status constraint', async () => {
  ok(
    await runQuery('products', {
      token: ids.wholesale.token,
      filters: [['status', 'EQUAL', S('active')]],
    }),
    'wholesale active list',
  );
  denied(
    await runQuery('products', {
      token: ids.a.token,
      filters: [
        ['status', 'EQUAL', S('active')],
        ['isWholesaleOnly', 'EQUAL', B(true)],
      ],
    }),
    'retail query for wholesale-only rows',
  );
});

test('app query shapes: retail bySlug/byIds must carry the wholesale-only constraint', async () => {
  // These are the exact shapes FirestoreProductRepository issues. The old bySlug shape (slug +
  // status only) and byIds shape (ids only) cannot satisfy the retail branch, so the repository
  // must add isWholesaleOnly == false for non-entitled callers. This test pins the contract.
  ok(
    await runQuery('products', {
      token: ids.a.token,
      filters: [
        ['slug', 'EQUAL', S(ids.productPublic)],
        ['status', 'EQUAL', S('active')],
        ['isWholesaleOnly', 'EQUAL', B(false)],
      ],
    }),
    'retail bySlug',
  );
  ok(
    await runQuery('products', {
      token: ids.wholesale.token,
      filters: [
        ['slug', 'EQUAL', S(ids.productWholesale)],
        ['status', 'EQUAL', S('active')],
      ],
    }),
    'wholesale bySlug',
  );
  ok(
    await runQuery('products', {
      token: ids.a.token,
      filters: [
        ['status', 'EQUAL', S('active')],
        ['isWholesaleOnly', 'EQUAL', B(false)],
      ],
      orderBy: [{ field: { fieldPath: 'soldCount' }, direction: 'DESCENDING' }],
    }),
    'retail cart/wishlist bulk read shape',
  );
});

test('home shelf: retail flagged shelves must carry the wholesale constraint', async () => {
  // FirestoreProductRepository._flagged builds status + flag + orderBy. Without the retail
  // `isWholesaleOnly == false` clause the query could match a wholesale-only row, so the whole
  // shelf read is denied. Staff/wholesale buyers are entitled and need no extra clause.
  const shelf = (token, { withWholesale }) => {
    const filters = [
      ['status', 'EQUAL', S('active')],
      ['isFeatured', 'EQUAL', B(true)],
    ];
    if (withWholesale) filters.push(['isWholesaleOnly', 'EQUAL', B(false)]);
    return runQuery('products', {
      token,
      filters,
      orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
    });
  };
  ok(await shelf(ids.a.token, { withWholesale: true }), 'retail home shelf');
  ok(await shelf(undefined, { withWholesale: true }), 'anonymous home shelf');
  denied(await shelf(ids.a.token, { withWholesale: false }), 'retail home shelf without constraint');
  denied(await shelf(undefined, { withWholesale: false }), 'anonymous home shelf without constraint');
  ok(await shelf(ids.wholesale.token, { withWholesale: false }), 'wholesale home shelf');
  ok(await shelf(ids.staff.token, { withWholesale: false }), 'staff home shelf');
});

test('category bySlug: shoppers must constrain isActive; staff may look up any slug', async () => {
  // FirestoreCategoryRepository.bySlug adds isActive == true for non-staff callers; admins rely on
  // the unconstrained lookup to reject a duplicate slug on an inactive category.
  const bySlug = (slug, token, { withActive }) => {
    const filters = [['slug', 'EQUAL', S(slug)]];
    if (withActive) filters.push(['isActive', 'EQUAL', B(true)]);
    return runQuery('categories', { token, filters, limit: 1 });
  };
  ok(await bySlug('active-cat', undefined, { withActive: true }), 'anonymous active category slug');
  ok(await bySlug('active-cat', ids.a.token, { withActive: true }), 'customer active category slug');
  denied(await bySlug('active-cat', ids.a.token, { withActive: false }), 'customer slug lookup without isActive');
  denied(await bySlug('inactive-cat', undefined, { withActive: false }), 'anonymous inactive slug lookup');
  ok(await bySlug('inactive-cat', ids.admin.token, { withActive: false }), 'admin inactive slug uniqueness check');
  ok(await read(`categories/${ids.categoryActive}`), 'anonymous active category doc');
  denied(await read(`categories/${ids.categoryInactive}`), 'anonymous inactive category doc');
});

test('guest order lookup: an unconstrained orderNumber query is denied for customers', async () => {
  // FirestoreOrderRepository.byOrderNumber filters only on orderNumber. The orders rule scopes
  // reads to the owner (or staff) and cannot be satisfied by that filter, so the query is denied.
  // No `guestOrderLookup` callable exists yet, so this is a documented gap, not a passing flow.
  denied(
    await runQuery('orders', { token: ids.a.token, filters: [['orderNumber', 'EQUAL', S('OM-TEST-2')]] }),
    'customer orderNumber lookup',
  );
  denied(
    await runQuery('orders', { filters: [['orderNumber', 'EQUAL', S('OM-TEST-1')]] }),
    'anonymous orderNumber lookup',
  );
  ok(
    await runQuery('orders', { token: ids.staff.token, filters: [['orderNumber', 'EQUAL', S('OM-TEST-1')]] }),
    'staff orderNumber lookup',
  );
});

test('order and account list shapes used by the app pass', async () => {
  ok(
    await runQuery('orders', {
      token: ids.a.token,
      filters: [['userId', 'EQUAL', S(ids.a.uid)]],
      orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
    }),
    'myOrders',
  );
  ok(
    await runQuery('addresses', {
      token: ids.a.token,
      filters: [['uid', 'EQUAL', S(ids.a.uid)]],
    }),
    'address book',
  );
  ok(
    await runQuery('support_requests', {
      token: ids.a.token,
      filters: [['uid', 'EQUAL', S(ids.a.uid)]],
      orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
    }),
    'my support tickets',
  );
  ok(
    await runQuery('notifications', {
      token: ids.a.token,
      filters: [['uid', 'EQUAL', S(ids.a.uid)], ['isRead', 'EQUAL', B(false)]],
      limit: 30,
    }),
    'unread notifications',
  );
});

test('blocked account loses private reads and public writes', async () => {
  denied(await read(`addresses/${ids.addressA}`, ids.blocked.token), 'blocked address read');
  denied(await read(`orders/${ids.orderB}`, ids.blocked.token), 'blocked order read');
  denied(await read(`notifications/${ids.notificationB}`, ids.blocked.token), 'blocked notification');
  denied(
    await write(`support_requests/${fresh('ticket_blocked')}`, {
      uid: S(ids.blocked.uid),
      subject: S('x'),
      orderId: S(''),
      productId: S(''),
      topic: S('other'),
      status: S('open'),
      messages: A(),
      createdAt: T(),
      updatedAt: T(),
    }, ids.blocked.token),
    'blocked support create',
  );
  // The catalogue is public, so a blocked session still reads it. Rules never hide public data.
  ok(await read(`products/${ids.productPublic}`, ids.blocked.token), 'blocked public catalogue read');
});
