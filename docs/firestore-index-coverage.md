# Firestore Composite Index Coverage — Phase 2A

Date: 2026-10-21
Project: `D:\event_shop`
Scope: local index definition audit and remediation only. No deployment, no production access, no cloud mutation.

## 1. Result

| Item | Before | After |
|---|---|---|
| `firestore.indexes.json` definitions | 50 | 102 |
| Additions | — | 52 |
| Schema accepted by `firebase-tools` 15.23.0 `FirestoreApi.validateSpec` | **NO** | **YES** |
| Duplicate processed signatures | — | 0 |
| Query shapes with no index/merge path in the local model | — | 0 (of the enumerated shapes) |

Files changed:

- `firestore.indexes.json` — rewritten into the deployable `fields`/`fieldPath` schema; all 50 existing definitions preserved field-for-field; 52 justified indexes appended.
- `docs/firestore-index-coverage.md` — this document.
- Backup of the original file: `firestore.indexes.json.backup-20261021-phase2a` (SHA-256 `68211cf5c91d98b29031720c64b9642ddbf28ce4372fc67cbef67de0325bed77`, identical to the pre-edit working file).

No other file was modified. `firestore.rules`, `functions/index.js`, Flutter UI/business logic, `.firebaserc`, `firebase.json`, billing and deployment configuration are untouched.

## 2. Method and rules used

### 2.1 The original file was not deployable

Every one of the 50 original entries used a non-existent serialization:

```json
{ "collectionGroup": "products", "queryScope": "COLLECTION",
  "indexes": [ { "field": "status", "order": "ASCENDING" } ] }
```

`firebase-tools` expects `fields` and `fieldPath`. The CLI's own validator rejected the file before any deploy could start:

```text
firestore.indexes.json.backup-20261021-phase2a: JSON OK, definitions=50, firebase-tools schema=INVALID
  -> Must contain "fields": {"collectionGroup":"products","queryScope":"COLLECTION",
     "indexes":[{"field":"status","order":"ASCENDING"}, ...]}
```

The rewrite was therefore mandatory, not an optional cleanup. It preserves all 50 definitions and their field order, only re-keying `indexes` → `fields` and `field` → `fieldPath`.

### 2.2 Equality filters can be merged; the audit over-counted

The Firebase audit (`FIREBASE_COMPLETE_AUDIT_REPORT.md` §C5) listed about 20 index families and stated that "Firestore requires the index to contain all equality fields." That is true only for a **single** composite index used directly. Cloud Firestore also merges simple equality indexes, and it can merge an `array-contains`/`array-contains-any` index with equality indexes (the docs explicitly warn that this merge can be slower and recommend a combined index where latency matters):

- "Cloud Firestore can merge the indexes for simple equality filters to build the indexes needed for larger equality queries."
- "`in` and `==` clauses use the same index."
- "To avoid performance loss caused by index merging, we recommend that you create an index to combine an array-contains or array-contains-any query with additional clauses."

Source: <https://firebase.google.com/docs/firestore/query-data/index-overview>.

Therefore the file uses **one index per filter field per sort shape** rather than a Cartesian product of every filter combination. For example, a retail query with `status == active`, `isWholesaleOnly == false`, `isFeatured == true`, a tag and `createdAt` sort is served by merging:

```text
[status,          createdAt DESC, __name__ ASC]
[isWholesaleOnly, createdAt DESC, __name__ ASC]
[isFeatured,      createdAt DESC, __name__ ASC]
[tags CONTAINS,   createdAt DESC, __name__ ASC]
```

No single index contains all four fields. This removes roughly 90–180 redundant product definitions while leaving every documented query shape covered.

Consequence to verify in staging: index merging is a query-planner behavior, not a configuration flag. The static model below proves the definitions are *shaped* correctly; only a real project can prove the planner accepts each query without returning a `failed-precondition` index link.

### 2.3 `__name__` direction is not cosmetic

Every paginated repository query ends with an explicit `orderBy(FieldPath.documentId)` (ASC). The docs state:

- "By default, the `__name__` field is sorted in the same direction of the last sorted field in the index definition."
- "To sort results by the non-default `__name__` direction, you need to create that index."

`firebase-tools` appends an implicit `__name__` to every index using the direction of the last ordered field. So:

