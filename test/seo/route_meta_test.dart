// The route metadata table is the single source of truth that the robots tag, robots.txt and
// sitemap.xml must all agree with. These tests pin that agreement against the real OmRoutes
// constants — if a route is added to the app and not classified here, this suite goes red before
// an unindexed (or worse, leaked) page ever ships.
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/seo/page_meta.dart';
import 'package:om_events/app/seo/route_meta.dart';

/// Every navigable path constant in `OmRoutes`, kept as a literal list so the test enumerates the
/// contract surface rather than reflecting (Dart cannot reflect static fields here).
const List<String> _allRouteConstants = <String>[
  OmRoutes.home,
  OmRoutes.category,
  OmRoutes.product,
  OmRoutes.search,
  OmRoutes.cart,
  OmRoutes.checkout,
  OmRoutes.orderSuccess,
  OmRoutes.login,
  OmRoutes.register,
  OmRoutes.forgotPassword,
  OmRoutes.resetPassword,
  OmRoutes.account,
  OmRoutes.accountOrders,
  OmRoutes.accountOrder,
  OmRoutes.accountAddresses,
  OmRoutes.accountWishlist,
  OmRoutes.accountNotifications,
  OmRoutes.accountSupport,
  OmRoutes.accountSettings,
  OmRoutes.reviewCompose,
  OmRoutes.wholesaleApply,
  OmRoutes.wholesaleBulkOrder,
  OmRoutes.wholesaleQuotation,
  OmRoutes.about,
  OmRoutes.contact,
  OmRoutes.faq,
  OmRoutes.policy,
  OmRoutes.notFound,
  OmRoutes.unavailable,
  OmRoutes.admin,
  OmRoutes.adminProducts,
  OmRoutes.adminProductNew,
  OmRoutes.adminProductDetail,
  OmRoutes.adminCategories,
  OmRoutes.adminOrders,
  OmRoutes.adminOrderDetail,
  OmRoutes.adminCustomers,
  OmRoutes.adminCustomerDetail,
  OmRoutes.adminInventory,
  OmRoutes.adminPricing,
  OmRoutes.adminReviews,
  OmRoutes.adminCoupons,
  OmRoutes.adminWholesale,
  OmRoutes.adminSettings,
  OmRoutes.adminReports,
  OmRoutes.adminAudit,
  OmRoutes.adminMedia,
];

