import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/seo/om_seo.dart';
import 'package:om_events/app/seo/page_meta.dart';

/// Every route in the app, with an explicit indexing decision.
///
/// This table is the single source of truth for three things that must never disagree: the
/// `<meta name="robots">` tag, the `Disallow:` list in `robots.txt`, and the URL set fed to
/// `sitemap.xml`. A route that is missing here falls through to [OmRouteMeta.unknown], which is
/// `noindex` — an unclassified page costs indexing, it does not leak a private URL into a
/// search result.
abstract final class OmRouteMeta {
  OmRouteMeta._();

  static const PageMeta home = PageMeta(
    route: OmRoutes.home,
    kind: OmPageKind.home,
    noIndex: false,
    titleTemplate: OmSeo.defaultTitle,
    descriptionTemplate:
        'Wholesale party supplies, balloons, decor and event materials for traders and planners. '
        'Quantity pricing applies automatically at checkout.',
  );

  static const PageMeta category = PageMeta(
    route: OmRoutes.category,
    kind: OmPageKind.collection,
    noIndex: false,
    descriptionTemplate:
        'Browse the range, compare pack sizes and see the quantity bands before you enquire.',
  );

  static const PageMeta product = PageMeta(
    route: OmRoutes.product,
    kind: OmPageKind.product,
    noIndex: false,
    ogType: 'product',
  );

  /// A search results page is a filtered duplicate of the catalogue: indexable links, but the page
  /// itself must not compete with category pages for the same query.
  static const PageMeta search = PageMeta(
    route: OmRoutes.search,
    kind: OmPageKind.collection,
    noIndex: true,
    canonicalFromPath: false,
    descriptionTemplate: 'Search results for the OM Events wholesale catalogue.',
  );

