import 'package:get/get.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';

/// A queue the operator can act on, with the number that justifies acting on it.
final class AdminQueueTile {
  const AdminQueueTile({
    required this.label,
    required this.count,
    required this.route,
    required this.caption,
    this.countIsEstimate = false,
  });

  final String label;

  /// Null means "the server did not tell us", which the tile renders as `Unknown` rather than 0 —
  /// a zero on a queue is a lie an operator will act on.
  final int? count;
  final String route;
  final String caption;
  final bool countIsEstimate;
}

/// The admin home page. Everything on it is a count or a short list that links to the real screen;
/// it never mutates, so there is exactly one reason for it to be wrong (a failed read), and that
/// reason is rendered as a failure state rather than as zeros.
final class DashboardController extends AdminController {
  DashboardController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final Rxn<DashboardStats> stats = Rxn<DashboardStats>();
  final RxList<Product> lowStock = <Product>[].obs;
  final RxList<Order> fulfilment = <Order>[].obs;
  final RxList<Review> pendingReviews = <Review>[].obs;
  final RxList<WholesaleApplication> pendingWholesale = <WholesaleApplication>[].obs;

  /// `DashboardStats` carries only `pendingOrders`/`pendingPayments`, so the per-status breakdown
  /// is assembled from one-row page reads and their `totalEstimate`. Any status with no estimate
  /// is null, and the tile says "Unknown" instead of inventing a count.
  final RxMap<OrderStatus, int?> statusCounts = <OrderStatus, int?>{}.obs;

  static const List<OrderStatus> _pipeline = <OrderStatus>[
    OrderStatus.placed,
    OrderStatus.confirmed,
    OrderStatus.processing,
    OrderStatus.packed,
  ];

  Future<void> loadAll() async {
    await guard<bool>(() async {
      final (
        dashboard,
        low,
        queuePages,
        reviews,
        wholesale,
      ) = await (
          _admin.dashboard(),
          _admin.lowStockReport(limit: 20),
          Future.wait(_pipeline.map((s) => _admin.listOrders(status: s, pageSize: 5))),
          _admin.moderationQueue(status: ReviewStatus.pending),
          _admin.wholesaleApplications(openOnly: true),
        );

      stats.value = dashboard;
      lowStock.assignAll(low);
      fulfilment.assignAll(queuePages.expand((page) => page.items).toList(growable: false));
      pendingReviews.assignAll(reviews);
      pendingWholesale.assignAll(wholesale.where((a) => a.isOpen).toList(growable: false));
      return true;
    });
    await loadStatusCounts();
  }

  Future<void> loadStatusCounts() async {
    final counts = <OrderStatus, int?>{};
    await Future.wait(OrderStatus.values.map((status) async {
      counts[status] = await _countFor(status);
    }));
    statusCounts.assignAll(counts);
  }

  Future<int?> _countFor(OrderStatus status) async {
    try {
      final page = await _admin.listOrders(status: status, pageSize: 1);
      return page.totalEstimate ?? (page.hasMore ? 1 : page.items.length);
    } catch (_) {
      // A count that did not load is not zero. Reporting zero would tell an operator the queue is
      // clear when the read simply failed.
      return null;
    }
  }

  List<AdminQueueTile> get queueTiles => <AdminQueueTile>[
        AdminQueueTile(
          label: 'Reviews awaiting moderation',
          count: pendingReviews.length,
          route: OmRoutes.adminReviews,
          caption: 'first page of the moderation queue',
        ),
        AdminQueueTile(
          label: 'Wholesale applications',
          count: pendingWholesale.length,
          route: OmRoutes.adminWholesale,
          caption: 'open applications',
        ),
        AdminQueueTile(
          label: 'Low stock',
          count: stats.value?.lowStockCount,
          route: OmRoutes.adminInventory,
          caption: 'products at or under their threshold',
        ),
        AdminQueueTile(
          label: 'Out of stock',
          count: stats.value?.outOfStockCount,
          route: OmRoutes.adminInventory,
          caption: 'products at zero',
        ),
        AdminQueueTile(
          label: 'Unpaid orders',
          count: stats.value?.pendingPayments,
          route: OmRoutes.adminOrders,
          caption: 'awaiting settlement',
        ),
      ];

  /// Revenue/orders tiles read the stats document. A null stats value renders as "not loaded",
  /// never as `₹0`, which would look like a bad trading day rather than a failed read.
  DashboardStats? get headline => stats.value;

  int? get revenueTodayPaise => stats.value?.revenueTodayPaise;
  int? get revenueMonthPaise => stats.value?.revenueMonthPaise;

  List<PipelineCount> get pipeline => _pipeline
      .map(
        (status) => PipelineCount(
          status: status,
          count: statusCounts[status],
        ),
      )
      .toList(growable: false);

  List<Product> get lowStockSample => lowStock.take(8).toList(growable: false);

  bool get hasLowStock => lowStock.isNotEmpty;
}

final class PipelineCount {
  const PipelineCount({required this.status, required this.count});

  final OrderStatus status;
  final int? count;

  String get label => switch (status) {
        OrderStatus.placed => 'Placed',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.processing => 'Processing',
        OrderStatus.packed => 'Packed',
        _ => status.code,
      };

  String get countLabel => count == null ? 'Unknown' : '$count';
}

/// `PagedResult` re-exported so the pipeline helper stays readable.
typedef OrderPage = PagedResult<Order>;
