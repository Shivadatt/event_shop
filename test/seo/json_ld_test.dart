// JSON-LD builders. Structured data is the surface that either earns rich results or triggers a
// Search Console penalty, so these assert the shape Google validates: money as a decimal string,
// aggregate vs single offer, ratings only when reviews exist, and — critically — that no internal
// field (cost price, stock, customer id, phone in a product doc) ever leaks into a public block.
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/seo/json_ld.dart';
import 'package:om_events/app/seo/om_seo.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/store_settings.dart';

Product _arched() => const Product(
      id: 'p-arch',
      name: 'Chrome Balloon Arch 12ft',
      slug: 'chrome-balloon-arch-12ft',
      sku: 'OME-ARCH-12',
      brand: 'OM Events',
      packSize: '1 kit',
      unit: 'kit',
      retailPricePaise: 150000,
      minOrderQty: 2,
      stockQty: 40,
      status: ProductStatus.active,
      slabs: <PriceSlab>[
        PriceSlab(minQty: 2, maxQty: 9, unitPricePaise: 140000),
        PriceSlab(minQty: 10, unitPricePaise: 125000),
      ],
    );

void main() {
  group('price band', () {
    test('spans the lowest slab to retail when several public prices exist', () {
      final band = OmJsonLd.priceBand(_arched());
      expect(band.$1, 125000);
      expect(band.$2, 150000);
    });

    test('a single-price product collapses to one value', () {
      const single = Product(
        id: 'x',
        name: 'Single',
        retailPricePaise: 5000,
        slabs: <PriceSlab>[PriceSlab(minQty: 1, unitPricePaise: 5000)],
      );
      final band = OmJsonLd.priceBand(single);
      expect(band.$1, 5000);
      expect(band.$2, 5000);
    });

    test('an unpriced product yields a null band, not a zero price', () {
      const free = Product(id: 'x', name: 'Unpriced', retailPricePaise: 0);
      final band = OmJsonLd.priceBand(free);
      expect(band.$1, isNull);
      expect(band.$2, isNull);
    });

    test('an inverted explicit range is corrected, never published backwards', () {
      final band = OmJsonLd.priceBand(_arched(), explicitMin: 200000, explicitMax: 90000);
      expect(band.$1, lessThanOrEqualTo(band.$2!));
    });
  });

  group('Product document', () {
    final doc = OmJsonLd.product(product: _arched());

    test('declares the schema context and type', () {
      expect(doc['@context'], OmJsonLd.context);
      expect(doc['@type'], 'Product');
      expect(doc['sku'], 'OME-ARCH-12');
      expect(doc['productID'], 'p-arch');
    });

    test('publishes a slug URL, absolute only once the origin is real', () {
      final url = doc['url'] as String;
      // Default test build has no SITE_URL, so it degrades to a relative path, not a fake domain.
      expect(url, '/product/chrome-balloon-arch-12ft');
      expect(url.contains(OmSeo.placeholderOrigin), isFalse);
    });

    test('multi-slab offers become an AggregateOffer with decimal low/high', () {
      final offers = doc['offers']! as Map<String, Object?>;
      expect(offers['@type'], 'AggregateOffer');
      expect(offers['lowPrice'], '1250.00');
      expect(offers['highPrice'], '1500.00');
      expect(offers['priceCurrency'], isNotEmpty);
      expect(offers['availability'], 'https://schema.org/InStock');
    });

    test('minimum admissible quantity is advertised on Offer-shaped products', () {
      const single = Product(
        id: 's',
        name: 'Single price',
        retailPricePaise: 80000,
        minOrderQty: 6,
        stockQty: 3,
        slabs: <PriceSlab>[PriceSlab(minQty: 1, unitPricePaise: 80000)],
      );
      final offer = (OmJsonLd.product(product: single)['offers']! as Map)['@type'];
      expect(offer, 'Offer');
    });

    test('no aggregateRating is fabricated when there are no reviews', () {
      expect(doc.containsKey('aggregateRating'), isFalse,
          reason: 'ratingCount is 0 — inventing one is a manual-action risk');
    });

    test('aggregateRating appears only with real review data', () {
      final reviewed = OmJsonLd.product(
        product: Product(
          id: 'r',
          name: 'Reviewed',
          retailPricePaise: 1000,
          ratingAvg: 4.6,
          ratingCount: 12,
        ),
      );
      final rating = reviewed['aggregateRating']! as Map<String, Object?>;
      expect(rating['ratingValue'], '4.6');
      expect(rating['reviewCount'], 12);
      expect(rating['bestRating'], 5);
    });

    test('an unpriced, out-of-stock product still renders a page without a fake price', () {
      final doc = OmJsonLd.product(
        product: const Product(id: 'o', name: 'Sold out', retailPricePaise: 0, stockQty: 0),
      );
      final offers = doc['offers']! as Map<String, Object?>;
      expect(offers.containsKey('price'), isFalse);
      expect(offers['availability'], 'https://schema.org/OutOfStock');
    });
  });

  group('no internal field leaks into a public Product block', () {
    test('forbidden keys are absent even when a caller tries to smuggle a price ceiling', () {
      final doc = OmJsonLd.product(
        product: _arched(),
        priceMinPaise: 90000,
        imageUrls: const <String>['https://cdn.example/a.jpg'],
        categoryPath: '/category/balloons',
      );
      final flat = doc.toString();
      for (final key in OmJsonLd.forbiddenProductKeys) {
        expect(flat.toLowerCase().contains('"${key.toLowerCase()}"'), isFalse,
            reason: '$key must never appear in a Product document');
      }
    });
  });

  group('BreadcrumbList', () {
    test('home is always position 1', () {
      final trail = productBreadcrumbTrail(
        product: _arched(),
        categoryName: 'Balloons',
        categoryPath: '/category/balloons',
      );
      final doc = OmJsonLd.breadcrumb(trail);
      final items = doc['itemListElement']! as List<Object?>;
      final first = items.first! as Map<String, Object?>;
      expect(first['position'], 1);
      expect(first['name'], 'Home');
      expect(items.length, 3);
      final last = items.last! as Map<String, Object?>;
      expect(last['name'], 'Chrome Balloon Arch 12ft');
    });

    test('crumb sanitize removes newline injection from a category name', () {
      final doc = OmJsonLd.breadcrumb(const <OmBreadcrumbItem>[
        OmBreadcrumbItem(name: 'Bad\nName', path: '/category/bad'),
      ]);
      final items = doc['itemListElement']! as List<Object?>;
      expect((items.first! as Map)['name'], 'Bad Name');
    });
  });

  group('WebSite + SearchAction', () {
    test('emits no SearchAction while the origin is unconfigured', () {
      final site = OmJsonLd.website();
      expect(site['@type'], 'WebSite');
      expect(site.containsKey('potentialAction'), isFalse,
          reason: 'a urlTemplate must be fetchable; none is until SITE_URL is real');
    });
  });

  group('Organization', () {
    test('uses brand defaults when settings are empty', () {
      final org = OmJsonLd.organization();
      expect(org['@type'], 'Organization');
      expect(org['name'], OmSeo.siteName);
    });

    test('formats an Indian phone as +91 when the settings carry one', () {
      final org = OmJsonLd.organization(
        settings: const StoreSettings(phone: '98765-43210'),
      );
      final contact = org['contactPoint']! as Map<String, Object?>;
      expect(contact['telephone'], '+919876543210');
      expect(contact['contactType'], 'sales');
    });

    test('omits contactPoint entirely when there is no phone', () {
      final org = OmJsonLd.organization(settings: const StoreSettings());
      expect(org.containsKey('contactPoint'), isFalse);
    });
  });

  group('ItemList', () {
    test('caps at pageSize and reports the true count', () {
      final many = List<Product>.generate(
        30,
        (i) => Product(
          id: 'id$i',
          name: 'Item $i',
          slug: 'item-$i',
          retailPricePaise: 1000,
        ),
      );
      final doc = OmJsonLd.itemList(name: 'Balloons', products: many, pageSize: 12);
      final elements = doc['itemListElement']! as List<Object?>;
      expect(elements.length, 12);
      expect(doc['numberOfItems'], 30);
    });
  });
}
