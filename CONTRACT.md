# OM Events – Shared Architecture Contract

Binding for all five sub-agents. Deviation = integration defect.

## Toolchain

Only the main agent runs `fvm`/`flutter`/`dart`/`git` write commands. Sub-agents verify by
reading code and report `NOT VERIFIED` when they cannot execute. Never edit outside your
assigned domain; if something outside it must change, report `NEEDS OWNER` with `file:line`.

## Package

`pubspec.yaml` name: `om_events`. Every import is package-relative:
`package:om_events/...` — never relative imports above one directory level.

## Layering (feature-first)

```
lib/app/            route table, bindings, theme, core constants/errors/utils/validators/widgets
lib/app/core/services/   firebase/ (auth, firestore clients), media/ (supabase), env.dart
lib/data/           models (typed), repositories (interface + firestore impl), providers
lib/features/<f>/   <f>_controller.dart, <f>_binding.dart, views/, widgets/
```

Rules:
- UI touches **no** `FirebaseFirestore` / `SupabaseStorage` directly. UI -> GetXController ->
  repository interface -> provider/service.
- One controller per screen; no god-controller. Controllers hold presentation state only;
  money/stock math lives in `lib/data/pricing/` (written by the main agent) and is **never**
  reimplemented in a controller or a Cloud-Function-adjacent Dart helper.
- All models are typed with `fromDoc(Map<String,dynamic> id, DocumentSnapshot)` / `toMap()` and
  are `freezed`-free (plain immutable classes + copyWith) to keep codegen out of the build.

## Already written — import these, never recreate or edit them

```
lib/app/core/env.dart  errors/failures.dart  utils/{money,om_slug,om_validators}.dart
lib/app/core/services/{app_bootstrap,session_store}.dart
lib/app/core/widgets/{om_buttons,om_surfaces,om_states,om_inputs,om_responsive,om_price,
                      om_media_image}.dart
lib/app/routes/{app_routes,guards,app_pages}.dart
lib/app/theme/{om_tokens,om_typography,om_theme}.dart
lib/app/bindings/{global,backend,media}_binding.dart
lib/data/om_doc.dart  query.dart  models/*.dart  pricing/pricing_engine.dart
lib/data/repositories/{auth,catalog,order,account,admin,media}_repository.dart  (abstract only)
lib/features/{storefront,admin}/*_routes.dart  (placeholder lists you replace)
```

Implementations belong to the owning agent: Firestore/Auth repository impls + `backend_binding.dart`
body (Agent 3), Supabase media impl + `media_binding.dart` body (Agent 4). Editing a shared file
outside your domain → report `NEEDS OWNER`, do not patch it.

## Single source of truth: pricing

`lib/data/pricing/pricing_engine.dart` (owner: main agent — already written, do not fork it):
`PricingEngine.priceFor({required Product product, required int qty, ProductVariant? variant,
int? customerOverrideUnitPricePaise}) -> PriceResolution`
`PriceResolution { unitPricePaise, lineTotalPaise, slab, nextSlab, unitsToNextSlab }`
`PricingEngine.mergeQty(...)`, `CartTotals.from(...)`, `OrderGranularity`, `validateSlabGrid(slabs)`

- Slab price applies to **every** unit in the line (not progressive marginal).
- Slabs are validated on write: no overlap, min<=max, positive price, open-ended band only last.
- Cart/checkout totals come from the controller calling the engine for display, and the
  authoritative total **only** from `orders.createOrder` (Cloud Function). Client total is
  advisory; backend rejects mismatch beyond the configured epsilon.
- Order lines snapshot `unitPrice` + slab boundaries immutably at purchase time.

Agents 1 and 2 consume `PriceResolution`; neither may define a pricing function.

## Route names — `lib/app/routes/app_routes.dart` is the only legal source

Navigate by `OmRoutes.*` constants; a literal route string inside a screen is a defect. Agents 1/2
register their own `GetPage`s inside `lib/features/storefront/storefront_routes.dart` /
`lib/features/admin/admin_routes.dart`; the main agent merges them in `app_pages.dart`.

Customer: `home`, `category` + `forCategory(slug)`, `product` + `forProduct(idOrSlug)`, `search`,
`cart`, `checkout`, `orderSuccess` + `forOrderSuccess(id)`, `login`, `register`, `forgotPassword`,
`resetPassword`, `account`, `accountOrders`, `accountOrder` + `forOrder(id)`, `accountAddresses`,
`accountWishlist`, `accountNotifications`, `accountSupport`, `accountSettings`, `reviewCompose` +
`forReview(productId)`, `wholesaleApply`, `wholesaleBulkOrder`, `wholesaleQuotation`, `about`,
`contact`, `faq`, `policy` + `forPolicy(kind)`, `notFound`, `unavailable`.
Admin: `admin`, `adminProducts`, `adminProductNew`, `adminProductDetail` (`/admin/products/:id`),
`adminCategories`, `adminOrders`, `adminOrderDetail`, `adminCustomers`, `adminCustomerDetail`,
`adminInventory`, `adminPricing`, `adminReviews`, `adminCoupons`, `adminWholesale`,
`adminSettings`, `adminReports`, `adminAudit`, `adminMedia`.

