# Firebase Complete Audit — Configuration, Integration, Missing Setup & Production Readiness

**Project:** `D:\event_shop` — OM Events And Decorators (Flutter Web, GetX)
**Audit date:** 2026-10-21
**Intended production project:** `om-events-store` (project number `438395878265`)
**Intended database:** Firestore `(default)`, region `asia-south1`
**Local project:** `demo-om-events` (emulators)
**Mode:** read-only audit. No deploy, no production call, no Console change, no code/config fix.
**Method:** five read-only specialist agents (config/auth, Firestore/indexes, Functions, Storage/media, hosting/other services) followed by independent verification of every material claim by the lead; all local commands below were executed in this audit unless explicitly marked otherwise.

> **What changed during this audit:** nothing under version control. The working tree already contained the staged Phase 1 rules/functions/test changes. `flutter analyze` refreshed local package metadata only (`pubspec.lock` unchanged). The only file created is this report.

---

## A. Executive Summary

**Overall production readiness: ≈40 %.**

| Question | Answer |
|---|---|
| Is Firebase fully configured? | **No.** The application code is Firebase-aware and locally tested; no production project is wired, deployed, or verified. |
| Is production launch safe today? | **No.** Five P0 blockers remain (below). |
| Does local success prove production? | **No.** Rules are proven against the emulator; indexes, Functions, Auth Console, billing and hosting are not. |

### Top five blockers

1. **P0-1 — Production environment is not wired, and the recorded plan cannot run the backend.** Owner-side notes from 2026-10-21 record `om-events-store` created with a Web app, Email/Password and Firestore `asia-south1`, but on **Spark**; this audit could not re-verify any of that. `.firebaserc` is still the placeholder (`REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID`), no production `--dart-define` file exists (gitignored), and Spark blocks deployment of all 39 callables + 3 triggers. Nothing can be deployed or live-tested as-is.
2. **P0-2 — Composite indexes do not match the real storefront queries.** Every retail product query now adds `isWholesaleOnly == false`; `firestore.indexes.json` has only one wholesale-aware index. At least 20 product index shapes (category, shelves, price/rating/soldCount sorts, search keywords, tags, wishlist `documentId in`) plus admin order/audit combinations are absent. The emulator does not enforce indexes, so local green tests hide this.
3. **P0-3 — Checkout/order transactions contain read-after-write and counter defects.** Coupon orders, cancellation stock restore and wholesale approval perform `tx.get` after a write inside the same Admin SDK transaction; the monthly order counter is read but never written. These fail only against real Firestore. The 104 green Functions tests use a fake transaction that explicitly allows reads after writes.
4. **P0-4 — The committed hosting artifact is a demo build.** `build/web/main.dart.js` is an emulator-targeted bundle (contains `demo-om-events`, no real key), and `build/web/index.html`, `robots.txt`, `sitemap.xml` still contain **28 literal `SITE_ORIGIN` tokens** (11/3/14). There is no CI and no token-substitution script.
5. **P0-5 — Admin media pipeline cannot work.** Firestore rules deny all `media_objects` writes (`firestore.rules:395-397`) while the uploader writes that ledger row *before* uploading; the gallery path writes `products/{id}.images` directly, which rules also deny; Supabase Storage is documented but not provisioned; the `mediaOptimise` callable is not deployed (and is dead code). Product images cannot be managed end-to-end.

### What is genuinely strong

- Firestore rules compile and **39/39 emulator tests pass** against the real Rules engine (not mocks), including role escalation, blocked accounts, staff-only reads, query-shape legality and the documented support-append limitation.
- Flutter analyzer is clean (**No issues found**) and **256 Flutter tests pass** (7 skipped).
- No client secret was found: no Admin SDK, no service-role key, no `firebase_storage` dependency, no real API key in the build artifact.
- The application refuses to render fake merchandise without Firebase configuration (`main.dart:29-36`) and fails closed on guards.

---

## B. Configuration Inventory

| Service / area | Purpose in this app | Configuration location | Status | Evidence |
|---|---|---|---|---|
| Firebase project alias | Selects deploy target | `.firebaserc` | **FAIL — placeholder** | `default = REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID`; no `om-events-store` committed anywhere except a disposable spike README |
| Firebase web app options | Client init | `--dart-define` via `lib/app/core/env.dart` | **PARTIAL — code complete, production values absent** | `Env` reads `FIREBASE_API_KEY/PROJECT_ID/APP_ID`; empty defaults; no `firebase_options.dart` |
| Auth | Email/password, profile mirror | `firestore_auth_repository.dart`, `accountEnsure` | **PARTIAL — works in emulator; Console unverified** | No email verification; reset has no `ActionCodeSettings`; session restore defect below |
| Firestore | Primary database | `lib/data/**`, `functions/**` | **PARTIAL — code complete; production not verified** | Env-driven DB; no region/default-DB evidence |
| Firestore rules | Authorization | `firestore.rules` (418 lines, SHA-256 `b5d8542d…a285d`) | **PASS — VERIFIED locally** | 39/39 emulator tests; strict reload via REST; not deployed |
| Composite indexes | Query serving | `firestore.indexes.json` (50 definitions) | **FAIL — incomplete** | See §C5; emulator does not enforce them |
| Cloud Functions | All trusted writes | `functions/index.js` + `functions/lib/**` | **PARTIAL — present, not deployable safely** | 39 callables + 3 triggers; P0 transaction/counter defects; Node 20 runtime configured |
| Functions tests | Regression coverage | `functions/test/**` (104 tests) | **PARTIAL — pass, but fake transactions** | `fake-firestore.js:13,292-293` models reads-after-write, unlike Firestore |
| Storage | Unused / Supabase intended | `storage.rules`, `storage.rules` only | **NOT USED — NEEDS DECISION** | No `firebase_storage` dependency; rules deny all writes; staff rule uses JWT claims the app never sets |
| Supabase Storage | Intended media home | Docs + Dart repository | **FAIL — unprovisioned** | No `supabase/` project, no SQL/policies; upload ledger blocked by Firestore rules |
| Hosting | SPA delivery | `firebase.json` (`build/web`) | **FAIL — no shippable artifact** | Demo bundle + unresolved SEO tokens; no CI |
| FCM / web push | Not implemented | — | **NOT REQUIRED — NOT USED** | No `firebase_messaging`, no service worker |
| Analytics / Crashlytics / Remote Config / Performance | Not implemented | — | **NOT REQUIRED — NOT USED** | No dependencies or calls |
| App Check | Abuse protection | — | **MISSING — NEEDS DECISION** | No dependency or enforcement |
| Emulator suite | Local verification | `firebase.local.json`, `firebase.local.strict.json` | **PASS — VERIFIED** | Auth 9099 / Firestore 8080 / Functions 5001 reachable; project `demo-om-events` |
| CI/CD | Build/test/deploy | — | **MISSING** | No `.github/workflows`, no Vercel/Netlify config |
| Billing | Functions deployment | Console only | **FAIL — reported Spark (NOT VERIFIED this audit)** | Owner-side record says `om-events-store` is on Spark; docs state Functions require Blaze (`docs/backend-setup.md:39`); Console could not be read |