| Query order | Index tail that matches | New `__name__` needed? |
|---|---|---|
| `soldCount DESC` (no documentId order) | `soldCount DESC, __name__ DESC` | No (implicit) |
| `soldCount DESC, documentId ASC` | `soldCount DESC, __name__ ASC` | **Yes** |
| `retailPricePaise ASC, documentId ASC` | `retailPricePaise ASC, __name__ ASC` | No (implicit ASC) |
| `retailPricePaise DESC, documentId ASC` | `retailPricePaise DESC, __name__ ASC` | **Yes** |
| `createdAt DESC, documentId ASC` | `createdAt DESC, __name__ ASC` | **Yes** |

This is why several existing indexes that look correct (for example `[status, soldCount DESC]`) do **not** serve the current cursor-paginated storefront or admin queries: their implicit suffix is `__name__ DESC`, while the query asks for `__name__ ASC`. They are retained (they serve non-paginated reads such as the home shelves and the Functions dashboard) but are not counted as coverage for paginated reads.

Alternative considered and rejected for this phase: remove the explicit `documentId` orderBy and rely on the implicit `__name__ DESC` tie-breaker so the existing indexes could serve the paginated queries. That changes cursor tie-break semantics in Flutter and Phase 2A forbids application changes, so the definitions were aligned to the current code instead.

### 2.4 Scope and limits checked

- All queries in the app target single collections; there are no `collectionGroup` queries, so every definition is `queryScope: COLLECTION`.
- One `array-contains`/`array-contains-any` filter per query. `in` and `array-contains-any` are capped at 30 values; the code chunks wishlist ids at 30 and caps keyword tokens at 5.
- One inequality range per query, and it must be the primary sort field. The catalogue deliberately moves price bounds to a client filter when a search term, an array filter or a multi-value category is present (`catalog_query_builder.dart:76-86,172-180`).
- An index may contain at most one array field; the verifier checks this.
- Every processed index has at least two fields including `__name__`.

## 3. Definition inventory

### 3.1 Before (50)

| Collection | Count |
|---|---:|
| products | 21 |
| product_variants | 2 |
| categories | 3 |
| orders | 5 |
| reviews | 3 |
| inventory_movements | 2 |
| audit_logs | 3 |
| notifications | 2 |
| support_requests | 2 |
| wholesale_applications | 2 |
| users | 3 |
| coupons | 1 |
| customer_price_overrides | 1 |
| **Total** | **50** |

### 3.2 After (102)

| Collection | Before | Added | After |
|---|---:|---:|---:|
| products | 21 | 41 | 62 |
| product_variants | 2 | 0 | 2 |
| categories | 3 | 0 | 3 |
| orders | 5 | 5 | 10 |
| reviews | 3 | 0 | 3 |
| inventory_movements | 2 | 0 | 2 |
| audit_logs | 3 | 4 | 7 |
| notifications | 2 | 0 | 2 |
| support_requests | 2 | 0 | 2 |
| wholesale_applications | 2 | 0 | 2 |
| users | 3 | 2 | 5 |
| coupons | 1 | 0 | 1 |
| customer_price_overrides | 1 | 0 | 1 |
| **Total** | **50** | **52** | **102** |

The Firestore quota for composite indexes is 200 per database; 102 is within it. No `fieldOverrides` are declared (single-field indexes remain automatic).

## 4. Query-to-index matrix

Notation: `EQ` = equality (`==` or `in`), `AC` = `array-contains`, `AC-any` = `array-contains-any` (uses the same index as `AC`), `__name ASC` = explicit document-id suffix. "Filters" lists every optional filter that can coexist with the row's sort; because equality filters merge, each one needs its own index ending in the same sort suffix.

### 4.1 Storefront catalogue — `products`

Source unless stated: `lib/data/providers/catalog_query_builder.dart` and `lib/data/repositories/firestore/firestore_catalog_repository.dart`.

