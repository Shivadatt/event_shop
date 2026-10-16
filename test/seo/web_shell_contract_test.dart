// The static web shell is what a crawler and a slow-connection customer see before Flutter paints.
// These tests read the real files in web/ and assert they satisfy the SEO, PWA and security
// contract, and — most importantly — that no deployer shipped a secret or an unexplained origin.
//
// The `{{SITE_ORIGIN}}` token is allowed (and expected) in these template files; a real Google API
// key, a JWT, a Firebase service-account or a service-role key is not.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/seo/om_seo.dart';
import 'package:om_events/app/seo/route_meta.dart';

String _read(String relative) {
  final file = File(relative);
  if (!file.existsSync()) {
    fail('$relative not found — run flutter test from the package root.');
  }
  return file.readAsStringSync();
}

bool _covered(List<String> rules, String path) {
  for (final rule in rules) {
    if (rule.isEmpty || rule.contains('?')) continue;
    final clean = rule.endsWith('/') ? rule.substring(0, rule.length - 1) : rule;
    if (path == clean || path.startsWith('$clean/')) return true;
  }
  return false;
}

void main() {
  late String index;
  late String robots;
  late String sitemap;
  late Map<String, dynamic> manifest;

  setUpAll(() {
    index = _read('web/index.html');
    robots = _read('web/robots.txt');
    sitemap = _read('web/sitemap.xml');
    manifest = jsonDecode(_read('web/manifest.json')) as Map<String, dynamic>;
  });

  group('index.html head contract', () {
    test('is a well-formed HTML5 document declared for the Indian locale', () {
      expect(index, contains('<!DOCTYPE html>'));
      expect(index, matches(RegExp(r'<html[^>]*lang="en-IN"')));
      expect(index, contains('<meta charset="UTF-8">'));
    });

    test('has a single non-empty <title> with the brand', () {
      final titles = RegExp(r'<title>(.*?)</title>').allMatches(index).toList();
      expect(titles.length, 1, reason: 'exactly one title in the shell');
      expect(titles.single.group(1), contains('OM Events'));
    });

    test('declares a meta description within the SERP budget', () {
      final match = RegExp(r'<meta name="description"\s+content="([^"]*)"').firstMatch(index);
      expect(match, isNotNull);
      final content = match!.group(1)!;
      expect(content.length, inInclusiveRange(40, OmSeo.maxDescriptionLength + 12));
    });

    test('sets viewport for responsive rendering', () {
      expect(index, matches(RegExp(r'name="viewport"[^>]*width=device-width')));
      expect(index, contains('initial-scale=1'));
    });

    test('declares theme-color matching the brand black', () {
      expect(index, contains('<meta name="theme-color" content="#0B0B0C">'));
      expect(index, contains('color-scheme'));
    });

    test('carries the full Open Graph and Twitter card set', () {
      for (final tag in [
        'property="og:type"',
        'property="og:site_name"',
        'property="og:title"',
        'property="og:description"',
        'property="og:url"',
        'property="og:image"',
        'name="twitter:card"',
        'name="twitter:title"',
        'name="twitter:description"',
      ]) {
        expect(index, contains(tag), reason: tag);
      }
      expect(index, contains('name="twitter:card" content="summary'));
    });

    test('has iOS / Android web-app metadata and icons', () {
      expect(index, contains('apple-mobile-web-app-title'));
      expect(index, contains('apple-mobile-web-app-capable'));
      expect(index, contains('rel="apple-touch-icon"'));
      expect(index, contains('rel="manifest"'));
      expect(index, contains('rel="icon"'));
      expect(index, contains('favicon.png'));
    });

    test('emits Organization and WebSite JSON-LD bootstrap blocks', () {
      final blocks = RegExp(r'<script type="application/ld\+json">').allMatches(index).length;
      expect(blocks, greaterThanOrEqualTo(2));
      expect(index, contains('"@type": "Organization"'));
      expect(index, contains('"@type": "WebSite"'));
    });

    test('paints in brand colours before Dart runs (first-paint CSS)', () {
      expect(index, contains('--om-black'));
      expect(index, contains('background-color: var(--om-black)'));
      expect(index, contains('#0B0B0C'));
      expect(index, contains('#C9A227'), reason: 'brand gold is present in the first paint');
    });

    test('degrades with a noscript message instead of a black void', () {
      expect(index, contains('<noscript>'));
    });

    test('boots Flutter asynchronously and never blocks first paint', () {
      expect(index, matches(RegExp(r'src="flutter_bootstrap\.js"\s+async')));
    });

    test('the loading frame is announced to assistive tech', () {
      expect(index, contains('role="status"'));
      expect(index, contains('aria-live="polite"'));
    });
  });

  group('web shell leaks no secret', () {
    test('no Google API key, JWT, service account or service-role key', () {
      expect(index, isNot(contains('AIzaSy')));
      expect(index, isNot(contains('serviceAccountKey')));
      expect(index, isNot(contains('"type": "service_account"')));
      expect(index, isNot(contains('SUPABASE_SERVICE_ROLE')));
      // A raw JWT (three base64url segments) is the shape of a service token / Firebase admin key.
      expect(index, isNot(matches(RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\.'))));
    });

    test('the only unsubstituted placeholder is the documented SITE_ORIGIN token', () {
      final tokens = RegExp(r'\{\{([A-Z_]+)\}\}').allMatches(index).map((m) => m.group(1)).toSet();
      expect(tokens, everyElement('SITE_ORIGIN'), reason: 'only {{SITE_ORIGIN}} may remain raw');
    });

    test('index.html never hardcodes the .example fallback as a real origin', () {
      expect(index, isNot(contains('omevents.example')));
    });
  });

  group('robots.txt contract', () {
    test('opens with a User-agent rule and never blanket-disallows the root', () {
      expect(robots, contains('User-agent: *'));
      expect(RegExp(r'^Disallow:\s*/$', multiLine: true).hasMatch(robots), isFalse);
    });

    test('disallows the transactional and admin surfaces', () {
      expect(robots, contains('Disallow: /admin'));
      expect(robots, contains('Disallow: /cart'));
      expect(robots, contains('Disallow: /checkout'));
      expect(robots, contains('Disallow: /account'));
    });

    test('covers EVERY route the table marks noindex (no disagreement between signals)', () {
      final rules = RegExp(r'^Disallow:\s*(\S+)', multiLine: true)
          .allMatches(robots)
          .map((m) => m.group(1)!)
          .toList();
      for (final path in OmRouteMeta.disallowedPaths) {
        expect(_covered(rules, path), isTrue,
            reason: '$path is noindex in the table but not refused in robots.txt');
      }
    });

    test('never disallows an indexable route', () {
      final rules = RegExp(r'^Disallow:\s*(\S+)', multiLine: true)
          .allMatches(robots)
          .map((m) => m.group(1)!)
          .toList();
      for (final path in OmRouteMeta.indexableStaticPaths) {
        expect(_covered(rules, path), isFalse, reason: '$path is indexable but robots blocks it');
      }
    });

    test('keeps the sitemap line commented while the origin is unsubstituted', () {
      expect(robots, contains('{{SITE_ORIGIN}}/sitemap.xml'));
      expect(RegExp(r'^Sitemap:', multiLine: true).hasMatch(robots), isFalse);
    });
  });

  group('sitemap.xml seed contract', () {
    test('is a valid urlset document', () {
      expect(sitemap, contains('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'));
      expect(sitemap.trimRight(), endsWith('</urlset>'));
    });

    test('uses only the documented SITE_ORIGIN token, never the .example fallback', () {
      final tokens = RegExp(r'\{\{([A-Z_]+)\}\}').allMatches(sitemap).map((m) => m.group(1)).toSet();
      expect(tokens, everyElement('SITE_ORIGIN'));
      expect(sitemap, isNot(contains('omevents.example')));
    });

    test('contains no private route', () {
      for (final forbidden in [
        '/cart', '/checkout', '/account', '/admin', '/order-success', '/login', '/search',
      ]) {
        expect(sitemap, isNot(contains('<loc>{{SITE_ORIGIN}}$forbidden')), reason: forbidden);
      }
    });

    test('lists only indexable seed pages', () {
      final locs = RegExp(r'<loc>\{\{SITE_ORIGIN\}\}([^<]*)</loc>').allMatches(sitemap)
          .map((m) => m.group(1)!)
          .where((p) => !p.startsWith('/policy/')) // policy/{kind} resolves via the policy route
          .toList();
      for (final loc in locs) {
        expect(OmRouteMeta.forPath(loc).isIndexable, isTrue, reason: loc);
      }
    });
  });

  group('manifest.json contract', () {
    test('names the store and pins standalone display', () {
      expect(manifest['name'], contains('OM Events'));
      expect(manifest['short_name'], isNotNull);
      expect(manifest['display'], 'standalone');
      expect(manifest['start_url'], isNotNull);
    });

    test('uses the brand theme colour', () {
      expect(manifest['theme_color'], '#0B0B0C');
      expect(manifest['background_color'], '#0B0B0C');
    });

    test('ships at least a 512 icon', () {
      final icons = (manifest['icons']! as List).cast<Map<String, Object?>>();
      expect(icons.any((i) => '${i['sizes']}'.contains('512')), isTrue);
    });
  });
}