---

## C. Feature-by-Feature Audit

### C1. Project and environment configuration

| Finding | Label | Evidence |
|---|---|---|
| No production project is pinned; deployment cannot target the intended project | **FAIL — ISSUE FOUND** | `.firebaserc:1-5` placeholder; `firebase.json` has no project; no alias for `om-events-store` |
| No accidental production deploy is possible today (fails closed) | **PASS — VERIFIED** | Placeholder project id causes CLI failure rather than a wrong-target deploy |
| Local/production separation exists only as intent | **PARTIAL — PARTIALLY VERIFIED** | `Env.useEmulators` is off by default (`env.dart:17`); emulator routing is explicit (`app_bootstrap.dart:79-97`). No staging project or staging defines. |
| Emulator ports match the client | **PASS — VERIFIED** | `firebase.json`/local configs 9099/8080/5001 vs `env.dart:36-41`; all three endpoints reachable |
| Old project ids (`om-events-and-decorators`, `om-event`) are not in active config | **PASS — VERIFIED** | Repository-wide search found only `spike/edge-feasibility/README.md` mentioning `om-events-store`; no old id in config/client |
| Docs and config contradict each other | **PARTIAL — PARTIALLY VERIFIED** | `.firebaserc` comment recommends `firebase projects:add` (not a Firebase CLI command); README build commands reference a gitignored `.env.production.json` that does not exist |
| Strict local config is valid JSON | **PARTIAL** | `JSON.parse` fails on a UTF-8 BOM in `firebase.local.strict.json`; the already-running emulator proves the CLI tolerates it, but this audit did not restart the emulator |

**Why it matters:** no deployment, Console verification or production smoke test is possible until a real project alias and production defines exist.

**Exact action:** confirm the existing `om-events-store` project and web app, resolve the Spark/Blaze (or migration) decision, run `firebase use --add`, keep the real id out of git (the existing `.firebaserc` policy), and create a local `.env.production.json` from `.env.example` with the public web values. Add a staging project/alias before the first deploy.

---

### C2. Firebase Authentication

| Check | Label | Evidence / result |
|---|---|---|
| Firebase Auth initialized from env | **PASS — VERIFIED (code)** | `app_bootstrap.dart` initializes only when `Env.hasFirebase`; emulator wiring at `:91-97` |
| Sign-up / sign-in / sign-out / profile mint | **PASS — PARTIAL (code)** | `firestore_auth_repository.dart:92-138`; sign-in and sign-up both call `accountEnsure`; server mints `role` (`functions/index.js:1490-1510`) |
| Client cannot escalate its own role | **PASS — VERIFIED (rules)** | 39/39 Rules tests cover user create/update/role escalation and blocked accounts |
| Auth-state restoration after page reload | **FAIL — ISSUE FOUND (code path)** | `AuthRepository` is only `Get.lazyPut` (`backend_binding.dart:44`); its auth listener is attached in the constructor (`firestore_auth_repository.dart:18-20`); nothing resolves it at startup (`main.dart:13-16`, `global_binding.dart:11-26`). `SessionStore` starts empty (`session_store.dart:10-16`), and `AuthGuard`/`AdminGuard` decide synchronously (`guards.dart:26-55`). Reloading `/account` or `/admin` bounces a signed-in user to `/login`; the storefront header renders signed-out until an auth screen resolves the repository. Not executed in a browser this audit. |
| Password reset | **PARTIAL — PARTIALLY VERIFIED** | `sendPasswordResetEmail` exists (`firestore_auth_repository.dart:143-149`) but no `ActionCodeSettings`/continue URL, so the emailed link depends on the Console action-link domain and template, both unverified |
| Email verification | **MISSING** | No `sendEmailVerification` or `emailVerified` check anywhere in `lib/` |
| Half-created profile recovery | **PARTIAL** | Sign-up creates the Auth user before `accountEnsure`; a failed callable leaves a user without a profile doc, shown provisionally as a guest. The next sign-in calls `_ensure` and repairs it. |
| Admin/staff authorization source | **PASS — VERIFIED (design)** | Roles live on `users/{uid}` and are re-read by rules/functions; JWT claims are advisory only |
| JWT claim mirror | **FAIL — ISSUE FOUND** | `adminAuth.setCustomRole(...)` (`functions/index.js:988-990`) is not an Admin SDK API; the error is swallowed, so custom claims are never set. No current security dependency, but Storage rules that rely on `request.auth.token.role` can never pass. |
| Auth Console facts | **NOT VERIFIED — EVIDENCE UNAVAILABLE** | Email/password provider, authorized domains, email templates, action-link domain, quotas, production persistence |

**Exact action:** resolve `AuthRepository` at bootstrap and await the first auth emission before `runApp` (with a bounded timeout), or bind it eagerly in `AppRootBinding`; add a browser reload test for `/account` and `/admin`. Add email verification if required by product policy. Replace `setCustomRole` with `adminAuth.setCustomUserClaims` or delete the dead call. Confirm all Console settings manually.

---

### C3. Cloud Firestore data model

- **PASS — VERIFIED (structure):** collections and converters agree for products, categories, variants, orders, reviews, notifications, support, wholesale, users, coupons, inventory, audit, settings and media references. Rules coverage is broad and default-deny.
- **PARTIAL — data/setup documents:** `store_settings/store` is required by the storefront; `adminSettingsSave` writes it, and the local seed creates it. No production document exists or was verified. `counters/*`, `coupons/*`, `customer_price_overrides/*` are created on demand.
- **FAIL — local seed shape drift** (`scripts/local/seed_local_store.mjs`):
  - `paymentMethods: ['cod', 'online']` (`:165`) are strings, but `StoreSettings.fromMap` reads maps via `readMapList` (`store_settings.dart:218-220`; `om_doc.dart:47-56` filters out non-maps), so a freshly seeded store has **zero payment options**.
  - `shippingZones: []` (`:165`) means every courier pincode is unserviceable; only pickup can pass the zone table.
  - Coupons use `expiresAt` while the client model stores/reads `endsAt` (`coupon.dart:108-109,129-130`). Null in the current seed, so inert, but the shape is inconsistent.
  - Product slabs overlap in at least one seeded product (flagged by the specialist; would be rejected by `validateSlabGrid` if edited through admin).
