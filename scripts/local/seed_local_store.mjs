// Seed the Firebase Local Emulator Suite with a real, browsable OM Events catalogue so the store
// can be run and demoed without a cloud project.
//
//   node scripts/local/seed_local_store.mjs
//
// Requires the emulators from firebase.local.json to already be running:
//   npx firebase-tools@13.35.1 emulators:start --config firebase.local.json \
//       --project demo-om-events --only auth,firestore
//
// It writes through the Firestore emulator's REST endpoint, which accepts plain client traffic when
// no rules file is configured — that is exactly why firebase.local.json omits the `rules` key. The
// production rules in firestore.rules still deny every one of these writes, and nothing here
// touches a real project: the host is loopback and the "credentials" are emulator placeholders.
//
// Images are intentionally left empty. Firestore may only hold media metadata (url/path/alt/order);
// the bytes live in Supabase Storage, and there is no Supabase project behind a local demo, so a
// fabricated CDN url would render as a broken image and hide that fact.

const PROJECT = process.env.OM_DEMO_PROJECT ?? 'demo-om-events';
const FIRESTORE = process.env.OM_FIRESTORE_EMULATOR ?? 'http://127.0.0.1:8080';
const AUTH = process.env.OM_AUTH_EMULATOR ?? 'http://127.0.0.1:9099';
// The Auth emulator ignores the key entirely; this string is a shape requirement of the endpoint,
// not a secret, and it is worded so nobody can mistake it for a real API key.
const AUTH_EMULATOR_KEY = 'localhost-emulator-not-a-real-key';

const now = new Date().toISOString();

/** Firestore REST values are typed; encode plain JS into that shape. */
function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'object') {
    const fields = {};
    for (const [k, val] of Object.entries(v)) fields[k] = toValue(val);
    return { mapValue: { fields } };
  }
  throw new Error(`Cannot encode ${typeof v}`);
}

async function writeDocs(collection, docs) {
  const writes = Object.entries(docs).map(([id, data]) => ({
    currentDocument: {},
    update: {
      name: `projects/${PROJECT}/databases/(default)/documents/${collection}/${id}`,
      fields: Object.fromEntries(
        Object.entries({ ...data, updatedAt: data.updatedAt ?? now }).map(([k, v]) => [k, toValue(v)]),
      ),
    },
  }));
  const url = `${FIRESTORE}/v1/projects/${PROJECT}/databases/(default)/documents:commit`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ writes }),
  });
  if (!res.ok) throw new Error(`${collection}: HTTP ${res.status} ${await res.text()}`);
  return Object.keys(docs).length;
}

