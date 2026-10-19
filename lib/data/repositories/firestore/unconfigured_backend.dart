import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/address.dart';
import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/data/repositories/order_repository.dart';

/// Honest "no backend" implementations, mirroring the `UnconfiguredMediaRepository` pattern: they
/// are real types that satisfy every interface, but every data call throws [ServerFailure] instead
/// of returning invented merchandise or silently empty lists. When `Env.hasFirebase` is false the
/// binding wires these so the app degrades to the setup screen with truthful failures rather than a
/// fake catalogue.
ServerFailure _unconfigured() => ServerFailure(
      'The store backend is not configured (${Env.missingKeys().join(', ')}).',
    );

final class UnconfiguredAuthRepository implements AuthRepository {
  @override
  UserProfile? get cachedProfile => null;

  @override
  Stream<UserProfile?> get profileChanges => Stream<UserProfile?>.error(_unconfigured());

  @override
  Stream<UserRole> get roleChanges => Stream<UserRole>.error(_unconfigured());

  @override
  Future<UserProfile> signIn({required String email, required String password}) async => throw _unconfigured();

  @override
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String displayName,
    String? phone,
  }) async =>
      throw _unconfigured();

  @override
  Future<void> signOut() async => throw _unconfigured();

  @override
  Future<void> sendPasswordReset(String email) async => throw _unconfigured();

  @override
  Future<void> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  }) async =>
      throw _unconfigured();

  @override
  Future<UserProfile> ensureProfile() async => throw _unconfigured();

  @override
  Future<void> updateProfile({
    String? displayName,
    String? phone,
    String? gstNumber,
    String? companyName,
    bool? notifyEmail,
    bool? notifyWhatsapp,
    bool? notifySms,
  }) async =>
      throw _unconfigured();

  @override
  Future<void> applyForWholesale({
    required String companyName,
    required String contactName,
    required String phone,
    String? gstNumber,
    String? address,
    String? reason,
    String? expectedMonthlyVolume,
  }) async =>
      throw _unconfigured();

  @override
  Future<void> toggleWishlist(String productId, {required bool add}) async => throw _unconfigured();
}

final class UnconfiguredProductRepository implements ProductRepository {
  @override
  Future<Product> byId(String id) async => throw _unconfigured();

  @override
  Future<Product> bySlug(String slug) async => throw _unconfigured();

  @override
  Future<Product> bySku(String sku) async => throw _unconfigured();

  @override
  Future<List<Product>> byIds(List<String> ids) async => throw _unconfigured();

  @override
  Future<PagedResult<Product>> search(CatalogQuery query) async => throw _unconfigured();

  @override
  Stream<PagedResult<Product>> watchSearch(CatalogQuery query) => Stream<PagedResult<Product>>.error(_unconfigured());

  @override
  Future<List<Product>> homeShelf({
    required int featuredLimit,
    required int bestSellerLimit,
    required int newArrivalLimit,
  }) async =>
      throw _unconfigured();

  @override
  Future<List<Product>> relatedTo(Product product, {int limit = 8}) async => throw _unconfigured();

  @override
  Future<List<String>> suggestions(String term, {int limit = 8}) async => throw _unconfigured();

  @override
  Future<int> availableStock(String productId, {String? variantId}) async => throw _unconfigured();
}

final class UnconfiguredCategoryRepository implements CategoryRepository {
  @override
  Future<List<Category>> tree() async => throw _unconfigured();

  @override
  Future<Category> byId(String id) async => throw _unconfigured();

  @override
  Future<Category> bySlug(String slug) async => throw _unconfigured();

  @override
  Future<List<Category>> childrenOf(String? parentId) async => throw _unconfigured();
}

final class UnconfiguredVariantRepository implements VariantRepository {
  @override
  Future<List<ProductVariant>> forProduct(String productId) async => throw _unconfigured();

  @override
  Future<ProductVariant> byId(String variantId) async => throw _unconfigured();
}

final class UnconfiguredCouponRepository implements CouponRepository {
  @override
  Future<CouponQuote> quote({required String code, required List<QuoteLine> lines, String? uid}) async =>
      throw _unconfigured();
}

final class UnconfiguredOrderRepository implements OrderRepository {
  @override
  Future<OrderReceipt> createOrder(OrderDraft draft) async => throw _unconfigured();