| ID | Query / source | Filters | Order | Required composite index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| P1 | Popular / best selling — `catalog_query_builder.dart:96-98,110-118`; `firestore_catalog_repository.dart:149-157` | `status EQ active`; optional `categorySlug EQ`, `categoryId EQ`/`in` (≤30), `isFeatured EQ`, `isWholesaleOnly EQ false` (retail), one `tags AC` **or** one `keywords AC-any` | `soldCount DESC, __name__ ASC` | one per filter: `[status / categoryId / categorySlug / isWholesaleOnly / isFeatured / tags AC / keywords AC, soldCount DESC, __name__ ASC]` | `[status, soldCount DESC]` ends `__name__ DESC` → **not a match** | **Added 7** |
| P2 | Newest — `:99-100` | same | `createdAt DESC, __name__ ASC` | same 7 fields ending `createdAt DESC, __name__ ASC` | `[status, createdAt DESC]` ends `__name__ DESC` → **not a match** | **Added 7** |
| P3 | Price low → high — `:101-102` | same; price bounds only when price sort, no search/array/multi-category (`:55-60,76-86`) | `retailPricePaise ASC, __name__ ASC` (implicit) | `[categoryId / categorySlug / isWholesaleOnly / isFeatured / tags AC / keywords AC, retailPricePaise ASC]` | `[status, retailPricePaise ASC]` **matches** the status member (implicit `__name__ ASC`) | **Added 6** |
| P4 | Price high → low — `:103-104` | same | `retailPricePaise DESC, __name__ ASC` | same 7 fields ending `retailPricePaise DESC, __name__ ASC` | `[status, retailPricePaise DESC]` ends `__name__ DESC` → **not a match** | **Added 7** |
| P5 | Top rated — `:105-106` | same | `ratingAvg DESC, __name__ ASC` | same 7 fields ending `ratingAvg DESC, __name__ ASC` | `[status, ratingAvg DESC]` ends `__name__ DESC` → **not a match** | **Added 7** |
| P6 | Featured-only switch — `search_filter_panel.dart:152-156` | adds `isFeatured EQ true` | any P1–P5 sort | served by the `isFeatured` member of the relevant sort set | none | **Covered by P1–P5**, no extra definition |
| P7 | Tag chip filter — `catalog_results.dart:180-185`; `catalog_controller.dart:125-131` | adds one `tags AC` | any P1–P5 sort | served by the `tags AC` member of the relevant sort set | none (no `tags` entry existed) | **Covered by P1–P5**; more than one tag is an invalid Firestore query — see §6 |
| P8 | Text search — `catalog_query_builder.dart:50-54` | adds `keywords AC-any` (≤5 tokens); price bounds move client-side | any P1–P5 sort | served by the `keywords AC` member of the relevant sort set | none (no `keywords` entry existed) | **Covered by P1–P5**; search + tag is invalid — see §6 |
| P9 | Single-category browse — `:27-28`; `firestore_catalog_repository.dart:38-60,64-81` | adds `categorySlug EQ` | any P1–P5 sort | `[categorySlug, sort, __name__ ASC]` | `[status, categorySlug, createdAt DESC]` is a different filter set and ends `__name__ DESC` | **Covered by P1–P5** |
| P10 | Parent-category browse — `:29-33` | `categoryId EQ` (one id) or `categoryId in` (2–30 descendants) | any P1–P5 sort | `[categoryId, sort, __name__ ASC]` | `[status, categoryId, …]` indexes are different filter sets; the `in` form uses the same index as `EQ` | **Covered by P1–P5** |
| P11 | Price range — `catalog_query_builder.dart:55-60` | `retailPricePaise >= / <=` only when the sort is a price sort and no search/array/multi-category; otherwise client-side | price sort owns the range | range and sort share `retailPricePaise`; P3/P4 indexes serve it | `[status, retailPricePaise ASC/DESC]` for the status-only shape | **Covered by P3/P4** |
| P12 | Home featured shelf — `firestore_catalog_repository.dart:189-217` | `status EQ`, `isFeatured EQ`, retail adds `isWholesaleOnly EQ false` | `createdAt DESC` (no explicit documentId) | retail: `[status, isWholesaleOnly, isFeatured, createdAt DESC]`; entitled: existing `[status, isFeatured, createdAt DESC]` | entitled **matches**; retail **missing** | **Added 1** |
| P13 | Home new-arrival shelf — same | `status EQ`, `isNewArrival EQ`, retail adds `isWholesaleOnly EQ false` | `createdAt DESC` | retail: `[status, isWholesaleOnly, isNewArrival, createdAt DESC]` | entitled **matches**; retail **missing** | **Added 1** |
| P14 | Home best-seller shelf — same | `status EQ`, `isBestSeller EQ`, retail adds `isWholesaleOnly EQ false` | `soldCount DESC` | retail: `[status, isWholesaleOnly, isBestSeller, soldCount DESC]` | entitled **matches**; retail **missing** | **Added 1** |
| P15 | Related products — `firestore_catalog_repository.dart:220-231` | `status EQ`, `categoryId EQ`, retail adds `isWholesaleOnly EQ false` | `soldCount DESC` | retail: `[status, isWholesaleOnly, categoryId, soldCount DESC]` | entitled `[status, categoryId, soldCount DESC]` **matches**; retail **missing** | **Added 1** |
| P16 | Name suggestions — `firestore_catalog_repository.dart:234-245` | `status EQ`, `name >= term`, `name <= term+\uf8ff`, retail adds `isWholesaleOnly EQ false` | `name ASC` | retail: `[status, isWholesaleOnly, name ASC]` | entitled `[status, name ASC]` **matches**; retail **missing** | **Added 1** |
| P17 | Product by slug / SKU — `firestore_catalog_repository.dart:111-130` | `slug EQ` or `sku EQ`, `status EQ`, optional `isWholesaleOnly EQ false`; `limit(1)` | none | none — equality-only queries merge automatic single-field indexes | `[status, slug]`, `[status, sku]` are retained but redundant | **Unnecessary** |
| P18 | Cart / wishlist hydration — `firestore_catalog_repository.dart:133-146`; `firestore_account_repository.dart:118-136` | `__name__ in [≤30]`, `status EQ`, optional `isWholesaleOnly EQ false` | none | none — `in` uses the equality index and merges with single-field indexes | audit item 18 said missing | **Unnecessary** (staging confirmation required) |
| P19 | Admin product list — `firestore_admin_repository.dart:77-99` | optional `status EQ`; name/SKU search is client-side | `updatedAt DESC, __name__ ASC` | `[updatedAt DESC, __name__ ASC]`; `[status, updatedAt DESC, __name__ ASC]` | `[status, updatedAt DESC]` ends `__name__ DESC` | **Added 2** |
| P20 | Admin product search — same | client-side name/SKU filter over the P19 page | P19 order | P19 indexes | P19 | **Covered by P19** |
| P21 | Product detail by id — `firestore_catalog_repository.dart:104-108` | document get | none | none | — | **Not applicable** |