async function createAuthUser(email, password) {
  const res = await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${AUTH_EMULATOR_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await res.json();
  if (!res.ok) {
    // EMAIL_EXISTS is the normal path when the seed runs twice. The emulator reports it as HTTP 400
    // with message EMAIL_EXISTS — the numeric code is the HTTP status, not a 40001-style constant.
    if (body?.error?.message !== 'EMAIL_EXISTS') throw new Error(`${email}: ${JSON.stringify(body)}`);
    // `accounts:lookup` on this emulator wants an id token rather than an email list, and the seed
    // already knows the password, so signing in is the shortest way to the real `localId`.
    const again = await fetch(
      `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${AUTH_EMULATOR_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, returnSecureToken: false }),
      },
    );
    const found = await again.json();
    if (!again.ok) throw new Error(`${email}: ${JSON.stringify(found)}`);
    return found.localId;
  }
  return body.localId;
}

// A catalogue a buyer can actually exercise: quantity bands that cross real thresholds, so the slab
// engine, the "N more units for a cheaper price" hint and the server-side total all have something
// to disagree or agree about. Prices are integer paise; there are no rupee decimals anywhere.
const categories = {
  cat_balloons: { id: 'cat_balloons', name: 'Balloons', slug: 'balloons', description: 'Latex, chrome and foil balloons by the pack.', parentId: null, order: 1, images: [], seoTitle: 'Wholesale Balloons', seoDescription: 'Bulk latex, chrome and foil balloons with quantity pricing.', isFeatured: true, isActive: true },
  cat_tableware: { id: 'cat_tableware', name: 'Tableware', slug: 'tableware', description: 'Disposable and decor tableware for events.', parentId: null, order: 2, images: [], seoTitle: 'Wholesale Party Tableware', seoDescription: 'Plates, glasses and cutlery packs for parties and functions.', isFeatured: true, isActive: true },
  cat_decor: { id: 'cat_decor', name: 'Decor & Drapes', slug: 'decor', description: 'Backdrops, drapes and stage decor material.', parentId: null, order: 3, images: [], seoTitle: 'Event Decor Material', seoDescription: 'Backdrop panels, drapes and decor props at wholesale rates.', isFeatured: false, isActive: true },
  cat_lighting: { id: 'cat_lighting', name: 'Lighting', slug: 'lighting', description: 'Fairy lights, battaries and LED props.', parentId: null, order: 4, images: [], seoTitle: 'Party Lighting Wholesale', seoDescription: 'Bulb strings and LED props sold by the carton.', isFeatured: false, isActive: true },
  cat_inactive: { id: 'cat_inactive', name: 'Archived Range', slug: 'archived-range', description: 'Retired range kept to prove inactive rows stay hidden.', parentId: null, order: 9, images: [], isActive: false },
};

function product(o) {
  return {
    id: o.id, name: o.name, slug: o.slug, sku: o.sku, description: o.description,
    categoryId: o.categoryId, categorySlug: o.categorySlug, brand: o.brand,
    packSize: o.packSize, unit: o.unit, retailPricePaise: o.retailPricePaise,
    slabs: o.slabs ?? [], variants: [], images: [],
    minOrderQty: o.minOrderQty ?? 1, orderMultiple: o.orderMultiple ?? 1,
    stockQty: o.stockQty, lowStockThreshold: o.lowStockThreshold ?? 10,
    salePricePaise: o.salePricePaise ?? 0, saleFrom: null, saleTo: null,
    status: o.status ?? 'active', isWholesaleOnly: o.isWholesaleOnly ?? false,
    isFeatured: o.isFeatured ?? false, isBestSeller: o.isBestSeller ?? false,
    isNewArrival: o.isNewArrival ?? false, tags: o.tags ?? [], keywords: o.keywords ?? [],
    seoTitle: o.seoTitle ?? o.name, seoDescription: o.seoDescription ?? o.description,
    ratingCount: o.ratingCount ?? 0, soldCount: o.soldCount ?? 0, weightGrams: o.weightGrams ?? 0,
    // Catalogue sorts on the denormalised rating, so it needs a value even when nothing has reviewed.
    ratingAvg: o.ratingAvg ?? 0,
    createdAt: now,
  };
}

const products = {
  prod_latex_11: product({ id: 'prod_latex_11', name: '11" Round Latex Balloon — Assorted (50 pack)', slug: '11-round-latex-balloon-assorted-50-pack', sku: 'BAL-LTX-11-AS', description: 'Natural latex, 11 inch, matte finish. Sold in packs of 50; carton of 10 packs.', categoryId: 'cat_balloons', categorySlug: 'balloons', brand: 'PartyLite', packSize: '50 pcs', unit: 'pack', retailPricePaise: 45000, slabs: [{ minQty: 5, maxQty: 9, unitPricePaise: 42000 }, { minQty: 10, maxQty: null, unitPricePaise: 39000 }], minOrderQty: 1, orderMultiple: 1, stockQty: 420, isBestSeller: true, tags: ['balloon', 'latex'], keywords: ['balloon wholesale'], seoTitle: '11 inch Latex Balloon 50 Pack — Wholesale', seoDescription: 'Assorted 11 inch natural latex balloons, pack of 50, with slab pricing from 5 packs.', ratingCount: 41, soldCount: 612, weightGrams: 900 }),
  prod_chrome_gold: product({ id: 'prod_chrome_gold', name: 'Chrome Gold Balloon 12" (50 pack)', slug: 'chrome-gold-balloon-12-50-pack', sku: 'BAL-CHR-G-12', description: 'Mirror-finish chrome gold. Popular for wedding and anniversary backdrops.', categoryId: 'cat_balloons', categorySlug: 'balloons', brand: 'Foirolite', packSize: '50 pcs', unit: 'pack', retailPricePaise: 78000, slabs: [{ minQty: 6, unitPricePaise: 72000, maxQty: null }], stockQty: 8, lowStockThreshold: 12, isFeatured: true, tags: ['balloon', 'chrome'], seoTitle: 'Chrome Gold Balloon Wholesale', seoDescription: 'Mirror chrome gold 12 inch balloons, pack of 50.', ratingCount: 17, soldCount: 240, weightGrams: 1100 }),
  prod_foil_number: product({ id: 'prod_foil_number', name: 'Foil Number Balloon 40" (Any Digit)', slug: 'foil-number-balloon-40-any-digit', sku: 'BAL-FOL-40-N', description: 'Self-sealing 40 inch foil numerals for age and anniversary decor.', categoryId: 'cat_balloons', categorySlug: 'balloons', brand: 'Foirolite', packSize: '1 pc', unit: 'piece', retailPricePaise: 12500, slabs: [{ minQty: 10, maxQty: 24, unitPricePaise: 11000 }, { minQty: 25, maxQty: null, unitPricePaise: 9800 }], orderMultiple: 5, stockQty: 260, isNewArrival: true, tags: ['foil'], soldCount: 88 }),
  prod_plate_hard: product({ id: 'prod_plate_hard', name: 'Heavy Duty Dinner Plate — Gold Rim (100 pack)', slug: 'heavy-duty-dinner-plate-gold-rim-100-pack', sku: 'TBL-PLT-G-100', description: 'Rigid plate with a gold rim, suits seated dinners and buffets.', categoryId: 'cat_tableware', categorySlug: 'tableware', brand: 'Eventure', packSize: '100 pcs', unit: 'pack', retailPricePaise: 185000, slabs: [{ minQty: 4, maxQty: 9, unitPricePaise: 172000 }, { minQty: 10, maxQty: 24, unitPricePaise: 161000 }, { minQty: 25, maxQty: null, unitPricePaise: 149000 }], minOrderQty: 2, stockQty: 96, isBestSeller: true, tags: ['tableware', 'plate'], seoTitle: 'Gold Rim Party Plates 100 Pack', seoDescription: 'Heavy duty gold rim dinner plates in bulk cartons of 100.', ratingCount: 63, soldCount: 410, weightGrams: 4200 }),
  prod_glass_pp: product({ id: 'prod_glass_pp', name: 'PP Tumbler Glass — Smoke (250 pack)', slug: 'pp-tumbler-glass-smoke-250-pack', sku: 'TBL-GLS-S-250', description: 'Reusable smoked PP tumblers, 180 ml.', categoryId: 'cat_tableware', categorySlug: 'tableware', brand: 'Eventure', packSize: '250 pcs', unit: 'pack', retailPricePaise: 240000, slabs: [{ minQty: 3, unitPricePaise: 225000, maxQty: null }], stockQty: 40, tags: ['tableware', 'glass'], soldCount: 121 }),
  prod_drape_satin: product({ id: 'prod_drape_satin', name: 'Satin Drape Panel 5x10 ft — Ivory', slug: 'satin-drape-panel-5x10-ivory', sku: 'DCR-DRP-IV-510', description: 'Floor-length backdrop panel, hemmed and eyeleted.', categoryId: 'cat_decor', categorySlug: 'decor', brand: 'DecorPro', packSize: '1 pc', unit: 'piece', retailPricePaise: 95000, slabs: [{ minQty: 10, unitPricePaise: 86000, maxQty: null }], stockQty: 150, isFeatured: true, tags: ['decor', 'backdrop'], seoTitle: 'Satin Backdrop Drape Wholesale', seoDescription: 'Ivory satin drape panels 5 by 10 feet for event backdrops.', ratingCount: 9, soldCount: 54, weightGrams: 1400 }),
  prod_flower_wall: product({ id: 'prod_flower_wall', name: 'Artificial Flower Wall Panel 2x2 ft', slug: 'artificial-flower-wall-panel-2x2', sku: 'DCR-WAL-22', description: 'Modular greenery and bloom panel, clip-together.', categoryId: 'cat_decor', categorySlug: 'decor', brand: 'DecorPro', packSize: '1 pc', unit: 'piece', retailPricePaise: 130000, minOrderQty: 4, orderMultiple: 4, stockQty: 0, lowStockThreshold: 6, tags: ['decor', 'flower'], soldCount: 33 }),
  prod_lights_bulb: product({ id: 'prod_lights_bulb', name: 'Bulb String Lights 30 ft — Warm White', slug: 'bulb-string-lights-30ft-warm-white', sku: 'LGT-STR-30-WW', description: '80 warm-white bulbs, connectable up to 5 strings.', categoryId: 'cat_lighting', categorySlug: 'lighting', brand: 'GlowLine', packSize: '1 set', unit: 'set', retailPricePaise: 165000, slabs: [{ minQty: 5, maxQty: 11, unitPricePaise: 152000 }, { minQty: 12, maxQty: null, unitPricePaise: 141000 }], stockQty: 74, isBestSeller: true, tags: ['lighting'], ratingCount: 28, soldCount: 190 }),
  prod_battery_pack: product({ id: 'prod_battery_pack', name: 'LED Tea Light — Battery (72 pack)', slug: 'led-tea-light-battery-72-pack', sku: 'LGT-TL-72', description: 'Flameless tea lights with a 72 hour timer.', categoryId: 'cat_lighting', categorySlug: 'lighting', brand: 'GlowLine', packSize: '72 pcs', unit: 'pack', retailPricePaise: 21000, isWholesaleOnly: true, stockQty: 5, lowStockThreshold: 20, tags: ['lighting', 'led'], soldCount: 61 }),
  prod_retired: product({ id: 'prod_retired', name: 'Retired Paper Lantern (archived)', slug: 'retired-paper-lantern', sku: 'DEC-PL-OLD', description: 'Discontinued line, kept to prove non-active rows never surface.', categoryId: 'cat_decor', categorySlug: 'decor', retailPricePaise: 30000, stockQty: 0, status: 'draft' }),
};

// Coupon field names are exactly what CouponModel.fromMap reads: `kind` is a CouponKind code
// ('percentage' | 'flat' | 'freeShipping'), the discount itself is `percentOff` or `valuePaise`, and
// the basket floor is `minCartValuePaise`.
const coupons = {
  WELCOME10: { id: 'WELCOME10', code: 'WELCOME10', kind: 'percentage', description: 'Welcome — 10% off your first counter order', percentOff: 10, valuePaise: 0, minCartValuePaise: 100000, usageLimit: 500, usedCount: 12, isActive: true, excludesWholesale: false, endsAt: null, createdAt: now },
  FREESHIP999: { id: 'FREESHIP999', code: 'FREESHIP999', kind: 'freeShipping', description: 'Free delivery on orders above Rs 999', percentOff: 0, valuePaise: 0, minCartValuePaise: 99900, usageLimit: null, usedCount: 3, isActive: true, excludesWholesale: false, createdAt: now },
};

// store_settings/store — the values the storefront reads before it will render anything. Tax is
// basis points (18% = 1800) and every amount is paise.
const settings = {
  store: {
    shopName: 'OM Events And Decorators',
    tagline: 'Wholesale & Party Supplies',
    description: 'Balloon, tableware, decor and lighting supplies for traders, planners and event teams.',
    city: 'Hyderabad', state: 'Telangana', pincode: '500001',
    phone: '+91 90000 00000', whatsapp: '+91 90000 00000', email: 'counter@example.invalid',
    openingHours: 'Mon–Sat 10:00–20:00', googleMapsUrl: '', gstNumber: '36ABCDE1234F1Z5',
    invoicePrefix: 'OME', socialLinks: {},
    seoTitle: 'OM Events And Decorators — Wholesale & Party Supplies',
    seoDescription: 'Wholesale party supplies, balloons, decor and event materials with automatic quantity pricing.',
    taxInclusive: false, taxRateBps: 1800,
    minOrderValuePaise: 50000, freeShippingAbovePaise: 500000,
    isPickupEnabled: true, pickupNotes: 'Counter pickup from the warehouse, 11:00–18:00.',
    shippingZones: [
      { id: 'zone_hyderabad', name: 'Hyderabad city', pincodePrefixes: ['50'], flatRatePaise: 4900, freeAbovePaise: 500000, etaDaysMin: 1, etaDaysMax: 2, isActive: true },
    ],
    paymentMethods: [
      { code: 'cod', label: 'Cash on delivery', isEnabled: true, description: 'Pay the courier when the order arrives.', extraFeePaise: 0, minAmountPaise: 0, maxAmountPaise: null },
      { code: 'online', label: 'Pay online', isEnabled: false, description: 'Online payment is not configured for the local demo.', extraFeePaise: 0, minAmountPaise: 0, maxAmountPaise: null },
    ],
    allowGuestCheckout: true,
    cancellationPolicy: '', refundPolicy: '', shippingPolicy: '', privacyPolicy: '',
  },
};

async function main() {
  const counts = [];
  counts.push(['categories', await writeDocs('categories', categories)]);
  counts.push(['products', await writeDocs('products', products)]);
  counts.push(['coupons', await writeDocs('coupons', coupons)]);
  counts.push(['store_settings', await writeDocs('store_settings', settings)]);

  // Two logins so the role split is demonstrable. `users/{uid}` is normally minted by the
  // accountEnsure function and its `role` is owned by functions only; writing it here is possible
  // solely because the demo rules are off. Production rules reject the identical write.
  const demoUsers = [
    { email: 'admin@om-events.test', password: 'emulator-demo', role: 'admin', name: 'Store Admin' },
    { email: 'buyer@om-events.test', password: 'emulator-demo', role: 'customer', name: 'Walk-in Buyer' },
  ];
  const userDocs = {};
  for (const u of demoUsers) {
    const uid = await createAuthUser(u.email, u.password);
    if (!uid) throw new Error(`Could not create ${u.email}`);
    userDocs[uid] = {
      id: uid, uid, email: u.email, displayName: u.name, phone: '', gstNumber: '', companyName: '',
      role: u.role, wholesaleStatus: u.role === 'admin' ? 'approved' : 'pending', isBlocked: false,
      notifyEmail: false, notifyWhatsapp: false, notifySms: false,
      wishlistProductIds: [], addresses: [], createdAt: now,
    };
  }
  counts.push(['users', await writeDocs('users', userDocs)]);

  for (const [name, n] of counts) console.log(`  seeded ${String(n).padStart(3)} ${name}`);
  console.log('\nDemo logins (emulator only, no real account):');
  for (const u of demoUsers) console.log(`  ${u.role.padEnd(8)} ${u.email} / ${u.password}`);
}

main().catch((e) => {
  console.error(`\nSeed failed: ${e.message}`);
  console.error('Is the emulator running? npx firebase-tools@13.35.1 emulators:start --config firebase.local.json --project demo-om-events --only auth,firestore\n');
  process.exit(1);
});
