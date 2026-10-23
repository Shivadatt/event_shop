# Run the store locally, with no cloud project

This is the demo path. It gives you a browsable storefront, a working cart and a real admin panel
without a Firebase project, a Supabase project, or a single real key. It is also the only way to run
the app before you have credentials — and it is explicitly **not** a staging environment: the local
rules are off, so nothing here proves that `firestore.rules` is correct.

## Why the emulator and not a project

`firebase-tools` 15 refuses to boot the Firestore emulator below JDK 21. This machine has JDK 17, so
the suite is pinned to `firebase-tools@13.35.1` through `npx`. That pin is in the commands below — do
not "upgrade" them to the globally installed 15.x, or the emulator exits with code 1 and you will be
hunting for a Dart bug that does not exist.

## 1 · Start the backends

```bash
cd functions && npm install && cd ..
FUNCTIONS_DISCOVERY_TIMEOUT=60 npx --yes firebase-tools@13.35.1 emulators:start \
  --config firebase.local.json --project demo-om-events \
  --only auth,firestore,functions
```

Wait for `All emulators ready!`. Auth is on 9099, Firestore on 8080, Functions on 5001, Emulator UI on http://127.0.0.1:4000.

`FUNCTIONS_DISCOVERY_TIMEOUT=60` is not optional here. The Functions emulator gives your source 10 seconds to export its callables by default; on this machine loading `functions/index.js` exceeds that, the log says `User code failed to load. Cannot determine backend specification. Timeout after 10000`, and the suite still reports "ready" with an **empty** function registry. Every callable then fails with `does not exist` — coupons return `internal`, and checkout and admin writes never run. If a callable reports that it does not exist, check the emulator log for that timeout before debugging Dart.

**Start the Functions emulator too.** Signing in is not just an Auth call: `_ensure` invokes the
`accountEnsure` callable to mint `users/{uid}`, and with 5001 closed the callable fails with
`ERR_CONNECTION_REFUSED`, the sign-in form shows its auth-failure caption and never navigates. The
`functions/node_modules` install is required for the same reason — the emulator runs your source, and
`firebase-admin` is not vendored.

If a previous run died badly it can leave a `java.exe` holding 8080, and the new emulator then exits
with code 1 while the log talks about "multiple instances". Check with
`netstat -ano | grep 8080` and kill that java process only after confirming its command line is
`cloud-firestore-emulator-*.jar`.

## 2 · Seed a catalogue

```bash
node scripts/local/seed_local_store.mjs
```

Ten products across four live categories (plus one inactive category and one `draft` product, so you
can prove hidden rows stay hidden), two coupons, `store_settings/store`, and two logins:

| Role | Email | Password |
| --- | --- | --- |
| admin | `admin@om-events.test` | `emulator-demo` |
| customer | `buyer@om-events.test` | `emulator-demo` |

The seed writes straight into the emulator over its REST endpoint. That is possible only because
`firebase.local.json` deliberately declares **no** `rules` key, which makes the emulator log
`The emulator will default to allowing all reads and writes`. Under the real `firestore.rules`, every
one of those writes is rejected — user documents are minted by `accountEnsure`, and product, coupon
and settings writes are function-only. The seed also leaves `images: []` on every product: Firestore
may hold media metadata but never bytes, the bytes belong in Supabase Storage, and there is no
Supabase project behind a local demo, so a made-up CDN URL would only render a broken image.

Prices are integer paise with real quantity bands, so the slab engine has something to compute:
`11" Latex Balloon` is ₹450 at 1 pack, ₹420 from 5, ₹390 from 10.

## 3 · Run the app against it

```bash
fvm.bat flutter run -d web-server --web-port 5000 \
  --dart-define=OM_USE_EMULATORS=true
```

`OM_USE_EMULATORS=true` is the only switch you need. `Env` fills in placeholder Firebase options
(`localhost-emulator-not-a-real-key`, `demo-om-events`) and `AppBootstrap` points Firestore at
`localhost:8080` with `sslEnabled: false`, Auth at `localhost:9099`, and Cloud Functions at
`localhost:5001`. The placeholders are worded so they cannot be confused with credentials, and they
are never sent anywhere but loopback. Override the ports with `OM_FIRESTORE_EMULATOR_PORT`,
`OM_AUTH_EMULATOR_PORT`, `OM_FUNCTIONS_EMULATOR_PORT` if something else has them.

Open http://localhost:5000.

### Known caveat: a stored session can outrun the emulator switch

Once you have signed in, the browser keeps a Firebase session in IndexedDB
(`firebaseLocalStorageDb`). On the next hard reload the Auth SDK restores it — firing
`accounts:lookup` — before `AppBootstrap` has applied `useAuthEmulator`, and from then on that page
instance sends its auth calls to `https://identitytoolkit.googleapis.com` and gets HTTP 400. The
first frame of the app looks fine and the storefront still reads from the Firestore emulator, so the
symptom is confusing: only sign-in breaks.

Workaround while it is unfixed: clear the site's storage (DevTools → Application → Storage → Clear
site data), or use a fresh browser profile. The underlying ordering problem — `FirebaseAuth.instance`
must not be touched before the emulator host is set — is a real defect, tracked here rather than
papered over.

## 4 · Prove it

`test/integration/emulator_smoke_test.dart` runs the real web Firebase SDK in headless Chrome against
the emulator you just seeded, and finishes by mounting the actual app and asserting a seeded product
reaches the home shelf. It self-skips without `--platform chrome --dart-define=OM_USE_EMULATORS=true`,
so a normal `flutter test` never depends on your emulator being up.

```bash
CHROME_EXECUTABLE="C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" \
fvm.bat flutter test --platform chrome --dart-define=OM_USE_EMULATORS=true test/integration/
```

It reads the seed literally: 9 active products, 4 live categories, `store_settings/store`, the two
demo logins and their roles. Change the seed and this test goes red on purpose.

## What works and what does not

| Flow | Status |
| --- | --- |
| Catalogue, search, category pages, product page with slab pricing | works |
| Cart, quantity bands, coupon codes, checkout total | works |
| Placing an order | needs the Functions emulator (see below) |
| Admin panel, browsing and editing | works once you log in as the demo admin |
| Product images | shows placeholders — no Supabase project |
| Anything asserting `firestore.rules` denies a write | **not testable here** |

To exercise checkout and every admin write, add Functions:

```bash
npm --prefix functions install
FUNCTIONS_DISCOVERY_TIMEOUT=60 npx --yes firebase-tools@13.35.1 emulators:start \
  --config firebase.local.json --project demo-om-events --only auth,firestore,functions
```

The emulator runs `functions/index.js` locally, so the same `requireRole` guard that protects
production decides whether your demo session may write. That guard reads the `users/{uid}` document,
which is why the seed sets `role: admin` on the admin login. `OM_PAYMENT_GATEWAY` is declared as a
secret environment variable, so online payment capture stays unavailable; cash-on-delivery and the
counter order path still work.

## Shutting down

Ctrl-C the emulator process. `demo-om-events` data lives only in memory unless you pass
`--export-on-exit ./tmp/emulator_data` and `--import ./tmp/emulator_data` on the next start.
