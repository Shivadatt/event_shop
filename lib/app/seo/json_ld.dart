import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/seo/om_seo.dart';
import 'package:om_events/app/seo/route_meta.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/store_settings.dart';

/// JSON-LD builders for the structured data this store can actually earn rich results from:
/// Organization, Product (offers + aggregate rating), BreadcrumbList, and WebSite with a Sitelinks
/// SearchAction.
///
/// Rules these builders enforce, because a hand-written `<script>` tag never does:
/// * money crosses from paise to a plain decimal rupee string — no `₹`, no separators, no float;
/// * cost price, exact stock and customer data are never serialised into a public document;
/// * a field with no real value is omitted rather than invented, so Google never sees a placeholder
///   rating, price or image;
/// * `@id` and search-target values are only absolute when the site origin is configured.
abstract final class OmJsonLd {
  OmJsonLd._();

  static const String context = 'https://schema.org';

  /// Keys that must never appear in a public Product/Breadcrumb/ItemList document. Organization
  /// legitimately publishes the shop's own phone and email, so this list is asserted against the
  /// product-shaped builders only.
  static const List<String> forbiddenProductKeys = <String>[
    'cost',
    'costPrice',
    'costPricePaise',
    'unitCostPaise',
    'margin',
    'marginPaise',
    'grossMarginPaise',
    'stockQty',
    'balanceAfter',
    'uid',
    'userId',
    'orderId',
    'phone',
    'contactPhone',
    'whatsapp',
    'email',
    'contactEmail',
    'gstNumber',
    'internalNote',
    'transactionReference',
    'idempotencyKey',
    'adminToken',
    'serviceRoleKey',
  ];

  /// Merchant details from `store_settings`. Falls back to the compiled brand constants when the
  /// settings document has not loaded yet, which is what the static bootstrap block in
  /// `web/index.html` needs.
  static Map<String, Object?> organization({
    StoreSettings settings = StoreSettings.fallback,
    String? logoUrl,
  }) {
    final sameAs = <String>[
      for (final link in settings.socialLinks.entries)
        if (link.value.trim().isNotEmpty) link.value.trim(),
    ];
    final street = <String>[
      settings.addressLine1,
      settings.addressLine2,
    ].where((line) => line.trim().isNotEmpty).map((line) => line.trim()).join(', ');
    final phone = _digits(settings.phone);

    return <String, Object?>{
      '@context': context,
      '@type': 'Organization',
      '@id': _id('/#organization'),
      'name': settings.shopName.isEmpty ? OmSeo.siteName : settings.shopName,
      if (settings.tagline.isNotEmpty) 'slogan': settings.tagline,
      if (_configured(OmSeo.configuredOrigin) != null)
        'url': OmSeo.configuredOrigin,
      if ((logoUrl ?? '').isNotEmpty) 'logo': logoUrl!,
      if (sameAs.isNotEmpty) 'sameAs': sameAs,
      if (settings.fullAddress.isNotEmpty)
        'address': <String, Object?>{
          '@type': 'PostalAddress',
          if (street.isNotEmpty) 'streetAddress': street,
          if (settings.city.isNotEmpty) 'addressLocality': settings.city,
          if (settings.state.isNotEmpty) 'addressRegion': settings.state,
          if (settings.pincode.isNotEmpty) 'postalCode': settings.pincode,
          'addressCountry': 'IN',
        },
      if (phone.isNotEmpty)
        'contactPoint': <String, Object?>{
          '@type': 'ContactPoint',
          'telephone': phone.startsWith('91') ? '+$phone' : '+91$phone',
          'contactType': 'sales',
          'availableLanguage': const <String>['en', 'hi'],
        },
      if (settings.email.isNotEmpty) 'email': settings.email,
    };
  }