Guards (`lib/app/routes/guards.dart`, already written): `AuthGuard`, `AdminGuard`,
`PricingAdminGuard`, `SignedOutOnlyGuard`, `WholesaleGuard`. They read `SessionStore`
(`lib/app/core/services/session_store.dart`) and are UX + defence-in-depth only — Firestore rules
and Cloud Functions are the permission system, never a role the bundle supplied.

## Design tokens (owned by the main agent, everyone consumes — no raw hex outside theme)

`OmColors`: black `#0B0B0C`, surfaceDark `#141416`, gold `#C9A227`, goldBright `#E5C158`,
goldSoft `#F2E2B0`, cream `#FBF8F1`, line `#E3E0D8`, textPrimary `#16151A`, textMuted `#6B6A72`,
success `#1F8A4C`, warning `#C4761A`, danger `#B42318`.
`OmSpacing`: xs4 sm8 md16 lg24 xl32 xxl48 (all multiples of 4).
`OmRadius`: sm8 md12 lg16 pill999.
`OmBreakpoints`: mobile <600, tablet 600-1023, laptop 1024-1439, desktop >=1440.
`context.isMobile/.isTablet/.isLaptop/.isDesktop`, `context.omColumnCount` -> product grid columns
2/3/4/5. Text styles: `OmText.display/h1/h2/h3/lead/body/caption/label` (Google Fonts
`Cormorant Garamond` for display, `Inter` for body; falls back to system if font load fails).
Buttons: `OmButton(label:, onPressed:, variant: OmButtonVariant.primary|secondary|outline|ghost|
danger, size:, icon:, expanded:, loading:)`. Never use `Theme.of(context).colorScheme` raw gold
shortcuts and never hand-roll a `FilledButton` for a store CTA.

`Env` lives at `lib/app/core/env.dart` and reads `--dart-define` keys (`FIREBASE_API_KEY`,
`FIREBASE_PROJECT_ID`, `FIREBASE_APP_ID`, `FIREBASE_AUTH_DOMAIN`, `FIREBASE_STORAGE_BUCKET`,
`FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_MEASUREMENT_ID`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_MEDIA_BUCKET`, `FUNCTIONS_REGION`, `SITE_URL`, `CURRENCY`) with **empty defaults**, plus
`hasFirebase` / `hasSupabase` / `isFullyConfigured` / `missingKeys()` /
`hasServiceRoleKeyInClient`. `supabase_service_role_key`, Firebase private service accounts and
admin tokens must never appear anywhere in `lib/` — Cloud Functions only.
`.env.example` documents every key; no real value is committed anywhere.

Accessibility: every interactive element has a label, contrast >= 4.5:1 for body text, tap
targets >= 44dp, no color-only state signalling.

## Firestore collections (Agent 3 owns schema + rules; others read the types only)

`users`, `categories`, `products`, `product_variants`, `inventory_movements`, `orders`,
`order_items`, `payments`, `reviews`, `coupons`, `addresses`, `wholesale_applications`,
`store_settings`, `audit_logs`, `notifications`, `support_requests`, `media_objects`.

Money is stored as integer **paise** (`pricePaise`, `lineTotalPaise`) everywhere. Never double.
Display formats through `OmMoney.format(paise)` -> `₹1,234`.
Timestamps: Firestore `Timestamp` in docs, `DateTime` in models, ISO-8601 in JSON.
Document ids: `nanoid`-style generated ids; product also carries `sku` (unique) and `slug`.
Images never inline: `media_objects` holds `{ storagePath, url, altText, order, type, bucket }`
referenced by products/categories/banners. No base64 in any document. Unbounded arrays are
forbidden — subcollection for order history, movements, reviews.

## Secrets in code

An unconfigured backend is a **visible state**, not a demo: `AppBootstrap.run()` returns a
`BootstrapReport`, `main.dart` renders `SetupRequiredPage` when Firebase is absent, and
`UnconfiguredMediaRepository` throws instead of pretending an upload succeeded. Do not add seed
data, mock catalogues, or `TODO: replace with real value` fallbacks that make a broken build look
healthy.

## State / DI conventions

`Get.put` / `Get.lazyPut(fenix: true)` only inside `Bindings`. Repositories injected as their
abstract type. `GetMaterialApp` with named routes + `pageTransitionsTheme` + FlavorBuilder.
No `setState` for cross-screen state; no duplicated reactive state — `Rx` lives in the owning
controller only, and derived values use `computed`/`Obx` on the narrowest possible subtree.

## Verification language (required in every agent report)

`PASS — LIVE VERIFIED` / `PASS — LOCAL VERIFIED (code read)` / `PARTIAL` / `FAIL` / `BLOCKED` /
`NOT TESTED` / `NOT CONFIGURED` with severity `P0` crash or data loss, `P1` wrong behaviour a
user sees, `P2` quality, `P3` polish. `file:line` for every claim. "It compiles in my head" is
not evidence.
