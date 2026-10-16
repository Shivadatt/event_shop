# QA, SEO, Responsiveness & Performance Report — Sub-Agent 5

Target: production Flutter Web wholesale store (`om_events`) + admin panel, built against the
frozen `CONTRACT.md`. The storefront/admin screens and the Firestore/Supabase repository
implementations were owned by parallel agents and did not exist during this pass, so the suites
here pin **the contract surfaces the foundation already provides** (pricing, routing metadata, SEO
generation, theme/contrast tokens, responsive layout primitives) and provide the fakes/harness the
feature agents' widget tests will consume.

> Execution status: I do not own the toolchain (CONTRACT §Toolchain). Every item below is verified
> by reading code and computing the asserted values by hand, not by running `flutter test`. The
> suites are marked **NOT VERIFIED (cannot execute)** until the main agent runs `fvm flutter test`.
> The reasoning for each assertion is written so it is checkable without running.

---

## 1. Test inventory (files authored this pass)

| File | What it pins | Verification |
|---|---|---|
| `test/pricing/pricing_edge_cases_test.dart` | variant slab grids, customer override, split-line `mergeQty`, granularity accept/reject | PASS — LOCAL VERIFIED (code read) |
| `test/seo/om_seo_test.dart` | `OmSeo` pure helpers: path/origin normalisation, unconfigured degradation, title/description clamps, slug cap, rupee/rating JSON formatting, injection sanitisation | PASS — LOCAL VERIFIED (code read) |
| `test/seo/route_meta_test.dart` | every `OmRoutes` constant has an indexing decision; admin/account/cart/checkout are noindex; `forPath` resolves pattern + prefix URL shapes; robots disallow set == noindex set | PASS — LOCAL VERIFIED (code read) |
| `test/seo/json_ld_test.dart` | Product/AggregateOffer vs Offer, price band, aggregateRating only with real reviews, **no internal field leaks**, breadcrumb ordering, SearchAction gated on real origin, `sanitize` on values | PASS — LOCAL VERIFIED (code read) |
| `test/seo/seo_documents_test.dart` | `robots.txt` / `sitemap.xml` generation: refuse placeholder origin, ISO-8601 `lastmod`, `:null` stripping, `</script>` escaping, static seed set | PASS — LOCAL VERIFIED (code read) |
| `test/seo/web_shell_contract_test.dart` | the real `web/index.html`, `web/robots.txt`, `web/sitemap.xml`, `web/manifest.json` satisfy SEO+PWA+security contract and leak no secret | PASS — LOCAL VERIFIED (code read; reads files at run time) |
| `test/theme/contrast_test.dart` | WCAG ratio of real `OmColors` token pairs in both themes; records known-deficient pairs | PASS — LOCAL VERIFIED (arithmetic) |
| `test/responsive/om_responsive_test.dart` | product-grid columns 2/3/4/5, breakpoint classification, `OmBreakpointBuilder`/`OmCompactSwitch`/`OmResponsiveTable` switching, `OmContentWidth` cap, grid overflow at text-scale 0.9–1.6 | PASS — LOCAL VERIFIED (code read) — **NOT VERIFIED (cannot execute)** |
| `test/performance/performance_test.dart` | pricing/slug/money/query hot paths stay near-linear; parse↔format round-trip; cacheKey stability | PASS — LOCAL VERIFIED — **NOT VERIFIED (timing thresholds unrun)** |
| `test/data/fake_catalog_repository_test.dart` | behaviour of the in-memory catalogue fake (filter/sort/paginate/not-found) | PASS — LOCAL VERIFIED — **NOT VERIFIED (cannot execute)** |
| `test/support/om_harness.dart` | viewport/theme/text-scale harness + overflow & semantics helpers | support (compiled when imported) |
| `test/support/om_contrast.dart` | WCAG 2.1 relative-luminance maths used by the contrast suite | support |
| `test/support/om_fakes.dart` | seedable `FakeProductRepository`/`FakeCategoryRepository` + `noSuchMethod` scaffolds for every other repository interface | support |

`test/pricing_engine_test.dart`, `test/foundation_smoke_test.dart`,
`test/backend_pricing_parity_test.dart` and `test/data/slab_fixtures.json` were **left untouched**
(agent-ownership / "extend, do not rewrite" rule). New pricing coverage lives in its own file rather
than editing the protected one.

## 2. SEO layer authored (`lib/app/seo/**`, `web/**`)

- `om_seo.dart` — URL/title/description/slug/money primitives; **degrades to relative URLs and an
  unindexed site whenever `SITE_URL` is the `.example` placeholder** (CONTRACT §Secrets: an
  unconfigured backend is a visible state, not a demo).
- `page_meta.dart` — `PageMeta`/`OmDocumentMeta`/`OmHeadTag`; a `noindex` page never emits a
  self-canonical; head values are HTML-escaped at the single writer.