  /// A product page. `offers` becomes an `AggregateOffer` whenever more than one price exists
  /// (slabs, a variant band, a live sale), because advertising one price and charging another is
  /// what gets a rich result disqualified.
  static Map<String, Object?> product({
    required Product product,
    int? priceMinPaise,
    int? priceMaxPaise,
    List<String> imageUrls = const <String>[],
    String? categoryPath,
  }) {
    final pictureUrls = images(product, imageUrls);
    final properties = <Map<String, Object?>>[
      if (product.packSize.isNotEmpty)
        <String, Object?>{
          '@type': 'PropertyValue',
          'name': 'Pack size',
          'value': product.packSize,
        },
      if (product.unit.isNotEmpty)
        <String, Object?>{
          '@type': 'PropertyValue',
          'name': 'Sold as',
          'value': product.unit,
        },
      if (product.minOrderQty > 1)
        <String, Object?>{
          '@type': 'PropertyValue',
          'name': 'Minimum order quantity',
          'value': product.minOrderQty,
        },
    ];

    return <String, Object?>{
      '@context': context,
      '@type': 'Product',
      'name': product.name.isEmpty ? OmSeo.sanitize(product.id) : OmSeo.sanitize(product.name),
      if (product.description.isNotEmpty) 'description': OmSeo.sanitize(product.description),
      if (product.sku.isNotEmpty) 'sku': product.sku,
      'mpn': product.sku.isEmpty ? product.id : product.sku,
      'productID': product.id,
      'url': OmSeo.absoluteProductUrl(product),
      if (pictureUrls.isNotEmpty) 'image': pictureUrls,
      if (product.brand.isNotEmpty)
        'brand': <String, Object?>{'@type': 'Brand', 'name': product.brand},
      'offers': _offers(product: product, explicitMin: priceMinPaise, explicitMax: priceMaxPaise),
      if (product.ratingCount > 0 && product.ratingAvg > 0)
        'aggregateRating': <String, Object?>{
          '@type': 'AggregateRating',
          'ratingValue': OmSeo.ratingValue(product.ratingAvg),
          'reviewCount': product.ratingCount,
          'bestRating': 5,
          'worstRating': 1,
        },
      'category': ?categoryPath,
      if (properties.isNotEmpty) 'additionalProperty': properties,
    };
  }

  /// Public image URLs for a product: caller-supplied first (already CDN-transformed), else the
  /// primary media reference. Never a `storagePath`, which is not a public URL.
  static List<String> images(
    Product product, [
    List<String> provided = const <String>[],
  ]) {
    if (provided.isNotEmpty) {
      return provided.where((url) => url.isNotEmpty).toList(growable: false);
    }
    final primary = product.primaryImage;
    if (primary == null || primary.url.isEmpty) return const <String>[];
    return <String>[primary.url];
  }

  /// Lowest and highest *public* unit price. Slabs and the sale price are in scope; cost price is
  /// not a field on [Product] at all, which is why the leak can only arrive via an explicit
  /// `priceMinPaise`/`priceMaxPaise` argument from a caller that shouldn't have it.
  static (int?, int?) priceBand(
    Product product, {
    int? explicitMin,
    int? explicitMax,
  }) {
    final values = <int>[
      if (product.retailPricePaise > 0) product.retailPricePaise,
      if (product.salePricePaise != null && product.salePricePaise! > 0) product.salePricePaise!,
      for (final slab in product.slabs)
        if (slab.unitPricePaise > 0) slab.unitPricePaise,
    ];
    if (values.isEmpty) return (null, null);
    values.sort();
    final low = explicitMin ?? values.first;
    final high = explicitMax ?? values.last;
    if (low <= 0 || high <= 0) return (null, null);
    return (low > high ? high : low, low > high ? low : high);
  }

  static Map<String, Object?> _offers({
    required Product product,
    int? explicitMin,
    int? explicitMax,
  }) {
    final band = priceBand(product, explicitMin: explicitMin, explicitMax: explicitMax);
    final low = band.$1;
    final high = band.$2;
    final availability =
        product.isInStock ? 'https://schema.org/InStock' : 'https://schema.org/OutOfStock';
    final url = OmSeo.absoluteProductUrl(product);

    if (low == null || high == null) {
      // An unpriced product still has a page; it simply must not claim a price Google can check.
      return <String, Object?>{
        '@type': 'AggregateOffer',
        'priceCurrency': Env.currencyCode,
        'availability': availability,
        'url': url,
      };
    }

    if (low == high) {
      return <String, Object?>{
        '@type': 'Offer',
        'priceCurrency': Env.currencyCode,
        'price': OmSeo.rupeeAmount(low),
        'availability': availability,
        'url': url,
        'itemCondition': 'https://schema.org/NewCondition',
        if (product.minOrderQty > 1) 'minimumAdmissibleQuantity': product.minOrderQty,
      };
    }

    return <String, Object?>{
      '@type': 'AggregateOffer',
      'priceCurrency': Env.currencyCode,
      'lowPrice': OmSeo.rupeeAmount(low),
      'highPrice': OmSeo.rupeeAmount(high),
      'offerCount': product.slabs.length > 1 ? product.slabs.length : 2,
      'priceRange': '${OmSeo.rupeeAmount(low)}-${OmSeo.rupeeAmount(high)}',
      'availability': availability,
      'url': url,
      'itemCondition': 'https://schema.org/NewCondition',
    };
  }

  static Map<String, Object?> breadcrumb(List<OmBreadcrumbItem> trail) => <String, Object?>{
        '@context': context,
        '@type': 'BreadcrumbList',
        'itemListElement': <Map<String, Object?>>[
          for (var i = 0; i < trail.length; i++)
            <String, Object?>{
              '@type': 'ListItem',
              'position': i + 1,
              'name': OmSeo.sanitize(trail[i].name),
              'item': OmSeo.absoluteUrl(trail[i].path),
            },
        ],
      };

