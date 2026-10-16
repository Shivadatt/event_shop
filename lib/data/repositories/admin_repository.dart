import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/order_repository.dart';

final class DashboardStats {
  const DashboardStats({
    this.ordersToday = 0,
    this.revenueTodayPaise = 0,
    this.revenueMonthPaise = 0,
    this.pendingOrders = 0,
    this.pendingPayments = 0,
    this.lowStockCount = 0,
    this.outOfStockCount = 0,
    this.newCustomers = 0,
    this.openSupportTickets = 0,
    this.pendingReviews = 0,
    this.pendingWholesaleApplications = 0,
    this.bestSellers = const <BestSellerRow>[],
    this.salesSparkline = const <SalesPoint>[],
  });

  final int ordersToday;
  final int revenueTodayPaise;
  final int revenueMonthPaise;
  final int pendingOrders;
  final int pendingPayments;
  final int lowStockCount;
  final int outOfStockCount;
  final int newCustomers;
  final int openSupportTickets;
  final int pendingReviews;
  final int pendingWholesaleApplications;
  final List<BestSellerRow> bestSellers;
  final List<SalesPoint> salesSparkline;
}

final class BestSellerRow {
  const BestSellerRow({
    required this.productId,
    required this.name,
    required this.unitsSold,
    required this.revenuePaise,
  });

  final String productId;
  final String name;
  final int unitsSold;
  final int revenuePaise;
}

final class SalesPoint {
  const SalesPoint({required this.day, required this.revenuePaise, required this.orders});

  final DateTime day;
  final int revenuePaise;
  final int orders;
}

final class ReportRow {
  const ReportRow({
    required this.key,
    required this.label,
    required this.units,
    required this.revenuePaise,
    this.costPaise = 0,
    this.discountPaise = 0,
  });

  final String key;
  final String label;
  final int units;
  final int revenuePaise;
  final int costPaise;
  final int discountPaise;

  /// Margin is only meaningful when a cost price was recorded; a zero-cost row is reported as
  /// unknown rather than as a 100% margin.
  int get grossMarginPaise => costPaise == 0 ? 0 : revenuePaise - costPaise;
  bool get hasCostData => costPaise > 0;
}

/// Admin-only operations. Every method here maps to a privileged Cloud Function or a
/// staff-gated Firestore query — the interface is not a permission check.
abstract interface class AdminRepository {
  Future<DashboardStats> dashboard();

  Future<PagedResult<Product>> listProducts({
    CatalogQuery? query,
    ProductStatus? status,
    int pageSize = 25,
    String? cursor,
  });

  /// Prices, stock and images are excluded from a plain product write; this is the privileged
  /// path that may touch them, and it writes an audit row.
  Future<Product> saveProduct(Product product, {List<PriceSlab>? slabs});

  Future<void> archiveProduct(String productId, {required bool archived});

  Future<Product> duplicateProduct(String productId);

  Future<void> saveVariant(ProductVariant variant);

  Future<void> deleteVariant(String variantId);

  Future<int> stockFor(String productId, {String? variantId});

  Future<void> adjustStock({
    required String productId,
    required int deltaQty,
    required StockMovementKind kind,
    required String reason,
    String? variantId,
    int? unitCostPaise,
  });

  Future<void> setOpeningStock({
    required String productId,
    required int quantity,
    String? variantId,
    required String reason,
  });

  Future<List<InventoryMovement>> movementsFor(
    String productId, {
    int limit = 50,
    DateTime? since,
  });

  Future<List<Product>> lowStockReport({int limit = 100});

  Future<PagedResult<Order>> listOrders({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    String? search,
    DateTime? from,
    DateTime? to,
    int pageSize = 25,
    String? cursor,
  });

  /// Status transitions run server-side so stock restore, notification and audit happen in one
  /// transaction whatever the browser tab looked like.
  Future<Order> transitionOrder({
    required String orderId,
    required OrderStatus to,
    String note = '',
    String? trackingUrl,
    String? carrier,
    String? cancelledReason,
  });

  Future<Order> markPayment({
    required String orderId,
    required String method,
    String? transactionReference,
    bool isCod = false,
  });

  Future<Order> issueRefund({
    required String orderId,
    required int amountPaise,
    required String reason,
  });

  Future<Order> createCounterOrder({
    required List<DraftLine> lines,
    required String contactPhone,
    String contactName = '',
    String paymentMethod = 'cash',
    String note = '',
  });

  Future<String?> invoicePdfUrl(String orderId);

  Future<PagedResult<UserProfile>> listCustomers({
    String? search,
    UserRole? role,
    int pageSize = 25,
    String? cursor,
  });

  Future<UserProfile> customerDetail(String uid);

  Future<void> setCustomerRole({required String uid, required UserRole role, required String reason});

  Future<void> setCustomerBlocked({
    required String uid,
    required bool blocked,
    required String reason,
  });

  Future<List<WholesaleApplication>> wholesaleApplications({bool openOnly = true});

  Future<void> decideWholesale({
    required String applicationId,
    required WholesaleStatus decision,
    required String note,
  });

  Future<void> saveCustomerPrice(CustomerPriceOverride override);

  Future<void> deleteCustomerPrice(String overrideId);

  Future<List<Review>> moderationQueue({ReviewStatus status = ReviewStatus.pending});

  Future<void> decideReview({
    required String reviewId,
    required ReviewStatus decision,
    String note = '',
  });

  Future<List<Coupon>> listCoupons();

  Future<Coupon> saveCoupon(Coupon coupon);

  Future<void> deleteCoupon(String couponId);

  Future<StoreSettings> settings();

  Future<void> saveSettings(StoreSettings settings);

  Future<PagedResult<AuditLog>> auditLogs({
    String? entityType,
    String? action,
    int pageSize = 50,
    String? cursor,
  });

  Future<List<ReportRow>> salesByProduct({required DateTime from, required DateTime to});

  Future<List<ReportRow>> salesByCategory({required DateTime from, required DateTime to});

  Future<List<ReportRow>> retailVsWholesale({required DateTime from, required DateTime to});

  Future<List<ReportRow>> slowMoving({int limit = 50});

  Future<List<ReportRow>> couponPerformance();

  Future<List<ReportRow>> inventoryValuation();

  Future<List<ReportRow>> cancelledOrRefunded({required DateTime from, required DateTime to});

  /// Returns CSV text generated from the same rows the on-screen report shows, so an export can
  /// never disagree with the dashboard.
  Future<String> exportCsv({required String reportId, DateTime? from, DateTime? to});

  /// Bulk product/category import. Validated row-by-row server-side; returns per-row errors
  /// instead of partially committing a bad sheet.
  Future<ImportSummary> importProductsCsv(String csv);
}

final class ImportSummary {
  const ImportSummary({
    required this.totalRows,
    required this.imported,
    required this.errors,
  });

  final int totalRows;
  final int imported;
  final List<String> errors;

  bool get isClean => errors.isEmpty;
}
