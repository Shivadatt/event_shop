import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/utils/om_slug.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/product.dart';

/// SEO primitives shared by the storefront shell, the document-head writer and the sitemap/robots
/// generators.
///
/// This layer is deliberately pure data: it produces strings, numbers and `Map`s and never touches
/// `dart:html` or a plugin, so it is unit-testable on the VM and the same builders can be reused
/// by a prerenderer or a Cloud Function.
abstract final class OmSeo {
  OmSeo._();

  static const String siteName = 'OM Events And Decorators';
  static const String tagline = 'Wholesale & Party Supplies';

  /// `<title>` of the home page, and the brand suffix every other title inherits.
  static const String defaultTitle = '$siteName — $tagline';

  /// The value `Env.siteUrl` falls back to when the build supplies none. It is a documentation
  /// placeholder, never a real origin, and nothing indexable may be emitted with it.
  static const String placeholderOrigin = 'https://omevents.example';

  /// Deploy-time token used in `web/index.html`, `web/robots.txt` and `web/sitemap.xml`. It is a
  /// deliberate non-value: a build that ships it unsubstituted is caught by
  /// `test/seo/om_seo_test.dart`.
  static const String siteOriginToken = '{{SITE_ORIGIN}}';

  static const int maxTitleLength = 60;
  static const int maxDescriptionLength = 158;

  /// Trailing slashes and query strings never belong in a canonical URL.
  static String normalizePath(String path) {
    final withoutQuery = path.split('?').first.split('#').first;
    if (withoutQuery.isEmpty || withoutQuery == '/') return '/';
    final withLeading = withoutQuery.startsWith('/') ? withoutQuery : '/$withoutQuery';
    final trimmed = withLeading.endsWith('/')
        ? withLeading.substring(0, withLeading.length - 1)
        : withLeading;
    return trimmed.isEmpty ? '/' : trimmed;
  }

  /// `https://shop.example` (never `https://shop.example/`). A path or full URL passed in is
  /// reduced to its origin.
  static String originOf(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final scheme = uri.scheme.toLowerCase();
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://${uri.host}$port';
    }
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  /// The configured site origin, or the placeholder when `SITE_URL` was not supplied.
  static String get configuredOrigin => originOf(Env.siteUrl);

  /// True only when `SITE_URL` is a real HTTPS origin: an empty value, the compiled-in default, or
  /// any reserved `.example` domain means "not configured" and must keep the site unindexed rather
  /// than publishing a canonical that points at nobody's store.
  static bool get hasRealSiteOrigin {
    final origin = configuredOrigin;
    if (origin.isEmpty || origin == placeholderOrigin) return false;
    if (!origin.startsWith('https://')) return false;
    if (origin.endsWith('.example') || origin.endsWith('.example.com')) return false;
    if (origin.contains(siteOriginToken)) return false;
    return true;
  }

  /// Canonical/absolute URL for a path. Returns the path unchanged when the origin is not
  /// configured, so a misconfigured build degrades to relative links instead of publishing a fake
  /// domain to Google.
  static String absoluteUrl(String path) {
    final normalized = normalizePath(path);
    if (!hasRealSiteOrigin) return normalized;
    return '$configuredOrigin$normalized';
  }

  /// `OmRoutes.forProduct`, `/product/balloon-arch-12ft`. The slug is stable because it comes from
  /// [Product.pathSlug], which falls back to the document id when a product predates slugs.
  static String productPath(Product product) => OmRoutes.forProduct(product.pathSlug);

  static String categoryPath(Category category) => OmRoutes.forCategory(category.pathSlug);

  static String absoluteProductUrl(Product product) => absoluteUrl(productPath(product));

  static String absoluteCategoryUrl(Category category) => absoluteUrl(categoryPath(category));

  /// A slug usable in a URL, always `OmSlug.isValid`-clean and within the length limit. The
  /// engine trims rather than trusting the caller, because a 300-character product name would
  /// otherwise produce a slug search engines refuse to canonicalise.
  static String stableSlug(String input, {String fallback = 'item'}) {
    final slug = OmSlug.from(input);
    final capped = slug.length <= maxSlugLength ? slug : _trimTo(slug, maxSlugLength);
    return OmSlug.isValid(capped) ? capped : fallback;
  }