- **PASS — ownership/authorization:** orders are owner/staff-readable only; client writes to orders, payments, coupons, stock, settings and audit are denied; those writes are callable-only.
- **FAIL — order line snapshots omit money fields:** the stored order item spreads `snapshot` (`functions/index.js:210-220`, `:352`), which lacks `unitPricePaise`, `lineTotalPaise` and `categoryId`. `OrderItem.fromMap` defaults missing ints to 0 (`order.dart:126-132`). Customer order detail/history therefore shows **₹0 line prices**, and any report/CSV derived from items loses line revenue and category.
- **FAIL — order counter never persists:** `counterRef` is read (`functions/index.js:310-312`) but never written; every order in a month receives sequence 1, so invoice/order numbers repeat.
- **NOT VERIFIED — production data:** whether `store_settings/store` exists, whether counters exist, collection sizes, region/backups. No production access was used.

---

### C4. Security Rules

| Check | Label | Evidence |
|---|---|---|
| Current file identity | **PASS — VERIFIED** | `sha256sum firestore.rules` = `b5d8542dcf78d96e719b20362dd829202bed7f8075609a5b887fd216a44a285d`; 418 lines; matches the last reported candidate |
| Compiles in strict emulator | **PASS — VERIFIED** | Harness reloads the file with `ignore_errors=false` before running; suite completed |
| Default deny | **PASS — VERIFIED** | Catch-all deny plus explicit collection blocks; tested |
| Anonymous/cross-customer isolation | **PASS — VERIFIED** | 39/39 suite covers anonymous reads, customer A vs B, blocked users |
| Staff/admin access | **PASS — VERIFIED** | Staff-only reads tested; role checks read the user document, not claims |
| Role escalation prevention | **PASS — VERIFIED** | Users create/update/role tests pass |
| Product/catalogue read rules | **PASS — VERIFIED** | Wholesale-only visibility and status constraints tested |
| Support message append limitation | **PASS — DOCUMENTED + TESTED** | An append that also edits an older turn is accepted; explicitly tested and recommended for a server-side normalize path if immutability must be strict |
| `media_objects` | **FAIL — blocks the product** | Public read, `allow write: if false` (`firestore.rules:395-397`); see §C8 |
| `products` writes | **FAIL — blocks the gallery path** | Function-only writes (`firestore.rules:154-193`); gallery updates products directly |
| Rules tests are real, not mocked | **PASS — VERIFIED** | `scripts/local/rules/security_rules.test.mjs` drives the emulator REST API with real Auth-emulator ID tokens (seed uses the emulator `Bearer owner` bypass only for fixtures) |
| Production rules deployment | **NOT VERIFIED** | Not deployed; no production project configured |

---

### C5. Composite Index Audit — HIGH PRIORITY

`firestore.indexes.json` contains **50 definitions** (21 `products`, 5 `orders`, 3 `reviews`, 3 `audit_logs`, etc.). Its header claims every read path is backed; that is no longer true.

The decisive change: every storefront product query now appends `isWholesaleOnly == false` for retail/anonymous callers (`firestore_catalog_repository.dart:96-101,151,163`; builder `catalog_query_builder.dart:43`). Firestore requires the index to contain **all equality fields**, so the existing indexes without `isWholesaleOnly` cannot serve these queries.

#### Missing index families (minimum launch set)

| # | Collection | Required field sequence | Query source | In JSON? |
|---|---|---|---|---|
| 1 | products | `status` + `isWholesaleOnly` + `retailPricePaise` ASC and DESC | price sort, retail browse — `catalog_query_builder.dart:43,58-59,101-104` | **No** (only `status+retailPrice`, lines 11-12) |
| 2 | products | `status` + `isWholesaleOnly` + `soldCount` DESC | best-selling sort — `:98` | **No** |
| 3 | products | `status` + `isWholesaleOnly` + `ratingAvg` DESC | rating sort — `:106` | **No** |
| 4 | products | `status` + `isWholesaleOnly` + `name` ASC | search suggestions — `firestore_catalog_repository.dart:237-243` | **No** (only `status+name`) |
| 5 | products | `status` + `categorySlug` + `isWholesaleOnly` + `createdAt` DESC | single-category browse — `builder:27-28`, repo `:153-154` | **No** (only `status+categorySlug+createdAt`, line 4) |
| 6 | products | `status` + `categorySlug` + `isWholesaleOnly` + `retailPricePaise` ASC/DESC | category price sort | **No** |
| 7 | products | `status` + `categorySlug` + `isWholesaleOnly` + `soldCount` DESC | category best-selling | **No** |
| 8 | products | `status` + `categorySlug` + `isWholesaleOnly` + `ratingAvg` DESC | category rating | **No** |
| 9 | products | `status` + `categoryId` + `isWholesaleOnly` + `createdAt` DESC | multi-category/newest — `builder:30-33` | **No** (only `status+categoryId+createdAt`, line 5) |
| 10 | products | `status` + `categoryId` + `isWholesaleOnly` + `retailPricePaise` ASC/DESC | multi-category price | **No** (lines 6-7 lack wholesale) |
| 11 | products | `status` + `categoryId` + `isWholesaleOnly` + `soldCount` DESC | related products — `repo:221-224` | **No** |
| 12 | products | `status` + `categoryId` + `isWholesaleOnly` + `ratingAvg` DESC | multi-category rating | **No** |
| 13 | products | `status` + `isFeatured` + `isWholesaleOnly` + `createdAt` DESC | home shelf — `repo:194-197,209-215` | **No** |
| 14 | products | `status` + `isNewArrival` + `isWholesaleOnly` + `createdAt` DESC | home shelf | **No** |
| 15 | products | `status` + `isBestSeller` + `isWholesaleOnly` + `soldCount` DESC | home shelf | **No** |
| 16 | products | `keywords` (array-contains-any) + `status` + `isWholesaleOnly` + each sort | text search — `builder:51-54` | **No keywords entry at all** |
| 17 | products | `tags` (array-contains) + `status` + `isWholesaleOnly` + each sort | tag filter — `builder:45-48` | **No tags entry at all** |
| 18 | products | `__name__` (in) + `status` + `isWholesaleOnly` | wishlist/cart product hydration — `firestore_account_repository.dart:126-132`, catalog `:139-142` | **No** |
| 19 | orders | `deliveryMode` + `createdAt` DESC; `userId` + `status`/`paymentStatus` + `createdAt` DESC; combined filters | admin order queue — `firestore_admin_repository.dart:294-303` | **No** (only status/paymentStatus singles and status+paymentStatus) |
| 20 | audit_logs | `actorUid` + `createdAt`; `entityType`/`action` + `actorUid` + `createdAt` | admin audit filter — `firestore_admin_repository.dart:586-592` | **No actorUid entries** |

**Count:** roughly **20–25 product definitions** plus several order/audit entries are missing. The exact number depends on which sort/filter combinations the UI exposes, but items 1–5 alone cover the default retail home/category/search paths.

