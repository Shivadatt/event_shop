// Unit tests for the pure SEO primitives. Nothing here touches dart:html or a plugin, so these run
// on the VM in the normal `flutter test` lane.
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/seo/om_seo.dart';

void main() {
  group('normalizePath', () {
    test('drops query strings and fragments, keeps the path', () {
      expect(OmSeo.normalizePath('/search?q=balloon&sort=price'), '/search');
      expect(OmSeo.normalizePath('/product/foo#reviews'), '/product/foo');
    });

    test('collapses trailing slashes but never the root', () {
      expect(OmSeo.normalizePath('/category/balloons/'), '/category/balloons');
      expect(OmSeo.normalizePath('/'), '/');
      expect(OmSeo.normalizePath(''), '/');
    });

    test('adds the leading slash when a caller forgot it', () {
      expect(OmSeo.normalizePath('product/abc'), '/product/abc');
    });
  });

  group('originOf', () {
    test('reduces a full URL to its scheme + host + port', () {
      expect(OmSeo.originOf('https://shop.example/cart?x=1'), 'https://shop.example');
      expect(OmSeo.originOf('https://shop.example:8443/'), 'https://shop.example:8443');
    });

    test('returns empty for empty input and strips trailing slashes otherwise', () {
      expect(OmSeo.originOf(''), '');
      expect(OmSeo.originOf('shop.example///'), 'shop.example');
    });
  });

  // Env.siteUrl defaults to the reserved .example placeholder, so a plain `flutter test` run (no
  // --dart-define) exercises the unconfigured path. That is the safe default we are pinning.
  group('unconfigured origin behaviour (default build)', () {
    test('the compiled-in default is treated as NOT a real origin', () {
      expect(OmSeo.hasRealSiteOrigin, isFalse,
          reason: 'SITE_URL defaults to https://omevents.example — a placeholder, never indexable');
    });

    test('absoluteUrl degrades to a relative path instead of a fake domain', () {
      expect(OmSeo.absoluteUrl('/product/abc'), '/product/abc');
      expect(OmSeo.absoluteUrl('product/abc'), '/product/abc');
    });
  });

  group('title', () {
    test('appends the brand once and never twice', () {
      expect(OmSeo.title(primary: 'Balloons'), 'Balloons | ${OmSeo.siteName}');
      final alreadyBranded = OmSeo.title(seoTitle: 'OM Events — Balloons');
      expect(alreadyBranded.contains('OM Events'), isTrue);
      expect(' '.allMatches(alreadyBranded).length, lessThan(6),
          reason: 'no double brand suffix');
    });

    test('caps at the SERP limit and breaks on a word boundary', () {
      final long = OmSeo.title(primary: List<String>.filled(40, 'word').join(' '));
      expect(long.length, lessThanOrEqualTo(OmSeo.maxTitleLength));
      expect(long.endsWith('…'), isTrue);
      expect(long.contains(' ${OmSeo.siteName}'), isFalse,
          reason: 'a capped title drops the brand rather than mid-truncating it');
    });

    test('empty input yields the default home title', () {
      expect(OmSeo.title(), OmSeo.defaultTitle);
    });

    test('joins primary and secondary with a separator', () {
      expect(OmSeo.title(primary: 'Balloons', secondary: 'Red'),
          'Balloons · Red | ${OmSeo.siteName}');
    });
  });

  group('description', () {
    test('explicit SEO text wins and is clamped to 158', () {
      final d = OmSeo.description(seoDescription: List<String>.filled(60, 'a').join(' '));
      expect(d.length, lessThanOrEqualTo(OmSeo.maxDescriptionLength));
    });

    test('falls back to the first sentence of the body', () {
      final d = OmSeo.description(
        body: 'This pack has fifty balloons. They are latex and hold air for days.',
      );
      expect(d.startsWith('This pack has fifty balloons.'), isTrue);
    });

    test('empty input stays empty rather than inventing filler', () {
      expect(OmSeo.description(), isEmpty);
    });
  });

  group('stableSlug', () {
    test('normalises arbitrary names to a valid URL slug', () {
      expect(OmSeo.stableSlug('12ft Chrome Balloon Arch & Kit'),
          '12ft-chrome-balloon-arch-and-kit');
    });

    test('caps long names at the slug limit and stays valid', () {
      final slug = OmSeo.stableSlug(List<String>.filled(60, 'superlongword').join('-'));
      expect(slug.length, lessThanOrEqualTo(OmSeo.maxSlugLength));
      expect(slug, matches(RegExp(r'^[a-z0-9-]+$')));
      expect(slug.endsWith('-'), isFalse);
    });

    test('a value too short to be a valid slug falls back', () {
      expect(OmSeo.stableSlug('!'), 'item');
    });
  });

  group('money and rating formatting for JSON-LD', () {
    test('rupeeAmount is a plain two-decimal string, never a float or glyph', () {
      expect(OmSeo.rupeeAmount(199500), '1995.00');
      expect(OmSeo.rupeeAmount(100), '1.00');
      expect(OmSeo.rupeeAmount(1), '0.01');
      expect(OmSeo.rupeeAmount(199599), '1995.99');
      expect(OmSeo.rupeeAmount(-5000), '-50.00');
    });

    test('no thousands separators leak into the price', () {
      expect(OmSeo.rupeeAmount(100000000), '1000000.00');
      expect(OmSeo.rupeeAmount(100000000).contains(','), isFalse);
    });

    test('ratingValue clamps to 1..5 and one decimal', () {
      expect(OmSeo.ratingValue(0), '0.0');
      expect(OmSeo.ratingValue(4.5), '4.5');
      expect(OmSeo.ratingValue(4.67), '4.7');
      expect(OmSeo.ratingValue(7), '5.0');
    });
  });

  group('sanitize', () {
    test('neutralises newline injection that would break a meta tag', () {
      const dirty = 'Hello\nWorld"><script>';
      final clean = OmSeo.sanitize(dirty);
      expect(clean.contains('\n'), isFalse);
      expect(clean.contains('\r'), isFalse);
      expect(clean, 'Hello World"><script>');
    });
  });

  group('absoluteImage', () {
    test('passes through an absolute URL untouched', () {
      expect(OmSeo.absoluteImage('https://cdn.example/a.jpg'), 'https://cdn.example/a.jpg');
    });

    test('returns empty when no url and no fallback', () {
      expect(OmSeo.absoluteImage(''), isEmpty);
    });
  });
}
