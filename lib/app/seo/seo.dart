/// One import for everything the SEO layer offers:
///
/// ```dart
/// import 'package:om_events/app/seo/seo.dart';
/// ```
///
/// Screens use [OmSeo] for URLs/titles, [OmRouteMeta] for the indexing decision of their own route,
/// [OmJsonLd] for structured data and [OmSeoDocuments] for the static `robots.txt` / `sitemap.xml`
/// bodies. Nothing in this layer reads Firestore; pass the already-loaded [StoreSettings] or
/// [Product] in.
library;

export 'package:om_events/app/seo/json_ld.dart';
export 'package:om_events/app/seo/om_seo.dart';
export 'package:om_events/app/seo/page_meta.dart';
export 'package:om_events/app/seo/route_meta.dart';
export 'package:om_events/app/seo/seo_documents.dart';