**Emulator vs production:** all 39 rules tests pass because the emulator does not require composite indexes. A local pass proves query **legality under rules**, not index availability. Production would return `failed-precondition` with an index-creation link.

**Exact action:** extend `firestore.indexes.json`, deploy to a staging project with `firebase deploy --only firestore:indexes` (requires approval), then exercise every sort/filter combination and confirm **no** index-creation links appear. Do not treat emulator success as deployment evidence.

---

### C6. Cloud Functions

**Inventory (verified by loading the module): 42 exports = 39 callables + 3 Firestore triggers.**

- Callables: `ordersCreate`, `orderByIdempotency`, `orderRequestCancel`, `orderRequestReturn`, `couponsQuote`, `paymentsConfirm`, `adminOrderTransition`, `adminOrderMarkPayment`, `adminOrderRefund`, `adminCounterOrder`, `adminProductSave`, `adminProductArchive`, `adminVariantSave`, `adminVariantDelete`, `inventoryAdjust`, `inventorySetOpening`, `reviewSubmit`, `reviewReport`, `adminReviewModerate`, `adminWholesaleDecide`, `adminCustomerRole`, `adminCustomerBlock`, `adminCouponSave`, `adminCouponDelete`, `adminCustomerPriceSave`, `adminCustomerPriceDelete`, `adminCustomerPriceList`, `adminCategorySave`, `adminCategoryDelete`, `adminSalesByDay`, `adminTopCustomers`, `adminCustomerValue`, `adminSettingsSave`, `adminSupportUpdate`, `adminDashboard`, `adminReport`, `adminImportProducts`, `accountEnsure`, `variantListForProduct`.
- Triggers: `onWholesaleApplicationCreated`, `onReviewWritten`, `onProductWritten`.
- No scheduled function, no HTTP endpoint, no payment webhook.
- Authentication: every callable calls `requireCaller`/`requireRole`; triggers run with Admin SDK. `ordersCreate` permits anonymous guests but owns replay checks.
- Runtime: Node 20 configured (`functions/package.json`, `firebase.json`); syntax-checked locally on Node 24.
- Secrets: only the name `OM_PAYMENT_GATEWAY` (`process.env`, `index.js:421,613`); no code-level `defineSecret` binding was found. Whether `firebase.json`'s `secretEnvironmentVariables` is honored was not verified.
- Tests: 104 `node:test` cases pass; **they use a fake Firestore** (`functions/test/support/fake-firestore.js:13,292-293` says transactions are write queues and `tx.get` sees queued writes). They therefore cannot catch read-after-write defects.

#### Defects

| ID | Priority | Finding | Evidence | Impact |
|---|---|---|---|---|
| F-01 | **P0** | Coupon redemption reads after writing: `tx.update(couponRef)` then `tx.get(redemptionRef)` | `functions/index.js:376-381` (earlier read at `:257` could be reused) | Any order with a coupon/free shipping fails in real Firestore |
| F-02 | **P0** | Cancellation/return restore reads stock after writing history | `index.js:518-552` (write at `:525-531`, `tx.get` at `:542`) | Cancel/return fails when it must restore stock |
| F-03 | **P1** | Wholesale approval updates the application then reads the user | `index.js:957-962` | Approve/reject fails in production |
| F-04 | **P1** | Monthly order counter is read but never written | `index.js:307-313` | Every order in a month gets the same sequence/number |
| F-05 | **P1** | `adminCounterOrder` calls the `onCall` wrapper directly (`exports.ordersCreate(synthetic)`) instead of the inner handler | `index.js:721-739` | Staff counter sales likely throw; no test covers it |
| F-06 | **P1** | Order item snapshots omit `unitPricePaise`, `lineTotalPaise`, `categoryId` | `index.js:210-220`, `:352`; `order.dart:88-109` | ₹0 line prices in customer history; lossy reports/CSV |
| F-07 | **P1** | Refund validates only the single amount against total paid, not against remaining refundable | `index.js:704-717` | Repeated partial refunds can exceed paid |
| F-08 | **P1** | No payment webhook; `paymentsConfirm` only reflects a `payments` doc that only an admin/manual path creates | `index.js:609-638`; no gateway handler | Online orders remain pending forever; COD/manual only |
| F-09 | **P2** | `mediaOptimise` is declared in Dart but not exported by Functions | `media_optimise_gateway.dart:104`; export list | Dead code today (the uploader defaults to a passthrough gateway), latent failure if wired |
| F-10 | **P2** | `setCustomRole` is not an Admin SDK API and is swallowed | `index.js:988-990` | Claims never mirror roles; Storage rules depending on claims cannot pass |
| F-11 | **P2** | `orderByIdempotency` is exported but not called by the client; no guest order lookup exists | grep of `lib/`; export list | Dead endpoint / product decision for guest tracking |
| F-12 | **P3** | `variantListForProduct` is the only public catalogue callable; fine, but every public callable lacks App Check | `index.js:1556`; no App Check dependency | Abuse/cost exposure once public |

**What is correct:** pricing/rounding agreement, pincode serviceability, coupon windows/limits (enforced in `functions/lib/checkout.js:28-38`, tested), per-user redemption limits, replay ownership, stock decrement/serialization, audit writes, and role checks. These are covered by the 104 tests and were not contradicted by code inspection.

**Exact action:** move every transactional read before the first write (or reuse the existing read), persist the counter with `tx.set`, validate refunds against `paid − refunded`, call the inner order handler (refactor `ordersCreate` into a shared function) for counter orders, add the missing snapshot fields, then add **Functions-emulator integration tests** for coupon checkout, cancellation, wholesale approval and counter sale.

---

### C7. Billing and backend architecture

- **Configured plan: reported Spark; NOT VERIFIED in this audit.** Owner-side records from 2026-10-21 say `om-events-store` was created (Web app, Email/Password, Firestore `asia-south1`) on **Spark**. No production project is selected in the repo and no Console read was attempted, so this must be re-checked before planning. If Spark is confirmed, the trusted backend cannot deploy at all.
- **Deployment requirement: Blaze is required for Cloud Functions.** The repository itself states it (`docs/backend-setup.md:39`). Without Blaze, 39 callables and 3 triggers cannot be deployed; the app's checkout, admin writes and profile minting all depend on them.
- **Alternatives:** Supabase Edge Functions are *not* implemented. `spike/edge-feasibility/README.md` is explicitly disposable, not integrated, and flags that 9 transactional sites (including checkout) need proof under Deno. `docs/supabase-storage.md` covers Storage only. No `supabase/` directory, no Edge Functions, no migration.
- **Identity/database:** Firebase Auth + Firestore remain the only implemented identity/database layer. Supabase is intended for media only. Mixing providers would require a token bridge; none exists.
- **Decision required:** activate Blaze and keep Functions, or fund and execute a Supabase Edge Functions migration before launch. This audit cannot make that decision.