### 4.2 Categories, variants

| ID | Query / source | Filters | Order | Required index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| C1 | Active category tree — `firestore_catalog_repository.dart:22-36` | `isActive EQ true` | `order ASC` | `[isActive, order]` | **matches** | **Existing** |
| C2 | Category by slug — `firestore_catalog_repository.dart:284-295` | `slug EQ`; shoppers add `isActive EQ` | none | none — equality-only | `[slug]` single-field entry is redundant | **Unnecessary** |
| C3 | Children of category — `:298-301` | reuses C1 list, filters in Dart | — | C1 | C1 | **Covered by C1** |
| V1 | Variants, staff — `firestore_catalog_repository.dart:310-317` | `productId EQ` | `order ASC` | `[productId, order]` | **matches** | **Existing** |
| V2 | Variants, shopper callable / Functions — `functions/index.js:1591` | `productId EQ`, `isActive EQ` | none | none — equality-only | `[productId, isActive, order]` retained | **Unnecessary** |

### 4.3 Reviews

| ID | Query / source | Filters | Order | Required index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| R1 | Published reviews — `firestore_account_repository.dart:156-165` | `productId EQ`, `status EQ published` | `createdAt DESC` | `[productId, status, createdAt DESC]` | **matches** (implicit `__name__ DESC`) | **Existing** |
| R2 | My review — `:202-207` | `productId EQ`, `uid EQ`; `limit(1)` | none | none — equality-only | `[productId, uid]` retained but redundant | **Unnecessary** |
| R3 | Moderation queue — `firestore_admin_repository.dart:522-527` | `status EQ` | `createdAt DESC` | `[status, createdAt DESC]` | **matches** | **Existing** |
| R4 | `forProduct(publishedOnly: false)` — `firestore_account_repository.dart:156-165` | `productId EQ` only | `createdAt DESC` | would need `[productId, createdAt DESC]` | missing | **Not added** — no caller; mark as a required index if a staff view ever wires this path |

### 4.4 Orders

| ID | Query / source | Filters | Order | Required index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| O1 | My orders — `firestore_order_repository.dart:29-47` | `userId EQ` | `createdAt DESC, __name__ ASC` | `[userId, createdAt DESC, __name__ ASC]` | `[userId, createdAt DESC]` ends `__name__ DESC` | **Added 1** |
| O2 | Order by number — `firestore_order_repository.dart:57-70` | `orderNumber EQ`; `limit(1)` | none | none — equality-only | — | **Unnecessary** |
| O3 | Admin order queue — `firestore_admin_repository.dart:294-322` | optional `status EQ`, `paymentStatus EQ`, `deliveryMode EQ`, `userId EQ`; optional `createdAt >= / <=` | `createdAt DESC, __name__ ASC` | merge set: `[createdAt DESC, __name__ ASC]`, `[status, createdAt DESC, __name__ ASC]`, `[paymentStatus, …]`, `[deliveryMode, …]`, `[userId, …]` | every existing order index ends `__name__ DESC` for these shapes | **Added 5**; all 16 equality combinations verified by the local checker |
| O4 | Admin exact order-number search — `:284-293` | `orderNumber EQ` | none | none — equality-only | — | **Unnecessary** |
| O5 | Payment record read — `firestore_order_repository.dart:111-113` | document get | none | none | — | **Not applicable** |

