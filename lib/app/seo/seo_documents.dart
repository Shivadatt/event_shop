import 'dart:convert';

import 'package:om_events/app/seo/json_ld.dart';
import 'package:om_events/app/seo/om_seo.dart';
import 'package:om_events/app/seo/page_meta.dart';
import 'package:om_events/app/seo/route_meta.dart';
import 'package:om_events/data/models/store_settings.dart';

/// One `<url>` entry of `sitemap.xml`.
final class SitemapUrl {
  const SitemapUrl({
    required this.path,
    this.lastModified,
    this.changeFrequency = 'weekly',
    this.priority,
  });

  /// Root-relative path, e.g. `/product/balloon-arch`. Never a full URL: the origin is applied
  /// once, by the generator, so a stray absolute path cannot produce a duplicate entry.
  final String path;
  final DateTime? lastModified;
  final String changeFrequency;
  final double? priority;

  /// Sitemap values must be ISO-8601 in UTC to the second; a locale-formatted date makes the whole
  /// file unparseable and Google reports "couldn't fetch".
  String get lastModifiedIso {
    final at = lastModified;
    if (at == null) return '';
    final iso = at.toUtc().toIso8601();
    final fraction = iso.indexOf('.');
    final trimmed = fraction >= 0
        ? iso.substring(0, fraction)
        : iso.endsWith('Z')
            ? iso.substring(0, iso.length - 1)
            : iso;
    return '${trimmed}Z';
  }

  String get priorityText {
    final p = priority;
    if (p == null) return '';
    return p.toStringAsFixed(1);
  }
}

/// Generators for the two static files a crawler reads before it runs any JavaScript.
///
/// Both refuse to emit a document for an unconfigured origin. A sitemap of `{{SITE_ORIGIN}}/...`
/// URLs is worse than no sitemap: it is a crawl-error in Search Console the shop has to clean up
/// later, and robots.txt that points at it makes the mistake permanent.
abstract final class OmSeoDocuments {
  OmSeoDocuments._();

  /// Crawl-delay is intentionally absent: Google ignores it and Bing honours it per-host, so a
  /// value here only slows other people's bots, not the shop's own traffic.
  static const String _userAgentBlock = 'User-agent: *';

  /// `robots.txt` body. `extraDisallow` is for query-string patterns (cart params, print views)
  /// that a route table cannot express.
  static String robotsTxt({
    String origin = '',
    List<String> extraDisallow = const <String>[],
    bool allowAdmin = false,
  }) {
    final disallowed = <String>{
      if (!allowAdmin) ...OmRouteMeta.disallowedPaths,
      ...extraDisallow,
    }.toList()..sort();

    final lines = <String>[
      '# OM Events And Decorators — wholesale and party supplies.',
      '# Rendered by OmSeoDocuments.robotsTxt; keep in sync with lib/app/seo/route_meta.dart.',
      _userAgentBlock,
      ...disallowed.map((path) => 'Disallow: ${OmSeo.normalizePath(path)}'),
      // Faceted and paginated catalogue URLs are crawl traps; the app keeps them indexable but
      // robots refuses the parameterised form so the budget goes to canonical pages.
      'Disallow: /*?add=',
      'Disallow: /*?remove=',
      'Disallow: /*?sort=price',
      '',
    ];

    final resolvedOrigin = origin.isEmpty ? OmSeo.configuredOrigin : OmSeo.originOf(origin);
    if (OmSeo.hasRealSiteOrigin || _isSubstituted(resolvedOrigin, origin)) {
      lines.add('Sitemap: $resolvedOrigin/sitemap.xml');
    } else {
      lines.add('# Sitemap: $resolvedOrigin/sitemap.xml');
      lines.add('# Not published: SITE_URL was not supplied at build time. Rebuild with '
          '--dart-define=SITE_URL=https://your-domain, or substitute '
          '${OmSeo.siteOriginToken} during deployment, and regenerate this file.');
    }
    return lines.join('\n');
  }