---

### C8. Storage and media

| Check | Label | Evidence |
|---|---|---|
| Firebase Storage bucket configured | **NOT VERIFIED / NOT USED** | No `firebase_storage` dependency; `FIREBASE_STORAGE_BUCKET` optional and unused |
| `storage.rules` secure | **PASS — secure by default, but dead config** | Public read only under `public/`; all writes denied (`storage.rules:18-28`) |
| Staff read rule correctness | **FAIL (latent)** | Uses `request.auth.token.role`, but roles are Firestore docs and claims are never set (`setCustomRole` is invalid) |
| Upload path authenticated/user-scoped | **PARTIAL** | Supabase repository scopes paths by owner; no live project to verify |
| File type/size validation | **PARTIAL — code-level** | `MediaLimits`/analysis exist; not verified against a live bucket |
| Public URLs expose sensitive files | **NOT VERIFIED** | No bucket provisioned |
| `media_objects` writable by client | **FAIL** | `firestore.rules:395-397` denies; ledger itself documents the requirement (`media_object_ledger.dart:293-308`) and the uploader writes it before bytes (`media_uploader.dart:496-499`) |
| Product gallery commit | **FAIL** | Direct `products/{id}.images` update (`supabase_media_repository.dart:800-811`) is denied by function-only product writes |
| Supabase project/policies | **MISSING** | Only `docs/supabase-storage.md`; no `supabase/` directory, no SQL, no bucket |
| `media_objects` ownership | **NEEDS DECISION** | Should be server-owned (Edge Function/callable); currently client-managed and blocked |
| Storage emulator coverage | **MISSING** | Not in either local config; no tests |

**Exact action:** pick one media architecture. Recommended: Supabase Storage + a small trusted server writer (Edge Function or a Firebase callable) that writes `media_objects` and the product `images` field; provision the bucket and RLS policies from a committed SQL file; add emulator/unit coverage. If Firebase Storage is chosen instead, add the SDK, a bucket, and a callable-based upload/sign path; do not reopen client writes.

---

### C9. Other Firebase services

| Service | Status | Evidence / decision |
|---|---|---|
| FCM / web push | **NOT REQUIRED — NOT USED** | No `firebase_messaging`, no `firebase-messaging-sw.js`; notifications are Firestore docs only |
| Analytics | **NOT REQUIRED — NOT USED** | No dependency/calls |
| Crashlytics | **NOT REQUIRED — NOT USED** | Not supported on Flutter web; no dependency |
| App Check | **MISSING — NEEDS DECISION** | Public callables and Firestore are unthrottled beyond Firebase defaults; recommended before paid traffic |
| Remote Config | **NOT REQUIRED — NOT USED** | No dependency |
| Performance Monitoring | **NOT REQUIRED — NOT USED** | No dependency |
| Hosting | **PARTIAL** | Config present; artifact not shippable (§C10) |
| Authorized domains / custom domain / SSL | **NOT VERIFIED** | Console-only |
| Backups / PITR | **NOT VERIFIED** | Console-only; no restore drill exists |

---

### C10. Hosting, CI/CD and production readiness

- **Hosting config:** `firebase.json` serves `build/web`, SPA rewrite `** → /index.html`, immutable asset caching, `cleanUrls`. The app uses hash routing, so the rewrite is harmless but indicative of copy-pasted config.
- **Committed artifact is not production:** `build/web/main.dart.js` was built 2026-10-19, contains **3 × `demo-om-events`** and **0** real API keys / service-role keys. It is an emulator build.
- **Unresolved deploy tokens:** `build/web/index.html` 11, `robots.txt` 3, `sitemap.xml` 14 = **28** literal `SITE_ORIGIN`. The repository has no substitution script.
- **No CI:** no `.github/workflows`, no Vercel/Netlify config. Deploy is manual and undocumented beyond README build commands pointing at an absent `.env.production.json`.
- **No wrong-project safeguard beyond the placeholder:** once `firebase use` rewrites `.firebaserc`, `test/security_hygiene_test.dart:134-153` will **fail**, because it accepts only `demo-*` or the placeholder. The documented setup and the test conflict; choose one policy (e.g. ignore a local, gitignored `.firebaserc`, or allow a `staging`/`production` alias).
- **Exposure:** no CSP/security headers beyond cache headers; source maps are not part of `build/web` (no `.map` found in the served tree) but this was not exhaustively scanned.

**Exact action:** add a deterministic build script that (1) passes production defines, (2) substitutes `SITE_ORIGIN` and fails if any token remains, (3) runs analyzer/tests, and (4) emits a smoke-testable artifact; wire it to CI with an explicit project alias.

---

### C11. Documentation and local setup

- `docs/backend-setup.md` is honest: it states rules/functions are unverified against a live project (`:9`) and lists Console steps including Blaze (`:39`). **PASS — accurate.**
- `README.md:31,65` instructs `--dart-define-from-file=.env.production.json`, but the file is gitignored and absent; `.env.example` is the only template.
- `docs/local-demo.md` correctly documents that checkout/admin writes need Functions, and that online capture stays unavailable without a gateway.
- Seed drift (§C3) means the documented "working cart/coupon/checkout total" demo cannot select a payment method or deliver a courier order without editing settings.

---

## D. Missing Setup Checklist

### 1. Missing code

- [ ] Transaction read-before-write fixes (F-01, F-02, F-03) and counter persistence (F-04).
- [ ] Counter-order handler refactor + test (F-05).
- [ ] Order item money/category fields (F-06).
- [ ] Refund cumulative validation (F-07).
- [ ] Payment gateway + webhook (F-08).
- [ ] Server-side media writer + product-image callable (P0-5).
- [ ] Bootstrap auth hydration / eager `AuthRepository` resolution.
- [ ] Production index definitions for the query shapes in §C5.
- [ ] Production build script with token substitution and CI.
- [ ] `setCustomUserClaims` (or removal of the dead call), guest-lookup decision.
- [ ] Functions-emulator integration tests that exercise real Admin SDK transactions.

### 2. Missing local configuration

- [ ] `.env.production.json` with the public web values (gitignored).
- [ ] Real project alias via `firebase use --add` (do not commit the id).
- [ ] Staging project/alias and defines.
- [ ] Token-substitution step for `web/index.html`, `robots.txt`, `sitemap.xml`.
- [ ] Storage emulator (only if Firebase Storage is chosen).
- [ ] A seeded store whose `paymentMethods` are maps and whose `shippingZones` cover at least one pincode.

### 3. Missing Firebase Console setup (manual, unverified)