### 4.5 Users, inventory, audit

| ID | Query / source | Filters | Order | Required index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| U1 | Admin customer list — `firestore_admin_repository.dart:414-439` | optional `role EQ`; text search client-side | `createdAt DESC, __name__ ASC` | `[createdAt DESC, __name__ ASC]`, `[role, createdAt DESC, __name__ ASC]` | `[role, createdAt DESC]` and the single-field `createdAt DESC` entry both end `__name__ DESC` | **Added 2** |
| U2 | Customer detail — `:443-447` | document get | none | none | — | **Not applicable** |
| I1 | Stock ledger — `firestore_admin_repository.dart:241-248` | `productId EQ`, optional `createdAt >=` | `createdAt DESC` | `[productId, createdAt DESC]` | **matches** (range and sort share the field) | **Existing** |
| I2 | Low-stock report — `:255-264` | `status EQ`; threshold applied in Dart | `stockQty ASC` | `[status, stockQty ASC]` | **matches** | **Existing** |
| A1 | Audit log — `firestore_admin_repository.dart:586-599` | optional `entityType EQ`, `action EQ`, `actorUid EQ`; optional `createdAt >= / <=` | `createdAt DESC, __name__ ASC` | merge set: `[createdAt DESC, __name__ ASC]`, `[entityType, …]`, `[action, …]`, `[actorUid, …]` | all existing audit indexes end `__name__ DESC` | **Added 4**; all 8 equality combinations verified |

### 4.6 Notifications, support, wholesale, coupons, addresses, customer pricing

| ID | Query / source | Filters | Order | Required index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| N1 | Notification stream — `firestore_account_repository.dart:216-222` | `uid EQ` | `createdAt DESC` | `[uid, createdAt DESC]` | **matches** | **Existing** |
| N2 | Mark-all-read — `:235-240` | `uid EQ`, `isRead EQ false` | none | none — equality-only | `[uid, isRead, createdAt]` retained but not needed by this query | **Unnecessary** |
| S1 | My support tickets — `:279-284` | `uid EQ` | `createdAt DESC` | `[uid, createdAt DESC]` | **matches** | **Existing** |
| S2 | Support reply — `:288-300` | array update/write | none | none | — | **Not applicable** |
| W1 | Wholesale queue — `firestore_admin_repository.dart:470-475` | `status EQ` when `openOnly` | `createdAt DESC` | `[status, createdAt DESC]`; unfiltered uses automatic `createdAt DESC` | **matches** | **Existing** |
| K1 | Coupon list — `:542-544` | none | none | none | `[isActive, createdAt DESC]` retained but currently unused | **Unnecessary** |
| AD1 | Address book / default reset — `firestore_account_repository.dart:34-36,84-106` | `uid EQ` | none / client sort | none — equality-only | — | **Unnecessary** |
| X1 | Customer price list (Functions) — `functions/index.js:1128-1130` | optional `productId EQ`, `uid EQ` | none | none — equality-only | `[uid, productId]` retained | **Unnecessary** |

### 4.7 Cloud Functions

| ID | Query / source | Filters | Order | Required index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| F1 | Dashboard best sellers — `functions/index.js:1316` | `status EQ active` | `soldCount DESC` | `[status, soldCount DESC]` | **matches** (no explicit documentId order) | **Existing** |
| F2 | Dashboard counts — `functions/index.js:1306-1315` | single field equality / range (`createdAt >=`, `status ==`, `status in`, `paymentStatus ==`) | none | automatic single-field indexes | — | **Unnecessary** |
| F3 | Admin reports — `functions/index.js:1194,1371` | optional `createdAt >=` | none | automatic single-field index | — | **Unnecessary** |
| F4 | Publish product snapshot — `functions/index.js:1563,1579,1591` | two equality fields (`productId`+`status`, `categoryId`+`status`, `productId`+`isActive`) | none | none — equality-only | existing composites retained | **Unnecessary** |
| F5 | Duplicate review check — `functions/index.js:927` | `productId EQ`, `uid EQ`; `limit(1)` | none | none — equality-only | `[productId, uid]` retained | **Unnecessary** |
| F6 | Category/product reference checks — `functions/index.js:1170-1171` | single equality | none | automatic single-field | — | **Unnecessary** |