  /// `sitemap.xml`. Throws when the origin is not a real, substituted host, so a misconfigured
  /// build cannot silently publish placeholder URLs.
  static String sitemapXml({
    required List<SitemapUrl> urls,
    String origin = '',
    StoreSettings settings = StoreSettings.fallback,
  }) {
    final resolvedOrigin = origin.isEmpty ? OmSeo.configuredOrigin : OmSeo.originOf(origin);
    final usable = OmSeo.hasRealSiteOrigin || _isSubstituted(resolvedOrigin, origin);
    if (!usable) {
      throw StateError(
        'Cannot generate a sitemap: the site origin is "$resolvedOrigin", which is either the '
        'compiled-in placeholder or the unreplaced ${OmSeo.siteOriginToken} token. Supply '
        'SITE_URL or substitute the token at deploy time.',
      );
    }

    final body = <String>[];
    for (final url in urls) {
      if (!OmRouteMeta.forPath(url.path).isIndexable) continue;
      final loc = '$resolvedOrigin${OmSeo.normalizePath(url.path)}';
      body.add('  <url>');
      body.add('    <loc>$loc</loc>');
      if (url.lastModifiedIso.isNotEmpty) {
        body.add('    <lastmod>${url.lastModifiedIso}</lastmod>');
      }
      body.add('    <changefreq>${url.changeFrequency}</changefreq>');
      if (url.priorityText.isNotEmpty) {
        body.add('    <priority>${url.priorityText}</priority>');
      }
      body.add('  </url>');
    }

    return <String>[
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
      ...body,
      '</urlset>',
      '',
    ].join('\n');
  }

  /// The static paths a catalogue-derived sitemap always begins with.
  static List<SitemapUrl> staticUrls({
    StoreSettings settings = StoreSettings.fallback,
    DateTime? updatedAt,
  }) {
    final modified = updatedAt ?? settings.updatedAt;
    return OmRouteMeta.indexableStaticPaths.map((path) {
      final isHome = path == '/';
      return SitemapUrl(
        path: path,
        lastModified: modified,
        changeFrequency: isHome ? 'daily' : 'weekly',
        priority: isHome ? 1.0 : 0.7,
      );
    }).toList(growable: false);
  }

  /// The seed blocks for `web/index.html` before any Firestore read has happened.
  static String bootstrapJsonLd({
    StoreSettings settings = StoreSettings.fallback,
    String? logoUrl,
  }) {
    final blocks = OmJsonLd.bootstrapBlocks(settings: settings, logoUrl: logoUrl);
    return blocks.map(_jsonBlock).join('\n');
  }

  static String _jsonBlock(Map<String, Object?> object) {
    final encoded = jsonEncode(_withoutNulls(object));
    // A JSON-LD block must never be able to close itself early: a `</script>` inside a string value
    // would end the block and start arbitrary markup.
    return '<script type="application/ld+json">'
        '${encoded.replaceAll('</', r'<\/')}'
        '</script>';
  }

  /// `null` has no meaning in schema.org and Google's parser reports it as an unknown property, so
  /// absent values are stripped rather than serialised.
  static Object? _withoutNulls(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.value != null) '${entry.key}': _withoutNulls(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_withoutNulls).toList(growable: false);
    }
    return value;
  }

  /// Head tags for one rendered page, in the order a document writer should apply them.
  static List<String> headTagsFor({
    required PageMeta meta,
    required String path,
    String? title,
    String? description,
    List<String> images = const <String>[],
    List<Map<String, Object?>> jsonLd = const <Map<String, Object?>>[],
  }) {
    final document = OmDocumentMeta(
      title: title ??
          meta.titleFor(primary: OmSeo.siteName, secondary: OmSeo.tagline),
      description: description ?? meta.descriptionFor(),
      path: path,
      noIndex: meta.noIndex,
      ogType: meta.ogType,
      imageUrls: images,
      jsonLd: jsonLd,
    );
    return <String>[
      '<title>${document.title}</title>',
      ...document.tags.map((tag) => tag.toHtml()),
    ];
  }

  /// True when `value` is a host the deployment actually substituted.
  static bool _isSubstituted(String value, String requested) {
    if (requested.isEmpty) return false;
    if (value.contains(OmSeo.siteOriginToken)) return false;
    return value.startsWith('https://');
  }
}