  /// Home is always position 1; a trail that starts deeper loses the site-name crumb Google shows.
  static List<OmBreadcrumbItem> homePrefixed(List<OmBreadcrumbItem> trail) => <OmBreadcrumbItem>[
        const OmBreadcrumbItem(name: 'Home', path: OmRoutes.home),
        ...trail,
      ];

  /// Sitelinks SearchAction. Emitted only when the origin is real, since the `urlTemplate` must be
  /// fetchable by the crawler.
  static Map<String, Object?> website({
    StoreSettings settings = StoreSettings.fallback,
    bool includeSearchAction = true,
  }) {
    final name = settings.shopName.isEmpty ? OmSeo.siteName : settings.shopName;
    return <String, Object?>{
      '@context': context,
      '@type': 'WebSite',
      '@id': _id('/#website'),
      'name': name,
      if (settings.tagline.isNotEmpty) 'alternateName': settings.tagline,
      if (_configured(OmSeo.configuredOrigin) != null) 'url': OmSeo.configuredOrigin,
      'inLanguage': 'en-IN',
      if (includeSearchAction && OmSeo.hasRealSiteOrigin)
        'potentialAction': <String, Object?>{
          '@type': 'SearchAction',
          'target': <String, Object?>{
            '@type': 'EntryPoint',
            'urlTemplate':
                '${OmSeo.configuredOrigin}${OmRoutes.search}?q={search_term_string}',
          },
          'query-input': 'required name=search_term_string',
        },
    };
  }

  /// The blocks a crawler needs before the Flutter app has painted anything: `web/index.html`
  /// embeds the output of this function so the first byte already carries entity data.
  static List<Map<String, Object?>> bootstrapBlocks({
    StoreSettings settings = StoreSettings.fallback,
    String? logoUrl,
  }) =>
      <Map<String, Object?>>[
        organization(settings: settings, logoUrl: logoUrl),
        website(settings: settings),
      ];

  /// A category/collection `ItemList`. Kept separate from [product] because Google validates the
  /// two differently and a listing page must not claim to be one product.
  static Map<String, Object?> itemList({
    required String name,
    required List<Product> products,
    int pageSize = 20,
  }) =>
      <String, Object?>{
        '@context': context,
        '@type': 'ItemList',
        'name': OmSeo.sanitize(name),
        'numberOfItems': products.length,
        'itemListElement': <Map<String, Object?>>[
          for (var i = 0; i < products.length && i < pageSize; i++)
            <String, Object?>{
              '@type': 'ListItem',
              'position': i + 1,
              'name': OmSeo.sanitize(products[i].name),
              'url': OmSeo.absoluteProductUrl(products[i]),
            },
        ],
      };

  static String _id(String suffix) =>
      OmSeo.hasRealSiteOrigin ? '${OmSeo.configuredOrigin}$suffix' : suffix;

  static String? _configured(String value) => OmSeo.hasRealSiteOrigin ? value : null;

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');
}

/// One crumb. Paths come from `OmRoutes`, never from a string a screen invented.
final class OmBreadcrumbItem {
  const OmBreadcrumbItem({required this.name, required this.path});

  final String name;
  final String path;
}

/// The trail for a product page, used by both the JSON-LD block and the visible breadcrumb.
List<OmBreadcrumbItem> productBreadcrumbTrail({
  required Product product,
  String? categoryName,
  String? categoryPath,
}) =>
    OmJsonLd.homePrefixed(<OmBreadcrumbItem>[
      if (categoryName != null && categoryPath != null)
        OmBreadcrumbItem(name: categoryName, path: categoryPath),
      OmBreadcrumbItem(name: product.name, path: OmSeo.productPath(product)),
    ]);

/// The trail for a category page.
List<OmBreadcrumbItem> categoryBreadcrumbTrail({
  required String name,
  required String path,
}) =>
    OmJsonLd.homePrefixed(<OmBreadcrumbItem>[
      OmBreadcrumbItem(name: name, path: path),
    ]);

/// Static route pages (`/about`, `/faq`, …) share this so a screen cannot forget the home crumb.
List<OmBreadcrumbItem> staticBreadcrumbTrail({
  required String name,
  required String path,
}) =>
    OmJsonLd.homePrefixed(<OmBreadcrumbItem>[
      OmBreadcrumbItem(name: name, path: path),
    ]);

/// The indexing decision for a path, as the storefront's head writer needs it.
bool omRouteIsIndexable(String path) => OmRouteMeta.forPath(path).isIndexable;