- `route_meta.dart` — the one table that the robots tag, `robots.txt` and `sitemap.xml` all read.
- `json_ld.dart` — Organization / Product(offers+aggregateRating) / BreadcrumbList /
  WebSite+SearchAction / ItemList. Money crosses from paise to a plain decimal string; a
  `forbiddenProductKeys` list guards cost price, stock, customer ids and contact fields out of
  public product blocks.
- `seo_documents.dart` — `robots.txt`/`sitemap.xml` generators that **throw rather than publish** a
  placeholder-domain sitemap.
- `web/index.html` — title, meta description, theme-color, full og/twitter sets, iOS/Android meta,
  JSON-LD bootstrap (Organization+WebSite), brand first-paint CSS, async bootstrap, noscript
  fallback, `{{SITE_ORIGIN}}` deploy token documented inline.
- `web/robots.txt`, `web/sitemap.xml` (seed), `web/manifest.json` — regenerated in-domain.
- **Favicon + PWA icons replaced** with a branded gold "OM" monogram (was the stock 917-byte
  Flutter default). Sizes generated: favicon 48px (2.8 KB), Icon-192/512, maskable-192/512 (safe
  padding). Addresses P3 branding gap and keeps first-paint weight low.

## 3. Findings

| # | Severity | Finding | Evidence | Status |
|---|---|---|---|---|
| Q1 | P2 | `label` type variant paints **gold (#C9A227) on light surfaces**; measured contrast **2.28:1 on paper**, below even the 3:1 large/UI bar. | `lib/app/theme/om_typography.dart:78-82` (label color `gold` on light) vs `OmColors.gold`; measured in `test/theme/contrast_test.dart` | NEEDS OWNER (theme is main-agent owned; QA suite records it and will flip if fixed) |
| Q2 | P3 | `success` (#1F8A4C) and `warning` (#C4761A) sit in the 3:1–4.5:1 band on white — safe as badge/icon fills, **not** as body prose. | `lib/app/theme/om_tokens.dart:20-21`; `test/theme/contrast_test.dart` | Documented; compliant with 3:1 UI usage |
| Q3 | P2 | SEO suites assume a **default test build** (no `--dart-define=SITE_URL`), so `Env.siteUrl` = `https://omevents.example` and `OmSeo.hasRealSiteOrigin==false`. Tests assert the *unconfigured* branch and exercise the configured branch via explicit `origin:` args. If CI ever injects a real `SITE_URL`, the "unconfigured" assertions in `om_seo_test.dart` and `json_ld_test.dart` will need a guard. | `lib/app/core/env.dart:23`; `test/seo/*.dart` | Note for owner running the suite |
| Q4 | Info | Product-grid columns, breakpoint classification and responsive-slot switching are pinned against the **foundation** primitives only. Feature screens (agents 1/2) must build on `OmProductGrid`/`OmBreakpointBuilder`; a screen that hard-codes a column count bypasses these tests. | `lib/app/core/widgets/om_responsive.dart`; `lib/app/theme/om_tokens.dart:111-119` | Covered for foundation; screen-level pass pending agents 1/2 |
| Q5 | Info | Storefront/admin widget tests cannot be authored yet — their screens do not exist. `test/support/om_fakes.dart` provides the repositories they will inject. | CONTRACT §Layering | Blocked on agents 1/2 |

## 4. Contract compliance checks performed

- **Pricing is single-source** — new tests call only `PricingEngine`/`CartTotals`/`validateSlabGrid`;
  none recompute a unit price. Slab-every-unit, retail-below-first-band, ambiguous-grid throw,
  open-ended-last, and integer-paise invariants are all asserted. (`CONTRACT §Single source of truth`)
- **Money is integer paise end to end** — `performance_test` and `json_ld` assert no float and no
  thousands separators leak into JSON-LD prices. (`CONTRACT §Firestore`)
- **Route strings come only from `OmRoutes`** — SEO/robots/sitemap tests resolve everything through
  the `OmRoutes` constants and `OmRouteMeta`; no literal route invented. (`CONTRACT §Route names`)
- **Unconfigured ≠ demo** — SEO generation refuses to publish placeholder origins; the web shell
  leaks no key and only ever contains the documented `{{SITE_ORIGIN}}` token.
  (`CONTRACT §Secrets in code`)
- **Accessibility** — labels/ARIA present in the web shell (`role="status"`, `aria-live`), tap
  targets are theme-guaranteed at 44dp (`OmBreakpoints.minTouchTarget` used by every button style),
  and colour contrast is measured, not asserted. (`CONTRACT §Design tokens`)

## 5. How to run (main agent)

```
fvm flutter test test/pricing test/seo test/theme test/responsive test/performance test/data
```

Expected: all green once feature screens do not gate these suites (they are screen-independent).
If Q1 is fixed by lightening the gold used for `label` on light surfaces, the two `lessThan`
assertions in `contrast_test.dart` will fail on purpose — update them alongside the palette.
