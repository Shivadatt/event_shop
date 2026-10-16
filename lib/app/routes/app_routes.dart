/// Every navigable path in the app. Widgets navigate by these constants; a literal route string
/// in a screen is a bug, because it cannot be found when the path changes.
abstract final class OmRoutes {
  static const String home = '/';

  static const String category = '/category';
  static const String product = '/product';
  static const String search = '/search';

  static const String cart = '/cart';
  static const String checkout = '/checkout';
  static const String orderSuccess = '/order-success';

  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  static const String account = '/account';
  static const String accountOrders = '/account/orders';
  static const String accountOrder = '/account/order';
  static const String accountAddresses = '/account/addresses';
  static const String accountWishlist = '/account/wishlist';
  static const String accountNotifications = '/account/notifications';
  static const String accountSupport = '/account/support';
  static const String accountSettings = '/account/settings';

  static const String reviewCompose = '/review';

  static const String wholesaleApply = '/wholesale/apply';
  static const String wholesaleBulkOrder = '/wholesale/bulk-order';
  static const String wholesaleQuotation = '/wholesale/quotation';

  static const String about = '/about';
  static const String contact = '/contact';
  static const String faq = '/faq';
  static const String policy = '/policy';

  // Admin. The `…Detail` constants are GetX *patterns* (registered with `:id`); the plain
  // constants are what you push.
  static const String admin = '/admin';
  static const String adminProducts = '/admin/products';
  static const String adminProductNew = '/admin/products/new';
  static const String adminProductDetail = '/admin/products/:id';
  static const String adminCategories = '/admin/categories';
  static const String adminOrders = '/admin/orders';
  static const String adminOrderDetail = '/admin/orders/:id';
  static const String adminCustomers = '/admin/customers';
  static const String adminCustomerDetail = '/admin/customers/:id';
  static const String adminInventory = '/admin/inventory';
  static const String adminPricing = '/admin/pricing';
  static const String adminReviews = '/admin/reviews';
  static const String adminCoupons = '/admin/coupons';
  static const String adminWholesale = '/admin/wholesale';
  static const String adminSettings = '/admin/settings';
  static const String adminReports = '/admin/reports';
  static const String adminAudit = '/admin/audit';
  static const String adminMedia = '/admin/media';

  /// `errors` is not a navigable route; it is the fallback for an unknown deep link, which the
  /// storefront must render as a real 404 rather than redirecting silently to home.
  static const String notFound = '/not-found';
  static const String unavailable = '/unavailable';

  static String forCategory(String slug) => '$category/$slug';
  static String forProduct(String idOrSlug) => '$product/$idOrSlug';
  static String forOrder(String orderId) => '$accountOrder/$orderId';
  static String forOrderSuccess(String orderId) => '$orderSuccess/$orderId';
  static String forReview(String productId) => '$reviewCompose/$productId';
  static String forPolicy(String kind) => '$policy/$kind';

  static String forAdminProduct(String productId) => '$adminProducts/$productId';
  static String forAdminOrder(String orderId) => '$adminOrders/$orderId';
  static String forAdminCustomer(String uid) => '$adminCustomers/$uid';

  static bool isAdmin(String path) => path == admin || path.startsWith('$admin/');
}

/// Named arguments carried in the query string instead of opaque `Get.arguments`, so a deep link
/// pasted into a new tab still works.
abstract final class OmRouteArgs {
  static const String returnUrl = 'return';
  static const String productId = 'productId';
  static const String variantId = 'variantId';
  static const String qty = 'qty';
  static const String orderId = 'orderId';
  static const String couponCode = 'coupon';
  static const String search = 'q';
  static const String source = 'from';
}

abstract final class OmRoutePath {
  /// `/product/ome-balloon-7?variantId=x` -> `ome-balloon-7`.
  static String lastSegment(String path) {
    final trimmed = path.split('?').first;
    final parts = trimmed.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  static Map<String, String> query(String uri) {
    final index = uri.indexOf('?');
    if (index < 0) return const <String, String>{};
    return Uri.splitQueryString(uri.substring(index + 1));
  }
}
