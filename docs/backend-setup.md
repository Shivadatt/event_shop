# Backend setup — Firebase Auth, Cloud Firestore, Cloud Functions

This document is the **operator runbook** for wiring the live backend that `lib/…/firestore/**`,
`firestore.rules` and `functions/**` expect. Nothing here contains a real credential: every secret is
a `<PASTE_FROM_CONSOLE>` placeholder and every project id is templated. **You must not commit a real
key, service-account JSON, or project id** into the repository, into `lib/**`, or into anything that
reaches the browser bundle.

> STATUS: The rules and functions in this repo are **UNVERIFIED against a live project** — no Firebase
> project or credentials are configured, so none of them have been executed or deployed. This guide is
> the path to make that verification happen.

---

## 0. What is already in place (do not edit these to add keys)

| File | Role |
| --- | --- |
| `lib/app/core/env.dart` | Reads `--dart-define` values. Defaults are **empty** so an unconfigured build fails loudly. |
| `lib/app/core/services/app_bootstrap.dart` | Calls `Firebase.initializeApp`, enables Firestore offline persistence, builds `FirebaseFunctions.instanceFor(region:)`. |
| `lib/app/core/services/firebase/firebase_backend.dart` | The ONLY file that touches Firebase SDK objects; maps every `FirebaseException`/`FirebaseFunctionsException` to an `OmFailure`. |
| `lib/app/bindings/backend_binding.dart` | Binds the Firestore repos when `Env.hasFirebase`, else throw-only unconfigured repos. |
| `functions/**` | Node 20, `firebase-functions` v2, CommonJS. Reads credentials from the runtime only. |
| `firestore.rules` / `firestore.indexes.json` / `storage.rules` / `firebase.json` | Deployed as-is; project id is templated. |

`Env.hasFirebase` is true only when **all three** of `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`,
`FIREBASE_APP_ID` are non-empty. Until then `main.dart` renders the setup page and the binding wires
the unconfigured repositories — the app never shows invented merchandise.

---

## 1. Create the Firebase project