- [ ] Re-confirm `om-events-store` and its plan (reported Spark); register/verify the Web app, copy public options.
- [ ] Authentication → Email/Password enabled; authorized domains; email templates; action-link domain.
- [ ] Firestore `(default)` in `asia-south1` (or document the actual region).
- [ ] Blaze plan for Functions (or approve the alternative architecture).
- [ ] Functions region aligned with `FUNCTIONS_REGION` (currently defaults to `us-central1`).
- [ ] Secret `OM_PAYMENT_GATEWAY` (only if online payments are in scope).
- [ ] Hosting site, custom domain, SSL, redirects.
- [ ] Budget alerts, usage limits, App Check (if adopted).
- [ ] Backups/PITR and a restore drill.

### 4. Missing indexes

- [ ] Product index families 1–18 in §C5 (roughly 20–25 definitions).
- [ ] Order queue combinations (delivery mode, customer + status/payment status).
- [ ] Audit `actorUid` combinations.
- [ ] Verify via a staging deployment that no query returns an index-creation link.

### 5. Missing data/setup documents

- [ ] Production `store_settings/store` (shop name, tax, shipping zones, payment method maps, policies).
- [ ] At least one active category/product/variant set for a smoke test.
- [ ] `counters/order-YYYY-MM` creation is automatic once F-04 is fixed.
- [ ] Coupons in the shape the client and server both read (`endsAt`, map-shaped payment methods in settings).

### 6. Missing billing or external-service decisions

- [ ] Blaze vs Supabase Edge Functions.
- [ ] Supabase Storage project + bucket + policies (recommended) vs Firebase Storage.
- [ ] Payment gateway and webhook provider (Razorpay/Stripe/etc.) or COD-only launch.
- [ ] App Check rollout.
- [ ] Guest order tracking requirement.

### 7. Missing automated tests

- [ ] Functions-emulator integration tests for coupon checkout, cancellation restore, wholesale approval, counter sale, refunds.
- [ ] Auth reload/session restore UI test.
- [ ] Index-canary test against a staging project (cannot be done in the emulator).
- [ ] Media upload/gallery tests (once the server writer exists).
- [ ] Production-build token/scan test in CI.

### 8. Missing manual browser/real-flow tests

- [ ] Sign in → reload `/admin` and `/account` (must stay signed in).
- [ ] Retail catalog: every sort, category, shelf, search, tag, price range, wishlist.
- [ ] Guest and signed-in checkout with COD/pickup and COD/courier; coupon and no-coupon.
- [ ] Admin: product save → image upload → gallery save → storefront render.
- [ ] Cancel/return an order and verify stock restoration.
- [ ] Wholesale apply → approve → wholesale pricing visible.
- [ ] Payment mark/refund flow (manual) and online-payment decision.

---

## E. Blocker Register

| ID | Priority | Description | Evidence | User impact | Exact fix | Dependencies | Approval / prod access |
|---|---|---|---|---|---|---|---|
| P0-1 | P0 | Production environment not wired; reported Spark blocks Functions | `.firebaserc:1-5`; no production defines; owner-side record (not re-verified); `docs/backend-setup.md:39` | Nothing can deploy; trusted backend cannot run | Re-confirm project/plan; upgrade to Blaze or approve Edge migration; `firebase use`; create `.env.production.json`; add staging | Console + billing | Yes / Yes |
| P0-2 | P0 | Missing composite indexes for wholesale-aware storefront queries | §C5; `catalog_query_builder.dart:43`; `firestore.indexes.json` | Catalog/search/category/shelf pages error in production | Extend indexes, deploy to staging, exercise all shapes | Project + Blaze not required for indexes | Yes / Yes |
| P0-3 | P0 | Transaction ordering + counter defects | `index.js:376-381, 518-552, 957-962, 307-313`; fake tx `:13,292` | Coupons, cancellations, approvals fail; duplicate order numbers | Reorder reads/writes; persist counter; add emulator integration tests | None (local) | No / No |
| P0-4 | P0 | No shippable hosting build/pipeline | `build/web` demo bundle, 28 tokens; no CI | Deploying serves demo/broken SEO | Production build + token substitution + CI + smoke test | P0-1 | Yes / Yes |
| P0-5 | P0 | Media pipeline blocked/unprovisioned | `firestore.rules:395-397`; `media_uploader.dart:496-499`; `supabase_media_repository.dart:800-811`; no `supabase/` | Admins cannot upload/attach product images | Choose storage; add server writer + callable; provision bucket/RLS | Architecture decision | Yes / Yes |
| P1-1 | P1 | Auth session not restored on reload | `backend_binding.dart:44`; `firestore_auth_repository.dart:18-20`; `guards.dart:26-55` | Signed-in users bounced to login; admin reload logs out | Resolve/await auth at bootstrap or bind eagerly; reload test | None | No / No |
| P1-2 | P1 | Online payment not implemented | `index.js:609-638`; no webhook | Online orders stay pending forever | Implement gateway + webhook + secret, or launch COD-only | Provider decision | Yes / Yes |
| P1-3 | P1 | Order items lose money/category fields | `index.js:210-220,352`; `order.dart:88-109` | ₹0 line prices; wrong reports | Add fields to snapshot; migration/backfill for existing orders | None | No / No |
| P1-4 | P1 | Refund can exceed paid | `index.js:704-717` | Financial loss | Validate `amount ≤ paid − refunded` | None | No / No |
| P1-5 | P1 | Counter-order path invokes wrapper | `index.js:721-739` | Counter sales unavailable | Extract inner handler and call it; add test | P0-3 refactor | No / No |
| P1-6 | P1 | Functions tests mask transaction defects | `fake-firestore.js:13,292-293` | False confidence; regressions ship | Add Functions-emulator integration suite | Emulators (already available) | No / No |
| P1-7 | P1 | No staging environment | `.firebaserc`; no CI | Cannot verify indexes/Console/billing safely | Add staging project + defines | P0-1 | Yes / Yes |
| P2-1 | P2 | Console facts unverified (Auth provider, templates, region, domains, backups, plan) | No project selected | Unknown launch readiness | Manual Console checklist | Console | Yes / Yes |
| P2-2 | P2 | App Check absent | `pubspec.yaml` | Abuse/cost exposure | Decide and enable before traffic | P0-1 | Yes / Yes |
| P2-3 | P2 | Storage rules dead/mismatched claims | `storage.rules:11-15`; `index.js:988-990` | Latent if Storage is enabled | Remove or align with doc-based roles | Media decision | No / No |
| P2-4 | P2 | Seed data invalid for checkout | `seed_local_store.mjs:165`; `store_settings.dart:218`; `om_doc.dart:47-56` | Local demo cannot choose payment/deliver courier | Fix seed shape; reseed | None | No / No |
| P2-5 | P2 | Hygiene test conflicts with `firebase use` | `security_hygiene_test.dart:134-153` | Correct local setup breaks tests | Choose alias policy; gitignore local `.firebaserc` or allow aliases | None | No / No |
| P2-6 | P2 | No email verification; reset action URL unset | `firestore_auth_repository.dart:143-149`; no verification code | Account trust/UX | Add verification + `ActionCodeSettings`; configure templates | Console | Yes / Yes |
| P3-1 | P3 | `.firebaserc` comment references non-existent command; strict config BOM; `mediaOptimise` dead code | `.firebaserc:1`; `firebase.local.strict.json:1`; `media_optimise_gateway.dart:104` | Confusion/latent failure | Clean up when touching these files | None | No / No |
| P3-2 | P3 | Guest order lookup / `orderByIdempotency` unused | No client call; export exists | Product gap if tracking is required | Decide; implement callable + route if needed | Product decision | Yes / Yes |

