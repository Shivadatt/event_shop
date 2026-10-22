'use strict';

// Real-emulator regression coverage for the P0-3 transaction defects and the Phase 2B order
// integrity fixes.
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

const { allocateOrderNumber, annualCounterId } = require('../../lib/order_number');

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
const COUNTER_PATH = `counters/order-${YEAR}`;

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

async function counterValue() {
  const snap = await db.doc(COUNTER_PATH).get();
  return snap.exists ? Number(snap.data().value || 0) : 0;
}

function seedProduct({ id, stockQty = 5, retailPricePaise = 10000, lowStockThreshold = 1 }) {
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
    lowStockThreshold,
    status: 'active',
    isWholesaleOnly: false,
    soldCount: 0,
    ratingAvg: 0,
    ratingCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function seedVariant({ id, productId, stockQty = 5, retailPricePaise = 9000 }) {
  return db.collection('product_variants').doc(id).set({
    id,
    productId,
    name: `Integration Variant ${id}`,
    sku: `IT-V-${id}`,
    retailPricePaise,
    salePricePaise: 0,
    slabs: [],
    images: [],
    stockQty,
    lowStockThreshold: 1,
    isActive: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function orderPayload({
  productId,
  variantId,
  qty = 1,
  tag,
  couponCode = '',
  contactEmail = `guest.${RUN}.${tag}@example.test`,
  lines,
}) {
  const payloadLines = lines || [{ productId, ...(variantId ? { variantId } : {}), qty }];
  return {
    lines: payloadLines,
    idempotencyKey: `itest-${RUN}-${tag}`,
    clientTotalPaise: 0,
    deliveryMode: 'pickup',
    paymentMethod: 'cod',
    contactEmail,
    contactPhone: '9000000000',
    couponCode,
  };
}

test('the first yearly number continues past the legacy monthly counter', async () => {
  const productId = `itest_prod_legacy_${RUN}`;
  await seedProduct({ id: productId, stockQty: 20 });
  // Simulate the pre-fix state: only monthly counters exist, and January reached sequence 4.
  await db.doc(COUNTER_PATH).delete();
  await db.doc(`counters/order-${YEAR}-01`).set({
    value: 4,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const receipt = await call('ordersCreate', orderPayload({ productId, tag: 'legacy-seed' }));
  const seq = Number(receipt.orderNumber.split('-').pop());

  assert.ok(seq >= 5, `the yearly counter must not restart at 1 (got ${receipt.orderNumber})`);
  assert.equal(await counterValue(), seq, 'the yearly counter must be written inside the order transaction');
});

test('yearly order counter is persisted and every order gets a distinct number', async () => {
  const productId = `itest_prod_counter_${RUN}`;
  await seedProduct({ id: productId, stockQty: 20 });

  const startSeq = await counterValue();

  const first = await call('ordersCreate', orderPayload({ productId, tag: 'counter-a' }));
  const second = await call('ordersCreate', orderPayload({ productId, tag: 'counter-b' }));

  assert.match(first.orderNumber, /^OME-\d{4}-\d{6}$/);
  assert.match(second.orderNumber, /^OME-\d{4}-\d{6}$/);
  assert.notEqual(first.orderNumber, second.orderNumber, 'two orders must never share an order number');

  const after = await counterValue();
  assert.equal(after, startSeq + 2);
  assert.equal(Number(second.orderNumber.split('-').pop()), after);
});

test('concurrent orders serialize on the yearly counter instead of minting the same number', async () => {
  const productIds = [`itest_prod_conc_a_${RUN}`, `itest_prod_conc_b_${RUN}`, `itest_prod_conc_c_${RUN}`];
  await Promise.all(productIds.map((id) => seedProduct({ id, stockQty: 10 })));

  const startSeq = await counterValue();

  const receipts = await Promise.all(
    productIds.map((productId, index) => call('ordersCreate', orderPayload({ productId, tag: `concurrent-${index}` }))),
  );
  const numbers = receipts.map((receipt) => receipt.orderNumber);
  assert.equal(new Set(numbers).size, numbers.length, 'concurrent orders must not share an order number');

  const after = await counterValue();
  assert.equal(after, startSeq + numbers.length);
  const minted = numbers.map((number) => Number(number.split('-').pop())).sort((a, b) => a - b);
  assert.deepEqual(minted, Array.from({ length: numbers.length }, (_, i) => startSeq + i + 1));
});

test('the yearly number allocator does not reset at a month boundary', async () => {
  const october = new Date(YEAR, 9, 31, 23, 30);
  const november = new Date(YEAR, 10, 1, 0, 30);
  assert.equal(annualCounterId(october), annualCounterId(november), 'both months use the same yearly counter');

  const allocateAndPersist = (now) => db.runTransaction(async (tx) => {
    const allocation = await allocateOrderNumber({ tx, db, prefix: 'OME', now });
    tx.set(allocation.counterRef, { value: allocation.seq }, { merge: true });
    return allocation;
  });

  const first = await allocateAndPersist(october);
  const second = await allocateAndPersist(november);

  assert.match(first.number, new RegExp(`^OME-${YEAR}-\\d{6}$`));
  assert.notEqual(first.number, second.number, 'a month boundary must not restart the visible sequence');
  assert.equal(second.seq, first.seq + 1);
  assert.equal(await counterValue(), second.seq);
});

test('a visible number that already exists is never minted again', async () => {
  const productId = `itest_prod_skip_${RUN}`;
  await seedProduct({ id: productId, stockQty: 10 });

  const nextSeq = (await counterValue()) + 1;
  const blockedNumber = `OME-${YEAR}-${String(nextSeq).padStart(6, '0')}`;
  await db.collection('orders').doc(`itest_blocked_${RUN}`).set({
    orderNumber: blockedNumber,
    userId: '',
    isGuest: true,
    status: 'placed',
    items: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const receipt = await call('ordersCreate', orderPayload({ productId, tag: 'skip-used' }));
  const mintedSeq = Number(receipt.orderNumber.split('-').pop());
  assert.ok(mintedSeq > nextSeq, `the existing ${blockedNumber} must be skipped`);
  assert.equal(await counterValue(), mintedSeq);
});

test('duplicate product lines exceeding stock are rejected with no reservation', async () => {
  const productId = `itest_prod_dup_over_${RUN}`;
  await seedProduct({ id: productId, stockQty: 5 });
  const startSeq = await counterValue();

  await assert.rejects(
    () => call('ordersCreate', orderPayload({
      lines: [{ productId, qty: 3 }, { productId, qty: 3 }],
      tag: 'dup-over',
    })),
    (error) => error.code === 'FAILED_PRECONDITION'
      && error.details
      && error.details.code === 'OUT_OF_STOCK'
      && Number(error.details.available) === 5
      && Number(error.details.requested) === 6,
  );

  assert.equal((await db.doc(`products/${productId}`).get()).data().stockQty, 5, 'stock must be unchanged');
  assert.equal(await counterValue(), startSeq, 'a rejected order must not move the counter');
  assert.equal((await db.doc(`idempotency_keys/itest-${RUN}-dup-over`).get()).exists, false);
});

test('duplicate product lines within stock reserve the combined quantity once', async () => {
  const productId = `itest_prod_dup_ok_${RUN}`;
  await seedProduct({ id: productId, stockQty: 10, lowStockThreshold: 8 });

  const receipt = await call('ordersCreate', orderPayload({
    lines: [{ productId, qty: 3 }, { productId, qty: 3 }],
    tag: 'dup-ok',
  }));

  const product = await db.doc(`products/${productId}`).get();
  assert.equal(product.data().stockQty, 4, 'the combined six units must be reserved once');
  assert.equal(product.data().soldCount, 6);

  const order = await db.doc(`orders/${receipt.orderId}`).get();
  assert.deepEqual(order.data().items.map((item) => item.qty), [3, 3], 'per-line items must be preserved');

  const movements = await db.collection('inventory_movements').where('orderId', '==', receipt.orderId).get();
  const sales = movements.docs.map((doc) => doc.data()).filter((move) => move.kind === 'saleOut');
  assert.equal(sales.length, 2);
  assert.deepEqual(sales.map((move) => Number(move.quantity)).sort((a, b) => a - b), [3, 3]);
  assert.deepEqual(sales.map((move) => Number(move.balanceAfter)).sort((a, b) => a - b), [4, 7]);

  const alert = await db.doc(`inventory_alerts/${productId}_base`).get();
  assert.equal(alert.exists, true);
  assert.equal(alert.data().balanceAfter, 4, 'the alert must use the post-reservation balance, not a stale one');
});

test('duplicate lines reaching one variant stock document are aggregated', async () => {
  const productA = `itest_prod_var_a_${RUN}`;
  const productB = `itest_prod_var_b_${RUN}`;
  const variantId = `itest_variant_dup_${RUN}`;
  await seedProduct({ id: productA, stockQty: 50 });
  await seedProduct({ id: productB, stockQty: 50 });
  await seedVariant({ id: variantId, productId: productA, stockQty: 5 });
  const startSeq = await counterValue();

  await assert.rejects(
    () => call('ordersCreate', orderPayload({
      lines: [
        { productId: productA, variantId, qty: 4 },
        { productId: productB, variantId, qty: 4 },
      ],
      tag: 'dup-variant',
    })),
    (error) => error.code === 'FAILED_PRECONDITION'
      && error.details
      && error.details.code === 'OUT_OF_STOCK'
      && Number(error.details.available) === 5
      && Number(error.details.requested) === 8,
  );

  assert.equal((await db.doc(`product_variants/${variantId}`).get()).data().stockQty, 5);
  assert.equal(await counterValue(), startSeq);
});

test('a rejected order leaves the yearly counter and stock untouched', async () => {
  const productId = `itest_prod_reject_${RUN}`;
  await seedProduct({ id: productId, stockQty: 5 });
  const startSeq = await counterValue();

  await assert.rejects(
    () => call('ordersCreate', orderPayload({ productId, qty: 6, tag: 'reject-single' })),
    (error) => error.code === 'FAILED_PRECONDITION',
  );

  assert.equal((await db.doc(`products/${productId}`).get()).data().stockQty, 5);
  assert.equal(await counterValue(), startSeq);
  assert.equal((await db.doc(`idempotency_keys/itest-${RUN}-reject-single`).get()).exists, false);
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