  @override
  Future<PagedResult<Order>> listMine({int pageSize = 20, String? cursor}) async => throw _unconfigured();

  @override
  Future<Order> byId(String orderId) async => throw _unconfigured();

  @override
  Future<Order> byOrderNumber(String orderNumber, {String? contactEmail}) async => throw _unconfigured();

  @override
  Future<void> requestCancellation(String orderId, {required String reason}) async => throw _unconfigured();

  @override
  Future<void> requestReturn(String orderId, {required String reason}) async => throw _unconfigured();

  @override
  Future<List<DraftLine>> expandReorder(String orderId) async => throw _unconfigured();

  @override
  Future<PaymentRecord> confirmPayment({required String orderId, required String paymentId, String? clientSecret}) async =>
      throw _unconfigured();

  @override
  Stream<Order> watchOrder(String orderId) => Stream<Order>.error(_unconfigured());
}

final class UnconfiguredAccountRepository
    implements AddressRepository, WishlistRepository, ReviewRepository, AccountRepository {
  @override
  Future<List<AddressBookEntry>> forCurrentUser() async => throw _unconfigured();

  @override
  Future<AddressBookEntry> save(AddressBookEntry entry) async => throw _unconfigured();

  @override
  Future<void> delete(String addressId) async => throw _unconfigured();

  @override
  Future<void> setDefault(String addressId, {bool billing = false}) async => throw _unconfigured();

  @override
  Future<List<String>> ids() async => throw _unconfigured();

  @override
  Future<List<Product>> items() async => throw _unconfigured();

  @override
  Future<bool> toggle(String productId, {required bool add}) async => throw _unconfigured();

  @override
  Future<List<Review>> forProduct(String productId, {bool publishedOnly = true}) async => throw _unconfigured();

  @override
  Future<RatingBreakdown> breakdownFor(String productId) async => throw _unconfigured();

  @override
  Future<Review> submit({
    required String productId,
    required int rating,
    String title = '',
    String body = '',
    String? orderId,
    List<MediaRef> images = const <MediaRef>[],
  }) async =>
      throw _unconfigured();

  @override
  Future<void> report(String reviewId, {required String reason}) async => throw _unconfigured();

  @override
  Future<Review?> mineFor(String productId) async => throw _unconfigured();

  @override
  Stream<List<AppNotification>> notifications({int limit = 30}) =>
      Stream<List<AppNotification>>.error(_unconfigured());

  @override
  Future<void> markNotificationRead(String id) async => throw _unconfigured();

  @override
  Future<void> markAllNotificationsRead() async => throw _unconfigured();

  @override
  Future<SupportRequest> openSupportTicket({
    required String subject,
    required SupportTopic topic,
    required String message,
    String? orderId,
    String? productId,
  }) async =>
      throw _unconfigured();

  @override
  Future<List<SupportRequest>> mySupportTickets() async => throw _unconfigured();

  @override
  Future<void> replyToTicket(String ticketId, {required String message}) async => throw _unconfigured();
}

final class UnconfiguredAdminRepository implements AdminRepository {
  Never _no() => throw _unconfigured();

  @override
  Future<DashboardStats> dashboard() async => _no();

  @override
  Future<PagedResult<Product>> listProducts({CatalogQuery? query, ProductStatus? status, int pageSize = 25, String? cursor}) async =>
      _no();

  @override
  Future<Product> saveProduct(Product product, {List<PriceSlab>? slabs}) async => _no();

  @override
  Future<void> archiveProduct(String productId, {required bool archived}) async => _no();

  @override
  Future<Product> duplicateProduct(String productId) async => _no();

  @override
  Future<Category> saveCategory(Category category) async => _no();

  @override
  Future<void> deleteCategory(String categoryId) async => _no();

  @override
  Future<void> saveVariant(ProductVariant variant) async => _no();

  @override
  Future<void> deleteVariant(String variantId) async => _no();

  @override
  Future<int> stockFor(String productId, {String? variantId}) async => _no();

  @override
  Future<void> adjustStock({
    required String productId,
    required int deltaQty,
    required StockMovementKind kind,
    required String reason,
    String? variantId,
    int? unitCostPaise,
  }) async =>
      _no();

  @override
  Future<void> setOpeningStock({required String productId, required int quantity, String? variantId, required String reason}) async =>
      _no();