---

## F. Production Readiness Checklist

| Area | Status | Note |
|---|---|---|
| Firebase project + web app | ❌ | Placeholder alias, no verified registration |
| Auth email/password enabled | ❓ | Console unverified |
| Authorized domains / templates | ❓ | Console unverified |
| Email verification | ❌ | Not implemented |
| Password reset end-to-end | ⚠️ | Code exists; action URL/template unverified |
| Session persistence across reload | ❌ | P1-1 |
| Firestore `(default)` + region | ❓ | Console unverified |
| `store_settings/store` | ❓ | No production doc verified |
| Security rules deployed | ❌ | Not deployed; locally verified |
| Rules test suite | ✅ | 39/39 emulator tests |
| Composite indexes deployed | ❌ | Incomplete and not deployed |
| Functions deployed on Blaze | ❌ | Not deployed; Blaze unverified |
| Functions transactional correctness | ❌ | P0-3 |
| Order numbering | ❌ | Counter never persists |
| Coupon checkout | ❌ | Read-after-write |
| Cancellation/return stock restore | ❌ | Read-after-write |
| Wholesale approval | ❌ | Read-after-write |
| Counter sale | ❌ | Wrapper invocation |
| Refund integrity | ❌ | Cumulative over-refund |
| Payments (COD/manual) | ⚠️ | Manual mark works; no gateway |
| Payments (online) | ❌ | No webhook/gateway |
| Admin authorization | ✅ (rules/design) | Roles server-minted; rules tested; claims dead |
| Media upload/gallery | ❌ | P0-5 |
| Storage bucket/policies | ❌ | Unprovisioned |
| FCM / notifications | ➖ | Firestore in-app only; no push |
| Analytics / Crashlytics / Remote Config / Performance | ➖ | Not used |
| App Check | ❌ | Missing |
| Hosting artifact | ❌ | Demo bundle + tokens |
| CI/CD | ❌ | None |
| Custom domain / SSL / redirects | ❓ | Console unverified |
| Backups / PITR / restore drill | ❓ | Unverified |
| Budget alerts / quotas | ❓ | Unverified |
| Source-map/secret exposure | ✅ (artifact scan) | No real keys/service-role in build; no Admin SDK in client |
| Smoke test on staging | ❌ | No staging |

Legend: ✅ verified · ⚠️ partial · ❌ missing/failing · ❓ not verified · ➖ not used.

---

## G. Verified Test Results

All commands below were executed in this audit from `D:\event_shop` (or `functions/`) unless marked otherwise.

| # | Command | Actual result | Interpretation |
|---|---|---|---|
| 1 | `sha256sum firestore.rules` + `wc -l` | `b5d8542dcf78d96e719b20362dd829202bed7f8075609a5b887fd216a44a285d`, 418 lines | Current candidate matches the previously reported hash |
| 2 | `node --test scripts/local/rules/security_rules.test.mjs` | **39 tests, 39 pass, 0 fail, 0 skipped**, ~2.2 s | Real emulator rules, real Auth tokens; default-deny/roles/blocked/query-shape coverage |
| 3 | `cd functions && npm test` | **104 tests, 104 pass, 0 fail, 0 skipped**, ~0.35 s | Unit tests only; fake Firestore (`test/support/fake-firestore.js`) |
| 4 | `node --check` on `index.js`, `lib/*.js`, `scripts/*.js` | All 8 files OK | Syntax only |
| 5 | `~/fvm/versions/3.44.6/bin/flutter analyze` | **No issues found!** (95 s) | Clean analyzer at the pinned SDK |
| 6 | `~/fvm/versions/3.44.6/bin/flutter test` | **256 passed, 7 skipped**, ~10 s | Full Flutter suite passes |
| 7 | Emulator probes | Firestore 8080 → 200; Auth 9099 → 200; Functions 5001 → 404 at root (running); UI reports `demo-om-events` | Correct local project; no production contact |
| 8 | Config JSON parse | `.firebaserc`, `firebase.json`, `firebase.local.json`, `firestore.indexes.json` OK; `firebase.local.strict.json` fails strict parse due to BOM | CLI tolerance inferred from running emulator; not restarted |
| 9 | Build artifact scan | `AIza` → 0; `service_role` → 0; `sb_secret` → 0; `demo-om-events` → 3; tokens index/robots/sitemap = 11/3/14 | Demo bundle, no real key, unresolved SEO tokens |
| 10 | Repository searches | No `guestOrderLookup`; no `mediaOptimise` export; no `onSchedule`; `counterRef` read only; 3 read-after-write sites | Static evidence for §C6 |

### Claims checked and rejected/downgraded

- **“Coupon ids/fields break quoting”** — quoting is by the `code` field (`index.js` coupon lookup), so seeded lowercase document ids are harmless; expiry uses `endsAt` consistently in the model and admin save. Only the seed's `expiresAt` and null value are inconsistent → downgraded to P3/local seed.
- **“Coupon usage limits are unenforced”** — false. `functions/lib/checkout.js:28-38` enforces `usageLimit`, and `coupon_windows.test.js:114-117` covers it; per-user limits are enforced inside the transaction (`index.js:257-260`).
- **“`mediaOptimise` missing breaks uploads”** — the callable is indeed absent, but no live path constructs `CallableMediaOptimiseGateway` (the uploader defaults to a passthrough). Uploads fail earlier at the `media_objects` write. Downgraded to P2 dead code.
- **“Session restoration is broken”** — confirmed as a code-path defect, but not reproduced in a browser during this audit; no runtime claim is made.

### Not run (and why)

- Functions-emulator integration tests that would prove F-01/F-02/F-03/F-05 (would require writing checkout fixtures to the local emulator; reserved for the remediation phase).
- Browser reload test for auth persistence (no browser flow executed in this audit).
- Any production check: project identity, plan, Auth providers/domains/templates, Firestore region, indexes, Functions deployment, Storage, Hosting, backups, billing.
- `firebase deploy` of any kind, index creation, secret creation, DNS/domain changes.

---

