'use strict';

// Real-emulator regression coverage for the P0-3 transaction defects.
//
// Unlike `functions/test/*.test.js` (which intercept the Admin SDK and therefore cannot model
// Firestore's read-before-write rule), this suite runs the REAL callables inside the Functions
// emulator, against the REAL Firestore emulator, and calls them over the callable HTTP protocol.
// Seeding and assertions use the Admin SDK; the transaction code under test is the deployed handler.
//
// Run from the repository root (dedicated ports, strict rules, fresh Functions code):
//   JAVA_HOME="C:/Users/ASUS/.jdks/corretto-21.0.10" \
//   firebase --config firebase.integration.json emulators:exec \
//     --only auth,firestore,functions --project demo-om-events \
//     "node --test functions/test/integration/transactions.integration.test.js"
// firebase-tools 15.x needs JDK 21+; the host default java is 17.

const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const PROJECT = process.env.OM_INTEGRATION_PROJECT || 'demo-om-events';
const AUTH_EMULATOR_KEY = 'localhost-emulator-not-a-real-key';

function stripScheme(value) {
  return String(value || '').replace(/^https?:\/\//, '').replace(/\/+$/, '');
}

const AUTH_HOST = stripScheme(process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9198');
const FUNCTIONS_HOST = stripScheme(
  process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST || process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5111',
);

admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const auth = admin.auth();

const RUN = `${Date.now()}${Math.random().toString(36).slice(2, 7)}`;
const PASSWORD = 'Integration1!';
const YEAR = new Date().getFullYear();
const MONTH = String(new Date().getMonth() + 1).padStart(2, '0');
const COUNTER_PATH = `counters/order-${YEAR}-${MONTH}`;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function signIn(email) {
  const url = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${AUTH_EMULATOR_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
  });
  const body = await res.json();
  if (!res.ok || !body.idToken) throw new Error(`Sign-in failed for ${email}: ${JSON.stringify(body)}`);
  return body.idToken;
}

async function createUser(role, tag) {
  const email = `itest.${RUN}.${tag}@example.test`;
  const user = await auth.createUser({ email, password: PASSWORD, displayName: `Integration ${tag}` });
  await db.collection('users').doc(user.uid).set({
    uid: user.uid,
    email,
    displayName: `Integration ${tag}`,
    phone: '',
    role,
    wholesaleStatus: role === 'customer' ? 'none' : 'approved',
    isBlocked: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { uid: user.uid, email, idToken: await signIn(email) };
}

async function call(name, data, idToken) {
  const url = `http://${FUNCTIONS_HOST}/${PROJECT}/us-central1/${name}`;
  let lastBody = '';
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}),
      },
      body: JSON.stringify({ data }),
    });
    lastBody = await res.text();
    // The Functions emulator can answer 404 for a moment while it publishes the endpoint.
    if (res.status === 404 && attempt < 39) {
      await sleep(500);
      continue;
    }
    let parsed = null;
    try {
      parsed = lastBody ? JSON.parse(lastBody) : null;
    } catch (_) {
      // fall through to the HTTP error below
    }
    if (parsed && parsed.error) {
      const error = new Error(parsed.error.message || 'Callable failed.');
      error.code = parsed.error.status || 'UNKNOWN';
      error.details = parsed.error.details;
      throw error;
    }
    if (!res.ok) throw new Error(`${name}: HTTP ${res.status} ${lastBody}`);
    return parsed ? parsed.result : null;
  }
  throw new Error(`${name}: endpoint never became available (${lastBody})`);
}