### 4.8 Media and other Firestore reads

| ID | Query / source | Filters | Order | Required index | Existing match | Verdict |
|---|---|---|---|---|---|---|
| M1 | Media ledger pagination — `lib/app/core/services/media/media_object_ledger.dart:452`; `lib/data/repositories/supabase/supabase_media_repository.dart:531,594` | collection filter only | `documentId` | none — document-id order uses the automatic `__name__` index | — | **Unnecessary** |

### 4.9 Audit reconciliation

| Audit §C5 item | Resolution |
|---|---|
| 1–3 (retail price/best-selling/rating sorts) | Covered by the P1–P5 merge sets (34 definitions), not one combined index per filter combination. |
| 4 (suggestions) | One retail index added (`[status, isWholesaleOnly, name ASC]`); entitled path already existed. The audit's "status+isWholesaleOnly+name" combined form is not required because equality merging applies. |
| 5–8 (single-category sorts) | `categorySlug` members of P1–P5. |
| 9–12 (multi-category / related) | `categoryId` members of P1–P5 plus the retail related index (P15). |
| 13–15 (home shelves) | Three retail shelf indexes added; three entitled indexes already existed. |
| 16 (keywords) | Five `keywords AC` merge members, one per sort shape. |
| 17 (tags) | Five `tags AC` merge members, one per sort shape. |
| 18 (wishlist/cart hydration) | **Not needed**: `__name__ in` + equality filters are equality-only and merge automatic indexes. Flagged for staging confirmation. |
| 19 (order queues) | Five order indexes added, including the `deliveryMode` and `userId` filters the audit named; existing indexes were in the wrong `__name__` direction for the current paginated queries. |
| 20 (audit actor) | Four audit indexes added, including `actorUid`. |

## 5. Added definitions (52)

### 5.1 Storefront catalogue merge sets — 34

For each sort suffix, one index per filter field. Equality fields use `ASCENDING` (direction is irrelevant for equality); `tags`/`keywords` use `arrayConfig: CONTAINS`.

| Sort suffix | Filter fields | Count |
|---|---|---:|
| `soldCount DESC, __name__ ASC` | status, categoryId, categorySlug, isWholesaleOnly, isFeatured, tags, keywords | 7 |
| `createdAt DESC, __name__ ASC` | same seven | 7 |
| `retailPricePaise ASC` (implicit `__name__ ASC`) | categoryId, categorySlug, isWholesaleOnly, isFeatured, tags, keywords (status already existed) | 6 |
| `retailPricePaise DESC, __name__ ASC` | same seven | 7 |
| `ratingAvg DESC, __name__ ASC` | same seven | 7 |
| | | **34** |

### 5.2 Non-paginated storefront reads — 5

| # | Index |
|---|---|
| 1 | `products`: `status, isWholesaleOnly, isFeatured, createdAt DESC` |
| 2 | `products`: `status, isWholesaleOnly, isNewArrival, createdAt DESC` |
| 3 | `products`: `status, isWholesaleOnly, isBestSeller, soldCount DESC` |
| 4 | `products`: `status, isWholesaleOnly, categoryId, soldCount DESC` |
| 5 | `products`: `status, isWholesaleOnly, name ASC` |

These are direct composite indexes rather than merge-dependent because they are the highest-traffic storefront reads and the docs warn that array/equality merging can cost latency. No array field is involved here.

### 5.3 Admin and account surfaces — 13

| # | Collection | Index |
|---|---|---|
| 1 | products | `updatedAt DESC, __name__ ASC` |
| 2 | products | `status, updatedAt DESC, __name__ ASC` |
| 3 | orders | `userId, createdAt DESC, __name__ ASC` |
| 4 | orders | `status, createdAt DESC, __name__ ASC` |
| 5 | orders | `paymentStatus, createdAt DESC, __name__ ASC` |
| 6 | orders | `deliveryMode, createdAt DESC, __name__ ASC` |
| 7 | orders | `createdAt DESC, __name__ ASC` |
| 8 | audit_logs | `entityType, createdAt DESC, __name__ ASC` |
| 9 | audit_logs | `action, createdAt DESC, __name__ ASC` |
| 10 | audit_logs | `actorUid, createdAt DESC, __name__ ASC` |
| 11 | audit_logs | `createdAt DESC, __name__ ASC` |
| 12 | users | `createdAt DESC, __name__ ASC` |
| 13 | users | `role, createdAt DESC, __name__ ASC` |