  static const PageMeta cart = PageMeta(
    route: OmRoutes.cart,
    kind: OmPageKind.transactional,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta checkout = PageMeta(
    route: OmRoutes.checkout,
    kind: OmPageKind.transactional,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta orderSuccess = PageMeta(
    route: OmRoutes.orderSuccess,
    kind: OmPageKind.transactional,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta login = PageMeta(
    route: OmRoutes.login,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
    titleTemplate: 'Sign in | ${OmSeo.siteName}',
  );

  static const PageMeta register = PageMeta(
    route: OmRoutes.register,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
    titleTemplate: 'Create an account | ${OmSeo.siteName}',
  );

  static const PageMeta forgotPassword = PageMeta(
    route: OmRoutes.forgotPassword,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
    titleTemplate: 'Reset your password | ${OmSeo.siteName}',
  );

  static const PageMeta resetPassword = PageMeta(
    route: OmRoutes.resetPassword,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
    titleTemplate: 'Choose a new password | ${OmSeo.siteName}',
  );

  static const PageMeta account = PageMeta(
    route: OmRoutes.account,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
    titleTemplate: 'My account | ${OmSeo.siteName}',
  );

  static const PageMeta accountOrders = PageMeta(
    route: OmRoutes.accountOrders,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  static const PageMeta accountOrder = PageMeta(
    route: OmRoutes.accountOrder,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  static const PageMeta accountAddresses = PageMeta(
    route: OmRoutes.accountAddresses,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  static const PageMeta accountWishlist = PageMeta(
    route: OmRoutes.accountWishlist,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  static const PageMeta accountNotifications = PageMeta(
    route: OmRoutes.accountNotifications,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  static const PageMeta accountSupport = PageMeta(
    route: OmRoutes.accountSupport,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  static const PageMeta accountSettings = PageMeta(
    route: OmRoutes.accountSettings,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  static const PageMeta reviewCompose = PageMeta(
    route: OmRoutes.reviewCompose,
    kind: OmPageKind.account,
    noIndex: true,
    followLinks: false,
  );

  /// The application form is a lead-generation page: it should rank for "wholesale party supplies
  /// signup"-style queries, so it is the one /wholesale page that is indexable.
  static const PageMeta wholesaleApply = PageMeta(
    route: OmRoutes.wholesaleApply,
    kind: OmPageKind.content,
    noIndex: false,
    titleTemplate: 'Wholesale account application | ${OmSeo.siteName}',
    descriptionTemplate:
        'Open a trade account for OM Events And Decorators: verified buyers get carton pricing, '
        'bulk-order tools and quotations.',
  );

  static const PageMeta wholesaleBulkOrder = PageMeta(
    route: OmRoutes.wholesaleBulkOrder,
    kind: OmPageKind.account,
    noIndex: true,
  );

  static const PageMeta wholesaleQuotation = PageMeta(
    route: OmRoutes.wholesaleQuotation,
    kind: OmPageKind.account,
    noIndex: true,
  );

  static const PageMeta about = PageMeta(
    route: OmRoutes.about,
    kind: OmPageKind.content,
    noIndex: false,
    titleTemplate: 'About us | ${OmSeo.siteName}',
  );

  static const PageMeta contact = PageMeta(
    route: OmRoutes.contact,
    kind: OmPageKind.content,
    noIndex: false,
    titleTemplate: 'Contact | ${OmSeo.siteName}',
  );

  static const PageMeta faq = PageMeta(
    route: OmRoutes.faq,
    kind: OmPageKind.content,
    noIndex: false,
    titleTemplate: 'FAQ | ${OmSeo.siteName}',
  );

  static const PageMeta policy = PageMeta(
    route: OmRoutes.policy,
    kind: OmPageKind.content,
    noIndex: false,
    titleTemplate: 'Policy | ${OmSeo.siteName}',
  );

  static const PageMeta notFound = PageMeta(
    route: OmRoutes.notFound,
    kind: OmPageKind.error,
    noIndex: true,
    canonicalFromPath: false,
    titleTemplate: 'Page not found | ${OmSeo.siteName}',
  );

  static const PageMeta unavailable = PageMeta(
    route: OmRoutes.unavailable,
    kind: OmPageKind.error,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
    titleTemplate: 'Store unavailable | ${OmSeo.siteName}',
  );

  static const PageMeta admin = PageMeta(
    route: OmRoutes.admin,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
    titleTemplate: 'Admin | ${OmSeo.siteName}',
  );

  static const PageMeta adminProducts = PageMeta(
    route: OmRoutes.adminProducts,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminProductNew = PageMeta(
    route: OmRoutes.adminProductNew,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminProductDetail = PageMeta(
    route: OmRoutes.adminProductDetail,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminCategories = PageMeta(
    route: OmRoutes.adminCategories,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminOrders = PageMeta(
    route: OmRoutes.adminOrders,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminOrderDetail = PageMeta(
    route: OmRoutes.adminOrderDetail,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminCustomers = PageMeta(
    route: OmRoutes.adminCustomers,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminCustomerDetail = PageMeta(
    route: OmRoutes.adminCustomerDetail,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminInventory = PageMeta(
    route: OmRoutes.adminInventory,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminPricing = PageMeta(
    route: OmRoutes.adminPricing,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminReviews = PageMeta(
    route: OmRoutes.adminReviews,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminCoupons = PageMeta(
    route: OmRoutes.adminCoupons,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminWholesale = PageMeta(
    route: OmRoutes.adminWholesale,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminSettings = PageMeta(
    route: OmRoutes.adminSettings,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminReports = PageMeta(
    route: OmRoutes.adminReports,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminAudit = PageMeta(
    route: OmRoutes.adminAudit,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  static const PageMeta adminMedia = PageMeta(
    route: OmRoutes.adminMedia,
    kind: OmPageKind.admin,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
  );

  /// Fallback for any path not covered above. Never indexable.
  static const PageMeta unknown = PageMeta(
    route: '*',
    kind: OmPageKind.error,
    noIndex: true,
    followLinks: false,
    canonicalFromPath: false,
    titleTemplate: 'Page not found | ${OmSeo.siteName}',
  );

  /// Every registered entry, including the `:id` admin patterns.
  static const List<PageMeta> entries = <PageMeta>[
    home,
    category,
    product,
    search,
    cart,
    checkout,
    orderSuccess,
    login,
    register,
    forgotPassword,
    resetPassword,
    account,
    accountOrders,
    accountOrder,
    accountAddresses,
    accountWishlist,
    accountNotifications,
    accountSupport,
    accountSettings,
    reviewCompose,
    wholesaleApply,
    wholesaleBulkOrder,
    wholesaleQuotation,
    about,
    contact,
    faq,
    policy,
    notFound,
    unavailable,
    admin,
    adminProducts,
    adminProductNew,
    adminProductDetail,
    adminCategories,
    adminOrders,
    adminOrderDetail,
    adminCustomers,
    adminCustomerDetail,
    adminInventory,
    adminPricing,
    adminReviews,
    adminCoupons,
    adminWholesale,
    adminSettings,
    adminReports,
    adminAudit,
    adminMedia,
  ];

  static Map<String, PageMeta> get byRoute => <String, PageMeta>{
        for (final entry in entries) entry.route: entry,
      };

  /// The page's metadata for a live path. Handles three shapes a real URL takes:
  /// an exact registered route, a GetX `:id` pattern, and a route plus a trailing id segment
  /// (`/category/balloons`). Anything under `/admin` that matched nothing is still admin.
  static PageMeta forPath(String path) {
    final normalized = OmSeo.normalizePath(path);
    final exact = byRoute[normalized];
    if (exact != null) return exact;

    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();

    for (final entry in entries) {
      if (!entry.route.contains(':')) continue;
      final pattern = OmSeo.normalizePath(entry.route).split('/').where((s) => s.isNotEmpty);
      final patternSegments = pattern.toList(growable: false);
      if (patternSegments.length != segments.length) continue;
      var matches = true;
      for (var i = 0; i < patternSegments.length; i++) {
        final part = patternSegments[i];
        if (!part.startsWith(':') && part != segments[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return entry;
    }

    PageMeta? bestPrefix;
    for (final entry in entries) {
      if (entry.route == '/' || entry.route.contains(':')) continue;
      if (normalized.startsWith('${entry.route}/')) {
        if (bestPrefix == null || entry.route.length > bestPrefix.route.length) {
          bestPrefix = entry;
        }
      }
    }
    if (bestPrefix != null) return bestPrefix;

    if (OmRoutes.isAdmin(normalized)) return admin;
    return unknown;
  }

  /// Static paths a sitemap may contain, before entity URLs are added. [OmSeo.hasRealSiteOrigin]
  /// must be true for any sitemap to be generated at all.
  static List<String> get indexableStaticPaths => entries
      .where((entry) => entry.isIndexable && !entry.route.contains(':') && entry.route != '*')
      .map((entry) => entry.route)
      .toList(growable: false);

  /// Paths `robots.txt` must refuse. Derived from the same table so a `noindex` page cannot also be
  /// crawled — the two signals disagreeing is what makes a removal request take weeks.
  static List<String> get disallowedPaths => entries
      .where((entry) => entry.noIndex)
      .map((entry) => entry.route)
      .where((route) => route != '/' && !route.contains(':') && route != '*')
      .toList(growable: false);

  /// Route names with no decision recorded. Always empty; the SEO test asserts it.
  static List<String> missingDecisionsFor(Iterable<String> routes) {
    final covered = byRoute.keys.toSet();
    return routes
        .map(OmSeo.normalizePath)
        .where((route) => route.isNotEmpty && !covered.contains(route))
        .toList(growable: false);
  }
}