function seedProduct({ id, stockQty = 5, retailPricePaise = 10000 }) {
  return db.collection('products').doc(id).set({
    id,
    name: `Integration Widget ${id}`,
    slug: id,
    sku: `IT-${id}`,
    description: 'Integration test product.',
    categoryId: 'itest',
    categorySlug: 'itest',
    brand: 'IT',
    packSize: '1 pc',
    unit: 'pack',
    retailPricePaise,
    salePricePaise: 0,
    slabs: [],
    variants: [],
    images: [],
    minOrderQty: 1,
    orderMultiple: 1,
    stockQty,
    lowStockThreshold: 1,
    status: 'active',
    isWholesaleOnly: false,
    soldCount: 0,
    ratingAvg: 0,
    ratingCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function orderPayload({ productId, qty = 1, tag, couponCode = '', contactEmail = `guest.${RUN}.${tag}@example.test` }) {
  return {
    lines: [{ productId, qty }],
    idempotencyKey: `itest-${RUN}-${tag}`,
    clientTotalPaise: 0,
    deliveryMode: 'pickup',
    paymentMethod: 'cod',
    contactEmail,
    contactPhone: '9000000000',
    couponCode,
  };
}

test('monthly order counter is persisted and every order gets a distinct number', async () => {
  const productId = `itest_prod_counter_${RUN}`;
  await seedProduct({ id: productId, stockQty: 20 });

  const before = await db.doc(COUNTER_PATH).get();
  const startSeq = before.exists ? Number(before.data().value || 0) : 0;

  const first = await call('ordersCreate', orderPayload({ productId, tag: 'counter-a' }));
  const second = await call('ordersCreate', orderPayload({ productId, tag: 'counter-b' }));

  assert.match(first.orderNumber, /^OME-\d{4}-\d{6}$/);
  assert.match(second.orderNumber, /^OME-\d{4}-\d{6}$/);
  assert.notEqual(first.orderNumber, second.orderNumber, 'two orders must never share an order number');

  const after = await db.doc(COUNTER_PATH).get();
  assert.equal(after.exists, true, 'the monthly counter document must be written inside the order transaction');
  assert.equal(Number(after.data().value), startSeq + 2);
  assert.equal(Number(second.orderNumber.split('-').pop()), startSeq + 2);
});

test('concurrent orders serialize on the monthly counter instead of minting the same number', async () => {
  const productIds = [`itest_prod_conc_a_${RUN}`, `itest_prod_conc_b_${RUN}`, `itest_prod_conc_c_${RUN}`];
  await Promise.all(productIds.map((id) => seedProduct({ id, stockQty: 10 })));

  const before = await db.doc(COUNTER_PATH).get();
  const startSeq = before.exists ? Number(before.data().value || 0) : 0;

  const receipts = await Promise.all(
    productIds.map((productId, index) => call('ordersCreate', orderPayload({ productId, tag: `concurrent-${index}` }))),
  );
  const numbers = receipts.map((receipt) => receipt.orderNumber);
  assert.equal(new Set(numbers).size, numbers.length, 'concurrent orders must not share an order number');

  const after = await db.doc(COUNTER_PATH).get();
  assert.equal(Number(after.data().value), startSeq + numbers.length);
  const minted = numbers.map((number) => Number(number.split('-').pop())).sort((a, b) => a - b);
  assert.deepEqual(minted, Array.from({ length: numbers.length }, (_, i) => startSeq + i + 1));
});

test('coupon redemption commits in one transaction and increments the per-user record', async () => {
  const productId = `itest_prod_coupon_${RUN}`;
  const couponCode = `ITCPN${RUN}`.toUpperCase();
  await seedProduct({ id: productId, stockQty: 10 });
  await db.collection('coupons').doc(couponCode).set({
    id: couponCode,
    code: couponCode,
    kind: 'flat',
    description: 'Integration flat discount',
    valuePaise: 5000,
    percentOff: 0,
    minCartValuePaise: 0,
    minQty: 1,
    perUserLimit: 3,
    usageLimit: 100,
    usedCount: 0,
    isActive: true,
    excludesWholesale: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const contactEmail = `guest.${RUN}.coupon@example.test`;
  const receipt = await call('ordersCreate', orderPayload({ productId, tag: 'coupon', couponCode, contactEmail }));

  assert.equal(receipt.totals.couponDiscountPaise, 5000);
  assert.equal(receipt.totals.grandTotalPaise, 5000);

  const redemption = await db.doc(`coupon_redemptions/${couponCode}__guest:${contactEmail}`).get();
  assert.equal(redemption.exists, true, 'the redemption record must exist after a successful order');
  assert.equal(Number(redemption.data().count), 1);

  const coupon = await db.collection('coupons').doc(couponCode).get();
  assert.equal(Number(coupon.data().usedCount), 1);
});

test('customer cancellation restores stock and closes the transaction cleanly', async () => {
  const productId = `itest_prod_cancel_${RUN}`;
  const buyer = await createUser('customer', 'cancel');
  const productRef = db.collection('products').doc(productId);
  await seedProduct({ id: productId, stockQty: 5 });

  const receipt = await call('ordersCreate', orderPayload({ productId, qty: 2, tag: 'cancel' }), buyer.idToken);
  assert.equal((await productRef.get()).data().stockQty, 3, 'order must reserve two units');

  const orderRef = db.collection('orders').doc(receipt.orderId);
  const beforeCancel = await orderRef.get();
  assert.equal(beforeCancel.data().status, 'placed');
  assert.equal(beforeCancel.data().items[0].isStockDeducted, true);

  await call('orderRequestCancel', { orderId: receipt.orderId, reason: 'integration test' }, buyer.idToken);

  const afterCancel = await orderRef.get();
  assert.equal(afterCancel.data().status, 'cancelled');
  assert.equal(afterCancel.data().items[0].isStockDeducted, false);
  assert.equal((await productRef.get()).data().stockQty, 5, 'cancellation must return the reserved units');

  const movements = await db.collection('inventory_movements').where('orderId', '==', receipt.orderId).get();
  const restores = movements.docs.map((d) => d.data()).filter((m) => m.kind === 'cancelRestore');
  assert.equal(restores.length, 1);
  assert.equal(Number(restores[0].quantity), 2);
  assert.equal(Number(restores[0].balanceAfter), 5);
});

test('wholesale approval updates the application and the user in one transaction', async () => {
  const applicant = await createUser('customer', 'wholesale');
  const adminUser = await createUser('owner', 'admin');
  const appId = `itest_app_${RUN}`;
  await db.collection('wholesale_applications').doc(appId).set({
    uid: applicant.uid,
    businessName: 'Integration Test Traders',
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await call('adminWholesaleDecide', { applicationId: appId, decision: 'approved', note: 'integration' }, adminUser.idToken);

  const app = await db.collection('wholesale_applications').doc(appId).get();
  assert.equal(app.data().status, 'approved');
  const user = await db.collection('users').doc(applicant.uid).get();
  assert.equal(user.data().role, 'wholesale');
});

test('repeated partial refunds cannot exceed the amount actually paid', async () => {
  const buyer = await createUser('customer', 'refund');
  const adminUser = await createUser('owner', 'refund-admin');
  const orderId = `itest_order_refund_${RUN}`;
  const orderRef = db.collection('orders').doc(orderId);
  await orderRef.set({
    orderNumber: `OME-${YEAR}-999999`,
    userId: buyer.uid,
    status: 'delivered',
    paymentStatus: 'paid',
    paymentMethod: 'cod',
    items: [],
    totals: { grandTotalPaise: 10000, paidPaise: 10000, refundedPaise: 0, subtotalPaise: 10000, taxPaise: 0, shippingPaise: 0, couponDiscountPaise: 0, slabDiscountPaise: 0, roundingPaise: 0 },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await call('adminOrderRefund', { orderId, amountPaise: 6000, reason: 'first partial' }, adminUser.idToken);
  let snap = await orderRef.get();
  assert.equal(Number(snap.data().totals.refundedPaise), 6000);
  assert.equal(snap.data().paymentStatus, 'partiallyRefunded');

  await assert.rejects(
    () => call('adminOrderRefund', { orderId, amountPaise: 6000, reason: 'over the cap' }, adminUser.idToken),
    (error) => error.code === 'FAILED_PRECONDITION' && /unrefunded amount/i.test(error.message),
  );
  snap = await orderRef.get();
  assert.equal(Number(snap.data().totals.refundedPaise), 6000, 'the refused refund must not be recorded');
  assert.equal(snap.data().paymentStatus, 'partiallyRefunded');

  await call('adminOrderRefund', { orderId, amountPaise: 4000, reason: 'exact remainder' }, adminUser.idToken);
  snap = await orderRef.get();
  assert.equal(Number(snap.data().totals.refundedPaise), 10000);
  assert.equal(snap.data().paymentStatus, 'refunded');

  await assert.rejects(
    () => call('adminOrderRefund', { orderId, amountPaise: 1, reason: 'nothing left' }, adminUser.idToken),
    (error) => error.code === 'FAILED_PRECONDITION',
  );
});