void main() {
  group('coverage', () {
    test('every OmRoutes constant has an explicit indexing decision', () {
      final missing = OmRouteMeta.missingDecisionsFor(_allRouteConstants);
      expect(missing, isEmpty, reason: 'unclassified routes: $missing');
    });

    test('no registered entry is duplicated by route', () {
      final routes = OmRouteMeta.entries.map((e) => e.route).toList();
      expect(routes.toSet().length, routes.length);
    });

    test('every registered entry actually resolves through forPath', () {
      for (final entry in OmRouteMeta.entries) {
        expect(OmRouteMeta.forPath(entry.route), same(entry),
            reason: '${entry.route} must resolve to its own entry');
      }
    });
  });

  group('privacy of transactional, account and admin areas', () {
    test('cart, checkout and order-success are noindex and nofollow', () {
      for (final route in [OmRoutes.cart, OmRoutes.checkout, OmRoutes.orderSuccess]) {
        final meta = OmRouteMeta.forPath(route);
        expect(meta.noIndex, isTrue, reason: route);
        expect(meta.followLinks, isFalse, reason: route);
        expect(meta.directives, containsAll(<String>['noindex', 'nofollow']));
      }
    });

    test('no admin route is ever indexable', () {
      for (final route in _allRouteConstants.where(OmRoutes.isAdmin)) {
        expect(OmRouteMeta.byRoute[route]!.noIndex, isTrue, reason: route);
      }
    });

    test('every account route is noindex', () {
      for (final route in _allRouteConstants
          .where((r) => r == OmRoutes.account || r.startsWith('${OmRoutes.account}/'))) {
        expect(OmRouteMeta.forPath(route).noIndex, isTrue, reason: route);
      }
    });

    test('a noindex page never advertises a self-canonical', () {
      expect(OmRouteMeta.cart.canonicalFor('/cart'), isNull);
      expect(OmRouteMeta.admin.canonicalFor('/admin'), isNull);
    });
  });

  group('indexable content', () {
    test('home, category, product and the marketing pages are indexable', () {
      for (final meta in <PageMeta>[
        OmRouteMeta.home,
        OmRouteMeta.category,
        OmRouteMeta.product,
        OmRouteMeta.wholesaleApply,
        OmRouteMeta.about,
        OmRouteMeta.contact,
        OmRouteMeta.faq,
        OmRouteMeta.policy,
      ]) {
        expect(meta.noIndex, isFalse, reason: meta.route);
        expect(meta.isIndexable, isTrue, reason: meta.route);
      }
    });

    test('search is noindex but its links are still followed', () {
      expect(OmRouteMeta.search.noIndex, isTrue);
      expect(OmRouteMeta.search.followLinks, isTrue);
      expect(OmRouteMeta.search.canonicalFromPath, isFalse);
    });

    test('the product page declares og:type product', () {
      expect(OmRouteMeta.product.ogType, 'product');
    });

    test('indexable static paths exclude patterns and the wildcard', () {
      for (final path in OmRouteMeta.indexableStaticPaths) {
        expect(path.contains(':'), isFalse, reason: path);
        expect(OmRouteMeta.forPath(path).isIndexable, isTrue, reason: path);
      }
      expect(OmRouteMeta.indexableStaticPaths, contains('/'));
    });
  });

  group('forPath resolution of real URL shapes', () {
    test('resolves a parameterised instance to its pattern entry', () {
      expect(OmRouteMeta.forPath('/product/balloon-arch-12ft'), same(OmRouteMeta.product));
      expect(OmRouteMeta.forPath('/category/balloons'), same(OmRouteMeta.category));
      expect(OmRouteMeta.forPath('/admin/products/xyz'), same(OmRouteMeta.adminProductDetail));
      expect(OmRouteMeta.forPath('/admin/orders/o1'), same(OmRouteMeta.adminOrderDetail));
      expect(OmRouteMeta.forPath('/account/order/o9'), same(OmRouteMeta.accountOrder));
    });

    test('nested account pages resolve to their own entries', () {
      expect(OmRouteMeta.forPath('/account/orders'), same(OmRouteMeta.accountOrders));
      expect(OmRouteMeta.forPath('/account/addresses'), same(OmRouteMeta.accountAddresses));
    });

    test('an unknown deep link is never indexable and is not an admin page', () {
      final meta = OmRouteMeta.forPath('/totally-unknown-thing');
      expect(meta.noIndex, isTrue);
      expect(meta.route, '*');
    });

    test('any unmatched /admin path is still treated as admin (noindex)', () {
      final meta = OmRouteMeta.forPath('/admin/some/brand/new/tool');
      expect(meta.noIndex, isTrue);
    });

    test('trailing slash and query are normalised before matching', () {
      expect(OmRouteMeta.forPath('/cart/?add=1'), same(OmRouteMeta.cart));
    });
  });

  group('robots.txt disallow list', () {
    test('disallowed paths are exactly the noindex routes minus the root', () {
      final disallowed = OmRouteMeta.disallowedPaths.toSet();
      expect(disallowed, contains(OmRoutes.cart));
      expect(disallowed, contains(OmRoutes.checkout));
      expect(disallowed, contains(OmRoutes.admin));
      expect(disallowed, isNot(contains('/')), reason: 'the root must never be disallowed');
      for (final path in disallowed) {
        expect(path.contains(':'), isFalse, reason: 'robots cannot express $: patterns');
      }
    });

    test('an indexable route is never in the disallow list', () {
      for (final entry in OmRouteMeta.entries.where((e) => e.isIndexable)) {
        expect(OmRouteMeta.disallowedPaths, isNot(contains(entry.route)), reason: entry.route);
      }
    });
  });
}