## 6. Missing, ambiguous or blocked query shapes

1. **Two or more tag chips produce an invalid Firestore query.** `catalog_query_builder.dart:45-48` loops over `query.tags.take(5)` and adds one `arrayContains` per tag; `CatalogController.toggleTag` (`catalog_controller.dart:125-131`) allows multi-select. Firestore permits only one array operator per query. No composite index can make this valid. Fixing it requires a Flutter/business-logic change, which Phase 2A forbids; the UI should either cap tags at one or combine tags into a single array-contains-any of a derived field.
2. **Tag + search is invalid for the same reason.** One `tags AC` and one `keywords AC-any` cannot coexist. The UI can set both.
3. **`wholesaleOnly == true` never reaches Firestore.** The builder only translates `== false` (`catalog_query_builder.dart:43`); the switch at `search_filter_panel.dart:157-162` sets `true`, which is a no-op for wholesale-entitled users and is forced to `false` for retail. This is a functional defect, not an index gap. The `isWholesaleOnly` indexes cover either value if the builder is fixed.
4. **`forProduct(publishedOnly: false)` has no caller and no index.** If a staff review-history view is added, create `[productId, createdAt DESC]`.
5. **Audit actor/date filters are not wired in the UI.** `AuditController` exposes only entity and action; `AdminRepository.auditLogs` accepts `actorUid`, `from`, `to`. The indexes are present for the full repository contract; the UI gap remains.
6. **Array-contains merging is valid but performance-sensitive per Firebase docs.** This file relies on merging for tag/keyword queries instead of creating every tag × category × featured × sort composite. Staging should measure search/tag latency; if it is unacceptable, add combined array indexes only for the measured shapes.
7. **`in` limits.** `categoryId in` is trimmed to 30 descendants and wishlist hydration chunks at 30 ids. A category tree with more than 30 descendants in one request is not fully covered by the `in` path; the resolver does not paginate that set.
8. **Price bounds are intentionally client-side in some shapes** (search, tag, multi-category, non-price sorts). Those queries do not need a price-range index, but they do return a page before filtering, so page sizes can look short. This is existing behavior (`catalog_query_builder.dart:65-86,172-180`), not changed here.

## 7. Local verification

All commands below were run from `D:\event_shop` unless noted. Outputs are verbatim summaries.

### 7.1 Backup identity

```text
$ sha256sum firestore.indexes.json firestore.indexes.json.backup-20261021-phase2a
68211cf5c91d98b29031720c64b9642ddbf28ce4372fc67cbef67de0325bed77 *firestore.indexes.json
68211cf5c91d98b29031720c64b9642ddbf28ce4372fc67cbef67de0325bed77 *firestore.indexes.json.backup-20261021-phase2a
```

The first line was taken before the rewrite. After the rewrite the working file hashes to `7ad51d2f74358fcd32609469cff8b15b781ddaa0b22de1c409b12edb0faf8526`.

### 7.2 JSON parse + firebase-tools schema

```text
firestore.indexes.json.backup-20261021-phase2a: JSON OK, definitions=50, firebase-tools schema=INVALID
  -> Must contain "fields": {"collectionGroup":"products","queryScope":"COLLECTION","indexes":[...]}
firestore.indexes.json: JSON OK, definitions=102, firebase-tools schema=VALID
```

The validator was the installed `firebase-tools@15.23.0` (`FirestoreApi.validateSpec`), not a hand-written schema check.

### 7.3 Generator / duplicate check

```text
existing=50 added=52 total=102
counts={"products":62,"product_variants":2,"categories":3,"orders":10,"reviews":3,
        "inventory_movements":2,"audit_logs":7,"notifications":2,"support_requests":2,
        "wholesale_applications":2,"users":5,"coupons":1,"customer_price_overrides":1}
duplicateSignatures=0
```

The duplicate check processes each index the same way `firebase-tools` does: append `__name__` in the last ordered field's direction when it is absent, then compare the full signature. This catches the case where `[status, soldCount DESC]` and `[status, soldCount DESC, __name__ ASC]` look different in JSON but are different indexes, and the case where two JSON entries collapse to the same processed index.

