# Firebase + Supabase Configuration Forensic Audit

**Project:** `D:\event_shop` — OM Events And Decorators
**Date:** 2026-10-22
**Scope:** read-only audit of whether Firebase and Supabase are actually configured and connected. No implementation, deployment, migration, Console, billing, or cloud write was performed.
**Method:** repository inspection with five read-only subagents covering disjoint areas, followed by independent verification of every load-bearing claim (paths, counts, project identifiers, build artifacts, call chains).

### Status legend (used exactly as required)

- `VERIFIED — CONFIGURED`
- `PARTIAL — CODE EXISTS, SETUP INCOMPLETE`
- `MISSING — NO IMPLEMENTATION FOUND`
- `PLACEHOLDER — NOT A REAL CONFIGURATION`
- `NOT VERIFIED — REQUIRES DASHBOARD OR ENVIRONMENT ACCESS`
- `NOT USED — NO CURRENT CALL PATH`
- `CONFLICT — CONFIGURATION DOES NOT MATCH CODE`

---

## A. Executive verdict

| Question | Answer | Status |
|---|---|---|
| Is Firebase configured in the code? | Yes, substantially: Auth, Firestore, callables and emulator switching are fully wired. No production project or client values are present. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |
| Is Firebase production connected and verified? | No. `.firebaserc` is a placeholder; no production `--dart-define` file exists; no deployment evidence exists; Console state was not read. | `NOT VERIFIED — REQUIRES DASHBOARD OR ENVIRONMENT ACCESS` |
| Is Supabase configured in the code? | Yes for media storage: SDK dependency, gated `Supabase.initialize()`, upload/move/remove/public-URL code and a Firestore media ledger exist. No real URL or key is present anywhere in the repository. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |
| Is a Supabase project confirmed to exist for this application? | No. A local CLI link cache names a project, but it is not read by the app and cannot be tied to any project in the owner's screenshot. Bucket, policies and reachability are unverified. | `NOT VERIFIED — REQUIRES DASHBOARD OR ENVIRONMENT ACCESS` |
| Which backend actually handles each feature? | Firebase Auth + Firestore + Cloud Functions for application logic; Supabase Storage for image bytes; Firestore for the media ledger; browser memory for the cart. No Supabase database or Edge Function is used. | See §D |
| Is the application production-ready? | No. Neither production backend is configured or verified in this repository, the current `build/web` hosting artifact targets local emulators, and the media pipeline is blocked by a rules/code conflict. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` overall |

**Direct answer to the audit question:** in production terms, **neither a configured and usable Firebase backend nor a configured and usable Supabase backend is established by the repository**. Both integrations are substantially written, but only the Firebase **local emulator** path is demonstrably runnable; production remains unconfigured and unverified.

**Severity of the blocking findings:**

- **P0** — No production Firebase project is pinned or deployed; if the prior Spark note is confirmed, Cloud Functions cannot deploy at all.
- **P0** — Media uploads cannot complete in production: the ledger write that must precede the byte transfer is denied by `firestore.rules`.
- **P1** — No Supabase project/bucket or client values are confirmed, and no production build exists.
- **P1** — Guest order detail lookup fails closed; server-side media optimisation is absent.
- **P2** — Product saves can omit failed images; the visibility lookup can persist a wrong URL; documentation and code disagree about empty defaults.
- **P3** — Unresolved SEO origin tokens in the build and an unignored `supabase/.temp` CLI cache.

---

## B. Service inventory

| Service | Evidence | Status |
|---|---|---|
| Firebase Auth | `firebase_auth` dependency (`pubspec.yaml:38-42`); initialization (`lib/app/core/services/app_bootstrap.dart:57-76`); email/password, sign-up and reset calls (`lib/data/repositories/firestore/firestore_auth_repository.dart:92,109,143`); provider configuration is external. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |
| Firestore | `cloud_firestore` dependency; collections and repositories under `lib/data/repositories/firestore/**`; rules and indexes files exist (`firestore.rules`, `firestore.indexes.json`). No deployment evidence. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |
| Cloud Functions | 39 callable exports and 3 Firestore triggers in `functions/index.js` (callables begin `:95`; triggers at `:1585,:1596,:1612`). Runtime Node 20 and region `us-central1` (`firebase.json:10-26`, `functions/lib/server.js:28`). No `.firebase/` deploy cache, no CI deploy, no release log. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |
| Firebase Storage | Firebase Hosting/Storage config exists (`firebase.json:6-9`, `storage.rules`), but there is no `firebase_storage` dependency and no `FirebaseStorage`/`getDownloadURL` call in `lib/**`. `storage.rules:3-7` explicitly states Firebase Storage is not the media home. | `NOT USED — NO CURRENT CALL PATH` |
| Supabase initialization | `supabase_flutter` is declared (`pubspec.yaml:42`) and initialized only when both defines are non-empty (`lib/app/core/services/app_bootstrap.dart:118-127`; `Env.hasSupabase` at `lib/app/core/env.dart:70`). | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |
| Supabase database | No PostgREST query, insert, update or `rpc` call was found. The system of record is Firestore. | `NOT USED — NO CURRENT CALL PATH` |
| Supabase Storage | Real storage calls exist (`lib/app/core/services/media/supabase_storage_service.dart:215,250,272,297,322,401`) and are invoked by the uploader (`media_uploader.dart:502,549`). No configured bucket or project. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |
| Supabase Edge Functions | No `functions.invoke` call and no `supabase/functions/` directory. The only “optimise” call is a Firebase callable that does not exist in `functions/index.js`. | `MISSING — NO IMPLEMENTATION FOUND` |
| Local emulators | `firebase.local.json:2` (permissive demo config), `firebase.local.strict.json:2` (strict rules), `firebase.integration.json:2` (integration, “Never deploy”); `OM_USE_EMULATORS` switches Auth/Firestore/Functions to localhost (`lib/app/core/env.dart:17-41`, `app_bootstrap.dart:102-109`). Historical run log exists (`build_logs/emulator_run.log`), but the emulator was not restarted during this audit. | `VERIFIED — CONFIGURED` (local only) |
| Hosting | `firebase.json:27-47` points at `build/web`; the existing `build/web` is an emulator build, untracked/gitignored, with unresolved SEO tokens. No deployment evidence. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` |

---

## C. Actual configuration map

| Source | What it contains | Status | Implication |
|---|---|---|---|
| `.firebaserc:4` | `default = REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID` only. | `PLACEHOLDER — NOT A REAL CONFIGURATION` | `firebase deploy` cannot target a real project unless an owner runs `firebase use --add`. |
| `firebase.json:2` | Explicitly states the project id is templated and `.firebaserc` is generated during setup. Functions/hosting/emulator config is otherwise concrete. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Deployment topology is defined; the target is not. |
| `firebase.local.json`, `firebase.local.strict.json`, `firebase.integration.json` | Local-only emulator configs. `firebase.local.json` deliberately omits `firestore.rules`, so the emulator runs with permissive defaults; the other two are local test configs. | `VERIFIED — CONFIGURED` (local only, never deployable) | Local success cannot be treated as production-rule success. |
| `.env.example` | All Firebase and Supabase values are empty (`:18-30`). Non-secret defaults only: `SUPABASE_MEDIA_BUCKET=om-events-media`, `FUNCTIONS_REGION=us-central1`, `SITE_URL` placeholder, `CURRENCY=INR`. | `PLACEHOLDER — NOT A REAL CONFIGURATION` | It is a template, not a runtime configuration; the app does not load `.env` files automatically. |
| `.env.production.json` | Absent. Referenced by `README.md:31,65`. | `MISSING — NO IMPLEMENTATION FOUND` | No in-repo production client values exist. External build-time defines could exist but are not verifiable from this repository. |
| `functions/.env` | Absent. `.gitignore:54` excludes it. `OM_FUNCTIONS_REGION` and `OM_PRICE_EPSILON_PAISE` are read at `functions/lib/server.js:28,32`. | `MISSING — NO IMPLEMENTATION FOUND` | Backend runtime uses defaults; the payment-gateway secret declared in `firebase.json:22-24` has no local value. |
| `lib/app/core/env.dart` | Firebase/Supabase values come only from `String.fromEnvironment` (`:9-11`, `:48-49`); emulator mode defaults off (`:17`); demo placeholders apply only in emulator mode (`:20-30`). Non-empty defaults exist for media bucket, function region, site URL and currency (`:50-56`). There is no generated `lib/firebase_options.dart`; `FirebaseOptions` is constructed at runtime from these defines (`app_bootstrap.dart:57-76`). | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | A production build must supply values; an emulator build works without them. |
| `build/web/` | Built 2026-10-19 15:08; contains `demo-om-events` (3 occurrences), one `firebaseapp.com`, one `appspot.com`, zero `AIza` keys, zero `supabase.co` URLs, and the local emulator placeholder key/app id. `build/web/index.html` still has 11 unresolved `{{SITE_ORIGIN}}` tokens. | `PLACEHOLDER — NOT A REAL CONFIGURATION` | This is an emulator-only build, not production evidence. The placeholder key/app id can only be emitted when `OM_USE_EMULATORS` is true (`env.dart:20-30`), so the artifact was compiled in emulator mode. |
| `supabase/.temp/linked-project.json` | Local CLI link cache: project ref `irlqctcddjmkwqdvsdsm`, display name `anvikinnovations-cmyk's Project`, organization metadata present (org id withheld here). Untracked and not gitignored. | `NOT VERIFIED — REQUIRES DASHBOARD OR ENVIRONMENT ACCESS` | Proves a CLI link was written locally, not that the project is reachable, correct, active, or has a bucket/policies. The app never reads this file. |
| `supabase/` | Only the `.temp` link file. No `config.toml`, migrations, seed, policies or Edge Functions. | `MISSING — NO IMPLEMENTATION FOUND` | Storage policies exist only as documentation snippets in `docs/supabase-storage.md`; they are not applied by this repository. |
| `web/index.html` | No Firebase SDK/config and no Supabase config; 11 `{{SITE_ORIGIN}}` tokens (`:26-31,58-104`). | `PLACEHOLDER — NOT A REAL CONFIGURATION` | Production hosting/SEO metadata is not substituted; nothing injects Firebase/Supabase config here. |
| CI configuration | No `.github/`, GitLab, CircleCI, Netlify or Vercel configuration. | `MISSING — NO IMPLEMENTATION FOUND` | Deployments are manual; no automated config injection or deployment evidence. |
| `firestore.rules`, `firestore.indexes.json` | Rules default-deny (`firestore.rules:8-9,414-416`); 102 index definitions, 0 field overrides (`firestore.indexes.json`). | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Files exist but are not deployed (see `docs/firestore-index-coverage.md:398,426`; `docs/backend-setup.md:9-11`). |
| Documentation | `docs/backend-setup.md:9-11` says no Firebase project/credentials are configured and none executed/deployed. `docs/supabase-storage.md:6-9,463` says nothing was executed against a live Supabase project. | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Documentation is explicit about the gap; it does not constitute configuration. Minor conflict: `docs/backend-setup.md:19` says defaults are empty, while `env.dart:50-56` has non-secret non-empty defaults. |

---

## D. Feature-to-backend matrix

| Feature | Actual path (evidence) | Backend used | Status | Can appear to work locally without production? |
|---|---|---|---|---|
| App startup / bootstrap | `lib/main.dart:13-16` → `app_bootstrap.dart:44-142`; each backend gated by `Env.hasFirebase`/`Env.hasSupabase`. | Firebase (production or emulator) | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Only with `--dart-define=OM_USE_EMULATORS=true`; otherwise `main.dart:29-35` renders `SetupRequiredPage`. |
| Authentication / roles | `firestore_auth_repository.dart:74-145` → Firebase Auth + `accountEnsure`; role read from `users/{uid}`. | Firebase Auth + Firestore + callable | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Yes with Auth/Firestore/Functions emulators and a seeded role document. |
| Catalogue / home / search | `firestore_catalog_repository.dart` reads Firestore; local seed is `scripts/local/seed_local_store.mjs` (`:19` demo project). | Firestore (production or emulator) | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Only after seeding; the seed products carry no images (`images: []`). |
| Product details / variants | Firestore product read plus `variantListForProduct` callable (`firestore_catalog_repository.dart:256,321`). | Firestore + Cloud Functions | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Yes only with the Functions emulator. |
| Cart / wishlist | Cart is in memory (`cart_store.dart:36,68`); wishlist is Firestore (`firestore_account_repository.dart:139-144`). | Local memory (cart); Firestore (wishlist) | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Cart works but is lost on reload; wishlist needs Auth/Firestore. |
| Checkout / order creation | `checkout_controller.dart:525` → `firestore_order_repository.dart:23-25` → `ordersCreate` callable (`functions/index.js:95`). | Cloud Functions + Firestore | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Only with the Functions emulator; there is no client-side fallback. |
| Admin product management | `firestore_admin_repository.dart` → callables such as `adminProductSave` (`functions/index.js:809`), `adminOrderTransition` (`:702`). | Cloud Functions + Firestore | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Only with emulators and an admin role document; local rules are permissive. |
| Image upload / gallery | `media_editor.dart` → `products_controller.dart` → `supabase_media_repository.dart:168` → `media_uploader.dart:498-570`; media ledger is Firestore. | Supabase Storage (bytes) + Firestore (ledger) | `CONFLICT — CONFIGURATION DOES NOT MATCH CODE` | Only with a real Supabase project **and** permissive local rules; production fails before bytes are uploaded. |
| Media optimisation | `media_uploader.dart:512` → `media_optimise_gateway.dart:88-99`; default is passthrough. The `mediaOptimise` callable does not exist in `functions/index.js`. | Passthrough / no working backend | `MISSING — NO IMPLEMENTATION FOUND` | Uploads can succeed unoptimised; the optimisation stage never runs. |
| Customer order history / guest lookup | `firestore_order_repository.dart:29-54`; guest `byOrderNumber` at `:57-69`, called from `checkout_controller.dart:550`; rules require signed-in owner or staff (`firestore.rules:211-215`). | Firestore | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Guest server-detail lookup fails closed under the deployed rules; the checkout receipt still shows totals. |
| Wholesale application / approval | `wholesale_controller.dart:70` → Firestore; approval via `adminWholesaleDecide` (`functions/index.js:1013`). | Firestore + Cloud Functions | `PARTIAL — CODE EXISTS, SETUP INCOMPLETE` | Yes with emulators; the “quotation” is a support ticket, not a quote. |

---

## E. Supabase project discrepancy

**What the screenshot proves:** an owner-side view of the current Supabase organization shows three projects: `bharat-tech-pulse`, `om_event`, and a paused `om_events_and_decorato...`. No project visibly named `event_shop` appears.

**What it does not prove:**

- It does not prove that no Supabase project exists in another organization, account, or region.
- It does not prove which project, if any, this repository is intended to use.
- It does not prove the paused project's ref, bucket names, policies, keys, or data.
- A project name is not a project reference; the app would need a URL and a publishable key, neither of which is present in the repository.

**What the app actually references:** no Supabase project. The only Supabase values are build-time defines (`lib/app/core/env.dart:48-49`), and no in-repo file supplies them. `SUPABASE_PUBLISHABLE_KEY` is not consumed anywhere; the code consumes `SUPABASE_ANON_KEY` and passes it to the SDK's `publishableKey` parameter (`app_bootstrap.dart:125`). The existing web artifact contains zero `supabase.co` URLs.

**What the local CLI cache adds:** `supabase/.temp/linked-project.json` records ref `irlqctcddjmkwqdvsdsm` and display name `anvikinnovations-cmyk's Project`. This is local Supabase CLI state, not application configuration. The display name matches none of the three names in the screenshot. It was present before this audit (mtime 2026-10-22 09:40), is untracked, and is **not** ignored by `.gitignore` (`git check-ignore` exits 1). It may indicate a project was linked on this machine, but it does not prove the project is the intended one, is active, or has the required bucket/policies.

**Conclusion:** the repository cannot be tied to `bharat-tech-pulse`, `om_event`, or `om_events_and_decorato...`. The exact project reference used by the application is **none found**. The CLI cache ref is an identifier only, not a connection proof.

---

## F. Missing setup

### F1. Missing code

- **Media ledger write path vs rules.** `media_object_ledger.dart:293-309` documents that `firestore.rules` denies every client write to `media_objects`; the actual rules are `firestore.rules:395-397` (`allow write: if false`). The uploader writes the staging row before uploading bytes (`media_uploader.dart:498`), so production uploads fail before any object is stored. Local emulators hide this because `firebase.local.json:2` omits the strict rules.
- **No `mediaOptimise` implementation.** The Dart contract names a Firebase callable (`media_optimise_gateway.dart:104`), but `functions/index.js` exports no `mediaOptimise`; `CallableMediaOptimiseGateway` is never constructed, and the default is the disabled passthrough (`supabase_media_repository.dart:119`).
- **No Supabase Edge Functions, migrations, or policy files.** `supabase/` contains only the local `.temp` link file. Policies exist only as SQL snippets in `docs/supabase-storage.md:88-215`.
- **No server-side guest-order lookup.** The rules comment (`firestore.rules:201-209`) says a callable comparing order number plus contact email does not exist; the client-side check cannot be enforced by Firestore.
- **No Supabase database schema.** This is not necessarily a defect: Firestore is intentionally the system of record and Supabase is only the object store.

### F2. Missing environment configuration

- No `.env`, `.env.production.json`, `functions/.env`, or `functions/.env.example` exists. Only `.env.example` is present, with every Firebase/Supabase value empty.
- `build/web` was built without production defines; it contains the emulator project and placeholder client values.
- No committed or locally evidenced values for `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_APP_ID`, `SUPABASE_URL`, or `SUPABASE_ANON_KEY`.
- `OM_PAYMENT_GATEWAY` is declared as a Functions secret but has no local value; Secret Manager state is unverified.
- `SUPABASE_SERVICE_ROLE_KEY` is correctly absent from the client; the guard at `env.dart:78-90` and `app_bootstrap.dart:157-175` is a safety check, not a configuration source.

### F3. Missing Supabase resources

- A project matching the app is not identified.
- Bucket `om-events-media` (`env.dart:50-51`) is not proven to exist.
- Storage policies for staff writes, public/private reads and anonymous access are not applied by the repository.
- Anonymous sign-ins are not proven enabled, although the storage service calls `signInAnonymously` (`supabase_storage_service.dart:143`) and the docs list this as a go-live prerequisite (`docs/supabase-storage.md:445-466`).
- No upload has been exercised against a live bucket; the docs say so explicitly.

### F4. Missing Firebase Console configuration

All of the following are `NOT VERIFIED — REQUIRES DASHBOARD OR ENVIRONMENT ACCESS`:

- existence and ownership of the intended project (prior audit notes report `om-events-store`, project number `438395878265`; this audit did not verify it);
- billing plan (prior notes report Spark, which cannot deploy Cloud Functions; `docs/backend-setup.md:39` requires Blaze);
- registered Web app and its public options;
- Email/Password provider and authorized domains;
- Firestore database region and deployed rules/indexes;
- 39 callables and 3 triggers deployed to `us-central1`;
- Secret Manager version for `OM_PAYMENT_GATEWAY`;
- Hosting release history;
- Firebase Storage bucket/rules (configured in the repo but not used by the client).

### F5. Missing deployment

- No `.firebase/` directory, hosting cache, release log, CI workflow, or deployment record exists in the repository.
- `build/web` is gitignored/untracked and is an emulator build.
- `docs/backend-setup.md:9-11` states that nothing was executed or deployed; `docs/firestore-index-coverage.md:398,426` says no index is claimed to be deployed.
- The prior audit report (`FIREBASE_COMPLETE_AUDIT_REPORT.md:27,216`) records owner-side notes about a created project but explicitly marks them unverified; it is not deployment evidence.
- **Uncommitted backend source.** `functions/index.js` is modified in the working tree, and `functions/lib/order_number.js` is untracked yet required at `functions/index.js:48`. The current working tree contains the Phase 2B fixes; a clean checkout of HEAD would not. Any future deploy must be made from an explicitly reviewed tree, not assumed from HEAD.

---

## G. False-success and fallback risks

1. **(P0) Media upload is not a fake success in code, but production cannot complete it.** The uploader awaits the ledger staging write (`media_uploader.dart:498`), then the real Supabase upload (`:502`), promotion (`:549`), ledger attach (`:557`) and success settlement (`:570`). If the ledger write is denied, it throws and rolls back. Under `firestore.rules:395-397` that denial is guaranteed in production. The `PassthroughOptimiseGateway` does not stand in for the byte transfer; it only skips the optional optimisation step. Local permissive rules are the only reason this path appears healthy.
2. **(P2) Product save can succeed with missing images.** `media_editor_state.dart:193-200` blocks only busy uploads and missing alt text; `publishableRefs` (`:207-212`) silently skips items whose `ref` is null. A failed upload can therefore be omitted while the product save reports success.
3. **(P2) Private-bucket handling can store a misleading URL.** Successful private uploads store an empty `url` (`media_uploader.dart:591-593`), and `OmMediaImage` shows “No image” for an empty URL without invoking a resolver (`om_media_image.dart:36-44`). A failed visibility lookup falls back to `assumedPublic` (`supabase_storage_service.dart:168-184`), which can persist a public URL for a private bucket. This is a wrong-reference risk, not a false upload success.
4. **(P2) Optimization is silently absent.** The default gateway is disabled (`media_optimise_gateway.dart:88-99`), the callable is never constructed, and no `mediaOptimise` export exists. Uploads succeed without the documented resize/crop/transform stage.
5. **(P1) Guest order recovery fails closed.** The guest `byOrderNumber` path is called from checkout, but `firestore.rules:211-215` allows order reads only to the signed-in owner or staff. A guest gets the receipt totals, not per-line server detail. The client-side email comparison is not a security control.
6. **(P1) The emulator build is not a production artifact.** It targets `demo-om-events` with localhost placeholders and no Supabase URL. Hosting it would point the browser at local services and disable media; it must not be used as deployment evidence.
7. **(P1) Local permissive rules hide production denials.** `firebase.local.json:2` deliberately omits `firestore.rules`; seeds and admin writes against that emulator prove local data shape, not production authorization.
8. **(P3) Unresolved SEO origin tokens.** `build/web/index.html` retains 11 `{{SITE_ORIGIN}}` tokens; this is not a backend issue but confirms the artifact was not prepared for a production host.

---

## H. Required manual verification

Do not create, delete, pause, resume, or reconfigure anything while checking. Read only.

### Firebase

1. Open `https://console.firebase.google.com/` and select the intended project. Record the project ID, project number, and billing plan. Compare the ID with `.firebaserc` (currently a placeholder) and with the prior notes (`om-events-store`).
2. **Project settings → General → Your apps → Web app:** confirm the app ID, API key presence (do not copy it into the repo), auth domain and storage bucket.
3. **Authentication → Sign-in method:** confirm Email/Password is enabled and the production hosting domain is authorized.
4. **Firestore → Data:** confirm the database exists and note its region. **Rules** tab: confirm the deployed rules match `firestore.rules`. **Indexes** tab: compare the composite count with the 102 definitions in `firestore.indexes.json`.
5. **Functions:** confirm the 39 callables and 3 triggers are deployed in `us-central1`, and confirm Secret Manager has `OM_PAYMENT_GATEWAY`.
6. **Hosting:** check release history for any deployment of `build/web`. It should be empty if this repository has never deployed.
7. **Usage and billing:** confirm Spark vs Blaze. If Spark, the Functions cannot deploy.

### Supabase

1. Open `https://supabase.com/dashboard`, select the organization shown in the screenshot, and record each project's name, ref, and status. The paused `om_events_and_decorato...` is a candidate to inspect, but do not assume it is the app's project.
2. Compare the ref of the candidate project with the local link cache ref `irlqctcddjmkwqdvsdsm` and the display name `anvikinnovations-cmyk's Project`. If they differ, the local CLI link points somewhere else.
3. **Project Settings → API:** confirm the project URL and publishable/anon key are present; compare the URL's project ref. Do not copy keys into source or chat.
4. **Storage:** confirm whether bucket `om-events-media` exists, whether it is public or private, its file-size/MIME limits, and its policies. The repository's documented policies are not applied automatically.
5. **Authentication → Providers:** confirm anonymous sign-ins are enabled, because the storage service calls `signInAnonymously`.
6. **Logs / usage:** check whether any storage requests or uploads have ever reached the project.
7. If no project matches, record that fact and stop. Do not create one as part of this audit.

### Build/deployment evidence (after configuration, not now)

A future production build should be checked for: zero `demo-om-events` occurrences, zero emulator key/app placeholders, the intended Firebase project ID, a real Supabase URL, and no `{{SITE_ORIGIN}}` tokens. The current artifact fails these checks.

---

## I. Recommended next steps

1. **Establish external truth first.** Complete §H for Firebase and Supabase and record the answers. Do not change code or infrastructure until the actual project, plan, bucket and ref are known.
2. **Resolve the Supabase project question.** Identify the intended project among the three visible projects or confirm it is elsewhere. Compare its ref with the local CLI cache. Do not create or pause anything yet.
3. **Resolve the Firebase plan.** If the intended project is on Spark, Functions cannot deploy. Decide between Blaze and an architecture that does not depend on Functions before further implementation.
4. **Prepare local-only configuration.** Once the projects are confirmed, create a gitignored `.env.production.json` from `.env.example` with the real public client values, and select the project locally with `firebase use --add`. Never commit it; never add a service-role key to a client build.
5. **Resolve the media design conflict before claiming image support.** Either grant the ledger the required write path (ideally via a callable/Admin SDK) or redesign the ledger, then apply the Supabase bucket/policies. Decide whether server-side optimization is in scope; if yes, implement or explicitly remove the dead `mediaOptimise` contract.
6. **Deploy to staging first.** Deploy rules, indexes, Functions and Hosting to a staging project, run the real-emulator/real-project tests, and verify a production-mode build. Only then consider production.
7. **Hygiene:** add `supabase/.temp/` to `.gitignore` so the local link cache cannot be committed, and confirm no project identifiers or keys enter the repository.
8. **Do not proceed to Phase 3 or further remediation** until the backend state above is established and approved.

---

## J. Integrity statement

### Commands executed (read-only)

- `ls`, `find`, `wc`, `grep`, `sed`, `Read` over the repository, including `lib/**`, `functions/**`, `supabase/**`, `docs/**`, `scripts/**`, `web/**`, `build/web/**`, and configuration files.
- `git status --short`, `git diff --stat`, `git diff HEAD -- <specific files>`, `git check-ignore`, `git ls-files` to inspect the working tree, ignore rules and tracked artifacts.
- `node -e` to parse `firestore.indexes.json` and count index definitions.
- No emulator was started, no Flutter build/test/analyze was run, no npm install/test was run, no deploy/migration/seed was run, and no cloud SDK or Dashboard request was made.

### Files inspected (primary)

`pubspec.yaml`, `pubspec.lock`, `.env.example`, `.gitignore`, `.firebaserc`, `firebase.json`, `firebase.local.json`, `firebase.local.strict.json`, `firebase.integration.json`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `functions/package.json`, `functions/index.js`, `functions/lib/**`, `lib/main.dart`, `lib/app/core/env.dart`, `lib/app/core/services/app_bootstrap.dart`, `lib/app/core/services/media/**`, `lib/data/repositories/firestore/**`, `lib/data/repositories/supabase/**`, `lib/app/core/widgets/media/**`, `lib/features/storefront/checkout/**`, `web/index.html`, `build/web/**`, `supabase/.temp/linked-project.json`, `docs/backend-setup.md`, `docs/supabase-storage.md`, `docs/firestore-index-coverage.md`, `docs/local-demo.md`, `spike/edge-feasibility/README.md`, `FIREBASE_COMPLETE_AUDIT_REPORT.md`.

### Report and change statement

- **Report created:** `docs/FIREBASE_SUPABASE_CONFIGURATION_AUDIT.md` (this file).
- **No existing file was modified.** No source, configuration, dependency, index, rule, environment or Flutter file was edited.
- **No cloud mutation, deployment, migration, seed, project creation, pause/resume, billing change, or Console change occurred.**
- **No secret values were printed.** Only variable names, presence/absence, project ids (not secrets), and the local Supabase CLI project ref were reported. No API key, token, password, service-role key, or connection string was reproduced.
- **Pre-existing working-tree state was preserved.** At audit start the tree already contained six modified tracked files (`functions/index.js`, `functions/lib/server.js`, the integration test, two docs, and a formatting-only `app_bootstrap.dart` diff), plus untracked `functions/lib/order_number.js`, the Phase 2B backup, and `supabase/`. The formatting-only `app_bootstrap.dart` change and the Supabase CLI cache predate this audit. None were edited by this audit.
- **External claims are marked unverified.** The Supabase screenshot was supplied as an owner description; the Firebase and Supabase Dashboards were not read by this audit. Prior audit notes are cited as prior notes, not current evidence.