  static const int maxSlugLength = 96;

  static String _trimTo(String value, int limit) {
    var cut = value.substring(0, limit);
    final lastDash = cut.lastIndexOf('-');
    if (lastDash > limit * 0.6) cut = cut.substring(0, lastDash);
    return cut.replaceAll(RegExp(r'-+$'), '');
  }

  /// Title: explicit SEO title, else the entity name, always with the brand suffix unless the
  /// author already wrote it in. Capped at [maxTitleLength] so SERPs do not truncate mid-word.
  static String title({
    String? seoTitle,
    String? primary,
    String? secondary,
    bool includeBrand = true,
  }) {
    final explicit = (seoTitle ?? '').trim();
    final base = explicit.isNotEmpty
        ? explicit
        : <String>[
            (primary ?? '').trim(),
            (secondary ?? '').trim(),
          ].where((part) => part.isNotEmpty).join(' · ');
    final candidate = base.isEmpty
        ? defaultTitle
        : (includeBrand && !_mentionsBrand(base)
              ? '$base | $siteName'
              : base);
    return _clamp(candidate, maxTitleLength);
  }

  static bool _mentionsBrand(String value) {
    final lower = value.toLowerCase();
    return lower.contains('om events') || lower.contains(siteName.toLowerCase());
  }

  /// Meta description: explicit SEO text, else the first sentence of the body copy. Empty input
  /// yields an empty string — a missing description must stay visibly missing rather than be
  /// padded with generic filler that Google ignores anyway.
  static String description({
    String? seoDescription,
    String? body,
    String? fallback,
  }) {
    final explicit = (seoDescription ?? '').trim();
    if (explicit.isNotEmpty) return _clamp(explicit, maxDescriptionLength);
    final prose = (body ?? '').trim();
    if (prose.isNotEmpty) return _clamp(_firstSentence(prose), maxDescriptionLength);
    return _clamp((fallback ?? '').trim(), maxDescriptionLength);
  }

  static String _firstSentence(String value) {
    final single = value.replaceAll(RegExp(r'\s+'), ' ');
    final stop = single.indexOf('. ');
    return stop > 40 ? single.substring(0, stop + 1) : single;
  }

  static String _clamp(String value, int limit) {
    if (value.length <= limit) return value;
    final slice = value.substring(0, limit - 1);
    final space = slice.lastIndexOf(' ');
    return '${space > limit * 0.5 ? slice.substring(0, space) : slice}…';
  }

  /// Paise → plain decimal rupees for JSON-LD (`199500` -> `1995.00`).
  ///
  /// JSON-LD `price` must be a decimal number with no currency glyph, no thousands separators and
  /// no float error, so this builds from integer arithmetic rather than `paise / 100.0`.
  static String rupeeAmount(int paise) {
    final negative = paise < 0;
    final abs = paise.abs();
    final rupees = (abs ~/ 100).toString();
    final fraction = (abs % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$rupees.$fraction';
  }

  /// Rating values are the one JSON-LD number that legitimately carries a decimal average; clamp
  /// to the 1..5 range Google's Product rich result expects and to one decimal place.
  static String ratingValue(double average) {
    if (average <= 0) return '0.0';
    final clamped = average > 5 ? 5.0 : average;
    final tenths = (clamped * 10).round();
    return '${tenths ~/ 10}.${tenths % 10}';
  }

  static String absoluteImage(String url, {String? fallbackPath}) {
    if (url.isEmpty) return fallbackPath == null ? '' : absoluteUrl(fallbackPath);
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return url.startsWith('/') ? '$configuredOrigin${url.replaceAll('//', '/')}' : url;
  }

  /// Strips control characters and collapses whitespace so a description authored in the admin
  /// panel cannot smuggle a newline (and therefore a broken `<meta>` tag) into the head.
  static String sanitize(String value) =>
      value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}