### 7.4 Query-shape coverage checker

```text
PASS firebase-tools validateSpec
PASS query-shape coverage (catalog/shelves/admin/orders/audit/users/legacy reads)
PASS every added index is used by at least one enumerated query shape
total=102
```

The checker enumerates 180 retail/wholesale catalogue combinations (2 retail states × 5 sorts × 3 category shapes × 2 featured states × 3 array states), 10 shelf/related/suggestion shapes, 16 admin-order filter combinations, 8 audit combinations, 2 customer-role shapes, and the legacy reads. It models Firestore's documented equality/array merging: an index is a candidate when its non-`__name__` fields are all query filters and its tail equals the query's sort suffix; the union of candidate filter fields must cover every filter. It also asserts that every added index is used by at least one enumerated shape, so no speculative index was added.

### 7.5 Relevant local suites (no application code changed)

```text
(cwd: functions) $ npm test
ℹ tests 104
ℹ pass 104
ℹ fail 0

(cwd: functions) $ npm run check:pricing
All pricing.js fixture cases match the shared expected figures.

(cwd: functions) $ npm run check:replay-guard
29/29 assertions passed.

$ git diff --check -- firestore.indexes.json
(no output)
```

Not run, with reasons:

- Flutter analyze/test: no Dart file changed.
- Rules emulator suite: `firestore.rules` unchanged, and the emulator does not enforce composite indexes; re-running 39/39 would not test this change.
- Functions emulator integration suite: requires the local emulator and does not exercise production index planning; the unit suite and static checkers were run instead.

### 7.6 What local verification does and does not prove

It proves:

- The file is valid JSON and valid under the installed CLI's index schema.
- All 50 original definitions survive the schema conversion.
- No two definitions process to the same index.
- Every enumerated query shape has a direct or documented merge path in the static model.
- No index was added that the enumerated shapes do not use.

It does **not** prove:

- That a production or staging Firestore project will build all 102 indexes successfully.
- That the query planner will merge the intended indexes for every combination.
- That array-contains merging performs acceptably.
- That indexes are deployed. None were.

## 8. Staging verification still required

These steps need a non-production Firebase project and were **not** performed:

1. Deploy only the index definitions to staging: `firebase deploy --only firestore:indexes --project <staging-project>` (approval required; not run here).
2. Wait for every index to reach `READY`; inspect `firebase firestore:indexes --project <staging-project>` for failures and count 102.
3. Exercise, with real data in staging:
   - every storefront sort (popular, newest, price low/high, best selling, top rated);
   - a leaf category (slug), a parent category (id `in`), featured-only, one tag, and a search term;
   - the three home shelves and related products as a retail/anonymous user;
   - the admin product list, order queue (all four filters, alone and combined), customer list and audit filters;
   - wishlist/cart hydration (`__name__ in` + equality) and suggestions.
4. Confirm none returns a `failed-precondition` index-creation link. If one does, capture the link's suggested fields and reconcile it with this matrix before adding anything.
5. Measure tag/keyword search latency. If merge latency is unacceptable, add combined array indexes only for the measured shapes.
6. Confirm the Firestore console shows the expected composite count and no unexpected duplicate single-field composites.
7. Three legacy entries declare a single field (`categories.slug`, `orders.createdAt DESC`, `users.createdAt DESC`). They are redundant with Firestore's automatic single-field indexes and are not relied on by any current query. They were retained to avoid deleting existing definitions in an add-only phase. If staging reports them as duplicates or rejects them, remove them in a follow-up cleanup before the production deploy.

The local emulator cannot substitute for this: it does not require composite indexes, so a green emulator run proves rules legality, not index availability.

## 9. Follow-ups recorded, intentionally not changed

1. **Duplicate product lines in one order may over-reserve stock.** If the same product appears on multiple order lines, each line may be validated against the same pre-decrement balance. Recommendation: add a transaction regression test with duplicate lines, then fix the aggregation. Not changed in Phase 2A.
2. **Monthly order counters can duplicate order numbers across months.** The visible order number includes the year but not the month, so a counter reset each month can produce the same visible number in two months. Recommendation: decide the numbering format (include month, or use a monotonic counter) and add regression tests. Not changed in Phase 2A.

## 10. Integrity statement

No production access, deployment, cloud mutation, rules change, Functions change, Flutter change, billing change or Console change was made. The only writes were the local index file, its backup, this document, and temporary generator/verifier scripts outside the repository. No index is claimed to be deployed or ready.