  @override
  Future<List<InventoryMovement>> movementsFor(String productId, {int limit = 50, DateTime? since}) async => _no();

  @override
  Future<List<Product>> lowStockReport({int limit = 100}) async => _no();

  @override
  Future<PagedResult<Order>> listOrders({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    DeliveryMode? deliveryMode,
    String? customerId,
    String? search,
    DateTime? from,
    DateTime? to,
    int pageSize = 25,
    String? cursor,
  }) async =>
      _no();

  @override
  Future<Order> transitionOrder({
    required String orderId,
    required OrderStatus to,
    String note = '',
    String? trackingUrl,
    String? carrier,
    String? cancelledReason,
  }) async =>
      _no();

  @override
  Future<Order> markPayment({required String orderId, required String method, String? transactionReference, bool isCod = false}) async =>
      _no();

  @override
  Future<Order> issueRefund({required String orderId, required int amountPaise, required String reason}) async => _no();

  @override
  Future<Order> createCounterOrder({
    required List<DraftLine> lines,
    required String contactPhone,
    String contactName = '',
    String paymentMethod = 'cash',
    String note = '',
  }) async =>
      _no();

  @override
  Future<String?> invoicePdfUrl(String orderId) async => _no();

  @override
  Future<PagedResult<UserProfile>> listCustomers({String? search, UserRole? role, int pageSize = 25, String? cursor}) async => _no();

  @override
  Future<UserProfile> customerDetail(String uid) async => _no();

  @override
  Future<void> setCustomerRole({required String uid, required UserRole role, required String reason}) async => _no();

  @override
  Future<void> setCustomerBlocked({required String uid, required bool blocked, required String reason}) async => _no();

  @override
  Future<List<WholesaleApplication>> wholesaleApplications({bool openOnly = true}) async => _no();

  @override
  Future<void> decideWholesale({required String applicationId, required WholesaleStatus decision, required String note}) async => _no();

  @override
  Future<void> saveCustomerPrice(CustomerPriceOverride override) async => _no();

  @override
  Future<void> deleteCustomerPrice(String overrideId) async => _no();

  @override
  Future<List<CustomerPriceOverride>> listCustomerPrices({String? productId, String? uid}) async => _no();

  @override
  Future<List<Review>> moderationQueue({ReviewStatus status = ReviewStatus.pending}) async => _no();

  @override
  Future<void> decideReview({required String reviewId, required ReviewStatus decision, String note = ''}) async => _no();

  @override
  Future<List<Coupon>> listCoupons() async => _no();

  @override
  Future<Coupon> saveCoupon(Coupon coupon) async => _no();

  @override
  Future<void> deleteCoupon(String couponId) async => _no();

  @override
  Future<StoreSettings> settings() async => _no();

  @override
  Future<void> saveSettings(StoreSettings settings) async => _no();

  @override
  Future<PagedResult<AuditLog>> auditLogs({
    String? entityType,
    String? action,
    String? actorUid,
    DateTime? from,
    DateTime? to,
    int pageSize = 50,
    String? cursor,
  }) async =>
      _no();

  @override
  Future<List<ReportRow>> salesByProduct({required DateTime from, required DateTime to}) async => _no();

  @override
  Future<List<ReportRow>> salesByCategory({required DateTime from, required DateTime to}) async => _no();

  @override
  Future<List<ReportRow>> retailVsWholesale({required DateTime from, required DateTime to}) async => _no();

  @override
  Future<List<ReportRow>> slowMoving({int limit = 50}) async => _no();

  @override
  Future<List<ReportRow>> couponPerformance() async => _no();

  @override
  Future<List<ReportRow>> inventoryValuation() async => _no();

  @override
  Future<List<ReportRow>> cancelledOrRefunded({required DateTime from, required DateTime to}) async => _no();

  @override
  Future<List<ReportRow>> salesByDay({required DateTime from, required DateTime to}) async => _no();

  @override
  Future<List<ReportRow>> topCustomers({int limit = 20}) async => _no();

  @override
  Future<ReportRow> customerValue(String uid) async => _no();

  @override
  Future<String> exportCsv({required String reportId, DateTime? from, DateTime? to}) async => _no();

  @override
  Future<ImportSummary> importProductsCsv(String csv) async => _no();
}
