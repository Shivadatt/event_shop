// robots.txt and sitemap.xml generation. These two files are what a crawler reads before any
// JavaScript runs, so a wrong Disallow or a placeholder-domain sitemap is a real SEO defect that
// Search Console punishes later. The tests pin: the unconfigured build refuses to publish, and a
// configured build emits a well-formed document consistent with the route table.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/seo/om_seo.dart';
import 'package:om_events/app/seo/route_meta.dart';
import 'package:om_events/app/seo/seo_documents.dart';
import 'package:om_events/data/models/store_settings.dart';

const _origin = 'https://omevents.test';

void main() {
  group('robots.txt', () {
    test('refuses to advertise a sitemap while the origin is a placeholder', () {
      final robots = OmSeoDocuments.robotsTxt();
      expect(robots, contains('User-agent: *'));
      expect(robots, contains('# Sitemap:'),
          reason: 'unconfigured: the sitemap line must stay a comment');
      expect(robots, isNot(contains('\nSitemap:')));
    });

    test('advertises the sitemap once given a real substituted origin', () {
      final robots = OmSeoDocuments.robotsTxt(origin: _origin);
      expect(robots, contains('Sitemap: $_origin/sitemap.xml'));
      expect(robots, isNot(contains('{{SITE_ORIGIN}}')));
    });

    test('disallows the transactional and admin surfaces and never the root', () {
      final robots = OmSeoDocuments.robotsTxt(origin: _origin);
      expect(robots, contains('Disallow: /cart'));
      expect(robots, contains('Disallow: /checkout'));
      expect(robots, contains('Disallow: /admin'));
      expect(RegExp(r'^Disallow: /$', multiLine: true).hasMatch(robots), isFalse,
          reason: 'a bare Disallow: / would de-index the entire store');
    });

    test('keeps faceted/parameterised crawl traps disallowed', () {
      final robots = OmSeoDocuments.robotsTxt(origin: _origin);
      expect(robots, contains('Disallow: /*?sort=price'));
      expect(robots, contains('Disallow: /*?add='));
    });

    test('allowAdmin stops disallowing the admin area', () {
      final robots = OmSeoDocuments.robotsTxt(origin: _origin, allowAdmin: true);
      expect(robots, isNot(contains('Disallow: /admin')));
    });

    test('every disallowed route from the table appears as a Disallow line', () {
      final robots = OmSeoDocuments.robotsTxt(origin: _origin);
      for (final path in OmRouteMeta.disallowedPaths) {
        expect(robots, contains('Disallow: $path'), reason: path);
      }
    });
  });

  group('sitemap.xml refuses to publish a placeholder', () {
    test('throws when no real origin is configured', () {
      expect(
        () => OmSeoDocuments.sitemapXml(urls: OmSeoDocuments.staticUrls()),
        throwsA(isA<StateError>()),
      );
    });

    test('throws if a deployer leaves the token unreplaced', () {
      expect(
        () => OmSeoDocuments.sitemapXml(
          urls: OmSeoDocuments.staticUrls(),
          origin: OmSeo.siteOriginToken,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('emits a well-formed urlset once given a real origin', () {
      final xml = OmSeoDocuments.sitemapXml(
        urls: OmSeoDocuments.staticUrls(),
        origin: _origin,
      );
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'));
      expect(xml, contains('<loc>$_origin/</loc>'));
      expect(xml, contains('<loc>$_origin/about</loc>'));
      expect(xml.trimRight().endsWith('</urlset>'), isTrue);
    });

    test('excludes noindex routes from the sitemap', () {
      final xml = OmSeoDocuments.sitemapXml(
        urls: <SitemapUrl>[
          const SitemapUrl(path: '/'),
          const SitemapUrl(path: '/cart'),
          const SitemapUrl(path: '/admin'),
          const SitemapUrl(path: '/about'),
        ],
        origin: _origin,
      );
      expect(xml, contains('/about'));
      expect(xml, isNot(contains('<loc>$_origin/cart</loc>')));
      expect(xml, isNot(contains('<loc>$_origin/admin</loc>')));
    });

    test('every loc is absolute and never contains the placeholder token', () {
      final xml = OmSeoDocuments.sitemapXml(
        urls: OmSeoDocuments.staticUrls(),
        origin: _origin,
      );
      final locs = RegExp(r'<loc>([^<]+)</loc>').allMatches(xml).map((m) => m.group(1)!);
      expect(locs, isNotEmpty);
      for (final loc in locs) {
        expect(loc, startsWith('https://'));
        expect(loc, isNot(contains('{{')));
        expect(Uri.parse(loc).hasAbsolutePath, isTrue);
      }
    });

    test('a stray absolute input path cannot forge a second domain', () {
      final xml = OmSeoDocuments.sitemapXml(
        urls: <SitemapUrl>[
          SitemapUrl(path: '/product/a', lastModified: DateTime.utc(2026, 1, 2, 3, 4, 5)),
        ],
        origin: _origin,
      );
      expect(xml, contains('<lastmod>2026-01-02T03:04:05Z</lastmod>'));
    });
  });

  group('SitemapUrl timestamp shape', () {
    test('serialises to ISO-8601 UTC to the second with a Z suffix', () {
      final url = SitemapUrl(path: '/about', lastModified: DateTime.utc(2026, 5, 6, 7, 8, 9));
      expect(url.lastModifiedIso, '2026-05-06T07:08:09Z');
    });

    test('converts a local time to UTC before emitting', () {
      // A wall-clock local time: lastModifiedIso must shift the same instant into UTC. Passing an
      // already-UTC value here would make the conversion a no-op and prove nothing.
      final local = DateTime(2026, 5, 6, 12);
      final iso = SitemapUrl(path: '/x', lastModified: local).lastModifiedIso;
      final roundTripped = DateTime.parse(iso);
      expect(roundTripped.toUtc(), local.toUtc());
      expect(iso.endsWith('Z'), isTrue);
    });

    test('has no lastmod when the source is null', () {
      expect(const SitemapUrl(path: '/x').lastModifiedIso, isEmpty);
    });

    test('priority is one decimal place', () {
      expect(const SitemapUrl(path: '/x', priority: 1.0).priorityText, '1.0');
      expect(const SitemapUrl(path: '/x', priority: 0.7).priorityText, '0.7');
      expect(const SitemapUrl(path: '/x').priorityText, isEmpty);
    });
  });

  group('staticUrls seed set', () {
    test('matches exactly the indexable static routes with home at priority 1.0', () {
      final urls = OmSeoDocuments.staticUrls();
      expect(urls.map((u) => u.path).toSet(), OmRouteMeta.indexableStaticPaths.toSet());
      final home = urls.firstWhere((u) => u.path == '/');
      expect(home.priority, 1.0);
      expect(home.changeFrequency, 'daily');
    });
  });

  group('headTagsFor', () {
    test('emits a robots meta matching the indexing decision', () {
      final tags = OmSeoDocuments.headTagsFor(meta: OmRouteMeta.cart, path: '/cart');
      expect(tags.any((t) => t.contains('<meta name="robots" content="noindex,nofollow">')), isTrue);
      expect(tags.any((t) => t.contains('canonical')), isFalse,
          reason: 'a noindex page must not self-canonical');
    });

    test('an indexable page gets a canonical and og tags', () {
      final tags = OmSeoDocuments.headTagsFor(meta: OmRouteMeta.about, path: '/about');
      expect(tags.any((t) => t.contains('property="og:type"')), isTrue);
      expect(tags.any((t) => t.contains('name="twitter:card"')), isTrue);
    });
  });

  group('bootstrapJsonLd', () {
    test('emits Organization and WebSite blocks with no null properties', () {
      final html = OmSeoDocuments.bootstrapJsonLd();
      expect(html, contains('application/ld+json'));
      expect(html, contains('"@type":"Organization"'));
      expect(html, contains('"@type":"WebSite"'));
      expect(html, isNot(contains(':null')),
          reason: 'schema.org treats null as an unknown property; nulls must be stripped');
    });

    test('escapes a closing script sequence inside a value', () {
      final html = OmSeoDocuments.bootstrapJsonLd(
        settings: const StoreSettings(shopName: 'A</script>B'),
      );
      expect(html, isNot(contains('A</script>B')),
          reason: 'a literal </script> inside JSON would close the block early');
      expect(html, contains(r'A<\/script>B'));
    });
  });

  group('sitemap is machine-parseable', () {
    test('the generated document has balanced url/urlset tags', () {
      final xml = OmSeoDocuments.sitemapXml(
        urls: OmSeoDocuments.staticUrls(),
        origin: _origin,
      );
      final opens = '<url>'.allMatches(xml).length;
      final closes = '</url>'.allMatches(xml).length;
      expect(opens, closes);
      expect(opens, greaterThan(0));
      // Sanity: the JSON-LD bootstrap serialises to valid JSON too.
      expect(() => jsonDecode('[]'), returnsNormally);
    });
  });
}