1. Create a project in the [Firebase console](https://console.firebase.google.com). Note its **project id** — this is `FIREBASE_PROJECT_ID`. Use the same id for Firestore, Auth, Functions and Hosting.
2. Add a **Web app** to the project. Copy its `apiKey`, `appId`, `authDomain`, `storageBucket`,
   `messagingSenderId`, (optional) `measurementId`.
3. Enable **Authentication → Email/Password**. (This is the only provider the repositories use.)
4. Enable **Cloud Firestore** (production mode, pick the same region as Functions below).
5. Enable **Cloud Functions** (requires the Blaze plan).

There is deliberately **no service-account key in the client**. The Admin SDK used by Cloud Functions
authenticates via the Functions runtime's Application Default Credentials — see §4.

---

## 2. Point the Firebase CLI at the project

`.firebaserc` ships a templated placeholder:

```jsonc
{ "projects": { "default": "REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID" } }
```

Generate it from the real id **locally** (never commit the result to a shared branch unless the team
agrees the project id is safe to share — a project id is not a secret, but keep it consistent):

```bash
firebase login
firebase projects:list                       # confirm your project is visible
# Either edit .firebaserc by hand, or:
firebase use --add                           # pick the project, name it "default"
```

`firebase.json` references `firestore.rules`, `firestore.indexes.json`, `storage.rules`, the
`functions/` source, and hosting on `build/web`. Its `//` comment explains why the project id stays
templated.

---

## 3. Build-time client configuration (`--dart-define`)

These values are **public by design** (they are the same values embedded in any web app's Firebase
config). They are NOT secrets. Do not paste a service-role key or any private credential here.

```bash
fvm flutter build web \
  --dart-define=FIREBASE_API_KEY=<PASTE_FROM_CONSOLE> \
  --dart-define=FIREBASE_PROJECT_ID=<PASTE_FROM_CONSOLE> \
  --dart-define=FIREBASE_APP_ID=<PASTE_FROM_CONSOLE> \
  --dart-define=FIREBASE_AUTH_DOMAIN=<PASTE_FROM_CONSOLE> \
  --dart-define=FIREBASE_STORAGE_BUCKET=<PASTE_FROM_CONSOLE> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<PASTE_FROM_CONSOLE> \
  --dart-define=FUNCTIONS_REGION=us-central1 \
  --dart-define=SUPABASE_URL=<PASTE_FROM_CONSOLE> \
  --dart-define=SUPABASE_ANON_KEY=<PASTE_FROM_CONSOLE> \
  --dart-define=SUPABASE_MEDIA_BUCKET=om-events-media \
  --dart-define=SITE_URL=https://your-domain.example
```

`FUNCTIONS_REGION` MUST match the region the functions are deployed in (§5), or every callable fails.
`SUPABASE_*` belong to the media layer (Agent 4) and are listed only so one command configures both.

> **`hasServiceRoleKeyInClient` guard**: `Env` reads `SUPABASE_SERVICE_ROLE_KEY` only to assert that
> no build accidentally embedded it. Never pass that define to a web build.

---

## 4. Functions runtime configuration (server-side, NOT in the bundle)

`functions/lib/server.js` reads three environment values at runtime. Provide them through a
**`functions/.env`** file (loaded by the Firebase CLI for gen-2 functions) and the Secret Manager for
secrets. `functions/.env` must be git-ignored.

```dotenv
# functions/.env  (server-only — never shipped to the browser)
OM_FUNCTIONS_REGION=us-central1
# Tolerance (paise) between the browser's total and the server-recomputed total before
# ordersCreate rejects with PRICE_CHANGED. 100 paise covers display rounding only, not real drift.
OM_PRICE_EPSILON_PAISE=100
```

`OM_PAYMENT_GATEWAY` is declared a **secret** in `firebase.json → functions[].secretEnvironmentVariables`.
Until it is set, `paymentsConfirm` refuses honestly and online orders are saved as `pending` (the
create path surfaces `message: "Online payment is not configured yet…"`). Set it once you have a
gateway:

```bash
firebase functions:secrets:set OM_PAYMENT_GATEWAY   # paste the value from the gateway console
```

The Admin SDK itself needs **no** key file: `admin.initializeApp()` with no arguments picks up the
Functions runtime's ADC. Do not add a `serviceAccount` path anywhere in `functions/` or `lib/`.

---

## 5. Deploy rules, indexes and functions

```bash
cd functions && npm ci && cd ..          # firebase-admin + firebase-functions, pinned in package.json
firebase deploy --only firestore:rules,firestore:indexes,functions,storage
```

Region check: functions are created with `setGlobalOptions({ region: REGION })` where
`REGION = OM_FUNCTIONS_REGION`. If you change the region, redeploy **and** rebuild the client with the
matching `FUNCTIONS_REGION`.

Emulator (optional, local only):

```bash
firebase emulators:start   # ports are pinned in firebase.json; Firestore + Auth + Functions + Hosting
```

---

## 6. Seeding the singleton documents

Some functions read a document that must exist before the store behaves correctly:

- `store_settings/store` — tax mode, `taxRateBps` (18% = `1800`), `invoicePrefix`, shipping zones,
  `allowGuestCheckout`. `functions/lib/server.js` falls back to `{}` (tax 0, pickup allowed) if it is
  missing, and the Dart `StoreSettings.fallback` mirrors that. Create it from the admin Settings screen
  (calls `adminSettingsSave`) or seed it in the console.
- `counters/order-YYYY-MM` — minted automatically on first order; do not pre-create.
- The first **owner** user: sign up in the app (which runs `accountEnsure` → role `customer`), then in
  the Firestore console set `users/<uid>.role = "owner"`. Roles are document-authoritative; custom
  claims are only an advisory mirror.

---

## 7. Pricing parity gate (run before trusting any price)

Three independent checks pin the pricing engine down:

1. `test/pricing_engine_test.dart` — unit tests the Dart engine directly.
2. `test/backend_pricing_parity_test.dart` — loads `test/data/slab_fixtures.json` and asserts the
   **Dart** engine reproduces every fixture case (headline numbers included: slabs 1-9@11000,
   10-20@10000, 21+@9500 → qty 1→11000, 10→100000, 20→200000, 21→199500).
3. `functions/scripts/check_pricing_fixtures.js` — loads the **same** fixture and runs
   `functions/lib/pricing.js` over it.

Because both engines are checked against one independent fixture, Dart == JS == fixture. Run all three
before deploying:

```bash
# Node parity check (run in the functions directory):
cd functions && npm ci && node scripts/check_pricing_fixtures.js   # exits non-zero on any mismatch

# Dart parity check (run from the repo root):
fvm flutter test test/backend_pricing_parity_test.dart test/pricing_engine_test.dart
```

`functions/lib/pricing.js` is a deliberate mirror of `lib/data/pricing/pricing_engine.dart`; if you
change one, change the other and re-run the fixture.

---

## 8. What is intentionally public-write (the only two, both field-allow-listed)

`firestore.rules` contains **no** `allow write: if true`. The only two client writes are:

1. **`wholesale_applications/{id}` create** — a signed-in, non-blocked user may create exactly one,
   with `status == "pending"`, a fixed field allow-list, and size caps. The `onWholesaleApplicationCreated`
   trigger flips the applicant's profile to `pending`. A client can never approve itself.
2. **`support_requests/{id}` create + owner reply** — create is `status == "open"`, `messages` capped
   at 1 with `isStaff == false`; a reply may only append non-staff messages and move among the
   open-family statuses. Staff resolution runs through `adminSupportUpdate`.

Everything else — prices, slabs, cost, stock balances, role, wholesale approval, order/payment status,
coupon definitions, review status, counters, idempotency keys — is written **only** by Cloud Functions,
which re-verify the caller's role from `users/{uid}` and write an `audit_logs` row.

---

## 9. Rollback / re-deploy

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only functions
```

If you rotate `OM_PAYMENT_GATEWAY`, run `firebase functions:secrets:set OM_PAYMENT_GATEWAY` again and
redeploy functions so the new version binds to it.