## H. Remaining Work Roadmap

### Phase 1 — Configuration and security blockers (before any deploy)

| Task | Complexity |
|---|---|
| Confirm/create production project + web app; set local alias; create `.env.production.json` | Small |
| Fix auth bootstrap/session hydration; add reload test | Small |
| Fix transaction ordering (F-01/02/03), counter (F-04), refund (F-07) | Medium |
| Add Functions-emulator integration tests for the fixed paths | Medium |
| Add the missing product/order/audit indexes to `firestore.indexes.json` | Medium |
| Decide App Check; align Storage/claims or remove dead config | Small–Medium |

### Phase 2 — Backend and data integrity

| Task | Complexity |
|---|---|
| Refactor `ordersCreate` into a shared handler; fix `adminCounterOrder` (F-05) | Medium |
| Add order-item money/category fields + backfill plan (F-06) | Medium |
| Implement/decide payments: gateway + webhook + secret, or COD-only launch (F-08) | Large |
| Media architecture: Supabase bucket/RLS + server writer + gallery callable (P0-5) | Large |
| Fix seed shape; add a checkout-ready fixture (P2-4) | Small |
| Resolve guest lookup / `orderByIdempotency` decision (P3-2) | Small–Medium |

### Phase 3 — Checkout and real-world application flows

| Task | Complexity |
|---|---|
| Staging deploy of rules + indexes + Functions; exercise all index shapes | Medium |
| E2E: guest/signed-in COD pickup + courier; coupon/no coupon; cancel/return | Medium |
| E2E admin: product → image → gallery → storefront; wholesale approve; refunds | Medium |
| Verify order numbering, stock, coupons and reports in staging | Small |
| Browser coverage for auth reload and guarded routes | Small |

### Phase 4 — Hosting, monitoring and operational readiness

| Task | Complexity |
|---|---|
| Production build script: defines, token substitution, fail-on-token, smoke test | Medium |
| CI pipeline with analyzer/tests/rules/Functions tests/build scan | Medium |
| Custom domain/SSL/redirects; security headers; App Check/budget alerts | Small–Medium |
| Backups/PITR + restore drill; logging/alerts for function errors | Medium |

### Phase 5 — Deployment preparation (pending explicit approval)

| Task | Complexity |
|---|---|
| Deploy rules/indexes/functions/hosting to staging, then production in a reviewed window | Medium (process risk, not code risk) |
| Post-deploy smoke matrix and rollback plan | Small–Medium |
| Record Console evidence and sign-off | Small |

---

## I. Completion Percentage

Scores count only evidence-backed work; unverified Console items score zero.

| Area | Weight | Score | Basis |
|---|---|---|---|
| Local code/configuration | 20 % | 65 % | App, repositories, env wiring, callables, rules, tests exist; production defines/artifact missing; media path broken; seed drift; docs/tests conflict |
| Security verification | 20 % | 55 % | Rules 39/39 + compile pass; no production deploy; no Storage tests; Functions security not integration-tested; App Check absent; claims dead |
| Backend functionality | 25 % | 40 % | 42 exports + 104 unit tests, but P0 order/coupon/cancel defects, counter, refund, counter-sale, payments, media writer |
| Production infrastructure | 20 % | 10 % | No configured project, no index/function/hosting deploy, no Auth/region/backups/plan verification; only config files exist |
| End-to-end application flows | 15 % | 30 % | Browse/cart/catalog verified locally on 2026-10-19; checkout with real Functions, admin media, auth reload and payments unproven |
| **Overall production readiness** | **100 %** | **≈40 %** | Weighted sum: 13.0 + 11.0 + 10.0 + 2.0 + 4.5 = **40.5 %** |

**Interpretation:** the local codebase is a substantial, well-tested implementation; the *production system* is not configured or proven. The 40 % should not be read as “40 % of the code is finished” — it is a readiness blend that heavily penalizes the absent production environment and the P0 defects.

By area, if you want single numbers: **local code ≈65 %**, **security verification ≈55 %**, **backend functionality ≈40 %**, **production infrastructure ≈10 %**, **E2E flows ≈30 %**.

---

## J. Exact Next Steps (in order)

1. **Manual — Firebase Console + local alias (P0-1).**
   Re-confirm the owner-side project facts for `om-events-store`: Web app registration, Email/Password, authorized domains, Firestore `asia-south1`/`(default)` and — decisively — the billing plan. The project is recorded as **Spark**, which cannot deploy Functions; either upgrade to Blaze or approve the Edge Functions migration before anything else. Then run `firebase use --add` locally and create `.env.production.json` from `.env.example` (never commit it). Record the answers as evidence.
2. **Local code — fix the order transaction defects (P0-3).**
   In `functions/index.js`, read the redemption doc before any write (reuse the read at `:257`), read all stock docs before writing history/items, read the user before updating the application, and write the counter with `tx.set`. Validate refunds against `paid − refunded`. Add Functions-emulator tests for coupon checkout, cancellation and wholesale approval; run them against `demo-om-events`.
3. **Local code — complete the index file (P0-2).**
   Add the wholesale-aware product families in §C5 (category, shelves, price/sold/rating sorts, suggestions, keywords, tags, wishlist) and the order/audit combinations. Add a checklist mapping each query shape to an index; plan a staging deployment to verify (emulator cannot).
4. **Decision + local code — media architecture (P0-5).**
   Choose Supabase Storage (recommended) or Firebase Storage; implement a trusted writer for `media_objects` and product `images` (callable or Edge Function), provision the bucket and RLS from committed SQL, and fix the gallery commit path. Add tests; do not re-open client writes.
5. **Local + CI — production build and auth bootstrap (P0-4, P1-1).**
   Resolve/auth-await `AuthRepository` before `runApp`; add a reload test. Add a build script that passes production defines, substitutes `SITE_ORIGIN` and fails if any token remains, runs analyzer/tests/build scan, and emits an artifact suitable for a staging smoke test. Deploy only after explicit approval.

**Can be done entirely locally without touching production:** steps 2, 3 (file edits + emulator tests; index *verification* needs staging), 4 (code + SQL; bucket provisioning needs Supabase), 5 (build + auth fix). **Requires manual Console/external access:** project/app/Auth/billing facts, Blaze activation, Supabase project/bucket, and any deployment.

---

### Final statement

This audit found **no repo evidence that the production Firebase project is wired, and could not independently verify its Console state; indexes, Functions and Hosting are not deployed and not safe to launch**. It did find a strong local foundation: secure default-deny rules proven by 39 emulator tests, a clean analyzer, 256 Flutter tests, and 104 Functions unit tests. The gap is not “Firebase is missing”; it is that production configuration is absent and several real-Firestore transaction/index/media defects are hidden by emulator and fake-database tests. Do not deploy until the P0 items are fixed and verified on a staging project.
