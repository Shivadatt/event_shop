import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/order_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';

/// Orders list: server-paged, filtered by status, payment status, delivery mode, date range and a
/// free-text search.
///
/// Every filter is passed to the repository as a nullable value — an unset date bound is sent as
/// null, never as a fabricated epoch — and the table renders exactly the page the server returned.
final class OrdersController extends AdminController with PagedAdminList<Order> {
  OrdersController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final Rxn<OrderStatus> statusFilter = Rxn<OrderStatus>();
  final Rxn<PaymentStatus> paymentFilter = Rxn<PaymentStatus>();
  final Rxn<DeliveryMode> deliveryFilter = Rxn<DeliveryMode>();
  final Rxn<DateTime> from = Rxn<DateTime>();
  final Rxn<DateTime> to = Rxn<DateTime>();
  final RxString search = ''.obs;

  /// Set when the screen was opened from a customer record. The repository filters server-side;
  /// this controller never filters the returned page itself.
  final RxnString customerId = RxnString();

  @override
  void onInit() {
    super.onInit();
    loadFirstPage();
  }

  bool get hasFilters =>
      search.value.isNotEmpty ||
      statusFilter.value != null ||
      paymentFilter.value != null ||
      deliveryFilter.value != null ||
      from.value != null ||
      to.value != null ||
      customerId.value != null;

  /// Inclusive bounds: a "from" date means from 00:00 that day, a "to" date means through
  /// 23:59:59.999 that day, so an operator picking one day gets that whole day.
  DateTime? get fromBound {
    final value = from.value;
    return value == null ? null : DateTime(value.year, value.month, value.day);
  }

  DateTime? get toBound {
    final value = to.value;
    if (value == null) return null;
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  }

  @override
  Future<PagedResult<Order>> fetch({String? cursor}) => _admin.listOrders(
        status: statusFilter.value,
        paymentStatus: paymentFilter.value,
        search: search.value.isEmpty ? null : search.value,
        from: fromBound,
        to: toBound,
        pageSize: pageSize,
        cursor: cursor,
        // NEEDS OWNER(AdminRepository): `DeliveryMode? deliveryMode` and `String? customerId` on
        // `listOrders`. A delivery-mode or single-customer queue cannot be filtered client-side
        // without paging the whole order collection, which the panel must not do.
        deliveryMode: deliveryFilter.value,
        customerId: customerId.value,
      );

  void applySearch(String value) {
    search.value = value.trim();
    loadFirstPage();
  }

  void applyStatus(OrderStatus? value) {
    statusFilter.value = value;
    loadFirstPage();
  }

  void applyPaymentStatus(PaymentStatus? value) {
    paymentFilter.value = value;
    loadFirstPage();
  }

  void applyDeliveryMode(DeliveryMode? value) {
    deliveryFilter.value = value;
    loadFirstPage();
  }

  void applyFrom(DateTime? value) {
    from.value = value;
    loadFirstPage();
  }

  void applyTo(DateTime? value) {
    to.value = value;
    loadFirstPage();
  }

  void clearFilters() {
    search.value = '';
    statusFilter.value = null;
    paymentFilter.value = null;
    deliveryFilter.value = null;
    from.value = null;
    to.value = null;
    customerId.value = null;
    loadFirstPage();
  }

  void openDetail(String orderId) => Get.toNamed<dynamic>(OmRoutes.forAdminOrder(orderId));

  /// CSV of the rows this page already holds.
  ///
  /// It is deliberately built from the loaded page rather than re-queried, and the dialog states
  /// how many rows were loaded — an export that silently covered a different set of orders than
  /// the table would be worse than no export.
  String exportLoaded() => OmCsv.build(
        headers: const <String>[
          'orderNumber',
          'placedAt',
          'status',
          'paymentStatus',
          'paymentMethod',
          'deliveryMode',
          'customer',
          'contactPhone',
          'items',
          'totalPaise',
          'paidPaise',
          'refundedPaise',
          'orderId',
        ],
        rows: <List<Object?>>[
          for (final order in rows)
            <Object?>[
              order.orderNumber,
              AdminFormat.dateTime(order.createdAt),
              order.status.code,
              order.paymentStatus.code,
              order.paymentMethod,
              order.deliveryMode.code,
              order.isGuest ? 'guest' : order.userId,
              order.contactPhone,
              order.totalQty,
              order.totals.grandTotalPaise,
              order.totals.paidPaise,
              order.totals.refundedPaise,
              order.id,
            ],
        ],
      );
}

/// One order: line-level price snapshots, forward-only status transitions, payment marking, refund
/// request and invoice reprint.
///
/// Reads go through `OrderRepository.byId`, which Firestore rules allow for staff (`isStaff()` may
/// read any order). Writes go through `AdminRepository`, whose Cloud Function re-checks the role,
/// re-applies the transition table, restores stock and writes the audit row in one transaction —
/// this class only ever sends intent.
final class OrderDetailController extends AdminController {
  OrderDetailController({required this.orderId});

  final String orderId;

  final OrderRepository _orders = Get.find<OrderRepository>();
  final AdminRepository _admin = Get.find<AdminRepository>();

  final Rxn<Order> order = Rxn<Order>();
  final RxnString invoiceUrl = RxnString();
  final RxList<String> issues = <String>[].obs();

  Order? get value => order.value;

  /// Refunds and payment marking are owner/admin surfaces. `PricingAdminGuard` is not on this
  /// route, so the screen gates the control itself and says why — while the function stays the
  /// authority regardless of what this page renders.
  bool get canIssueRefund => session.canEditPricing;
  bool get canMarkPayment => session.role.canManageStore;

  /// The only transitions this screen will offer. Anything outside the server's own table is
  /// refused here *and* by the function, so a stale tab cannot drag a dispatched parcel back to
  /// "placed".
  List<OrderStatus> get availableSteps => order.value?.status.nextSteps ?? const <OrderStatus>[];

  bool get isTerminal => availableSteps.isEmpty;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() => guard<bool>(() async {
        order.value = await _orders.byId(orderId);
        return true;
      });

  /// Rejects a move the model itself does not allow before it is sent.
  Future<bool> transitionTo(
    OrderStatus target, {
    String note = '',
    String? trackingUrl,
    String? carrier,
    String? cancelledReason,
  }) async {
    final current = order.value;
    if (current == null) return false;
    if (!current.status.nextSteps.contains(target)) {
      announce(
        '${current.status.code} cannot move directly to ${target.code}. Only the forward steps '
        'listed on this card are offered, and the function enforces the same table.',
        error: true,
      );
      return false;
    }
    final updated = await mutate<Order>(
      () => _admin.transitionOrder(
        orderId: current.id,
        to: target,
        note: note,
        trackingUrl: trackingUrl,
        carrier: carrier,
        cancelledReason: cancelledReason,
      ),
    );
    if (updated != null) {
      order.value = updated;
      issues.clear();
      announce(
        'Order marked ${target.code}. The transition, any stock restore, the customer '
        'notification and the audit row were written by the server in one transaction.',
      );
      return true;
    }
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
    return false;
  }

  Future<bool> markPayment({
    required String method,
    String? transactionReference,
    bool isCod = false,
  }) async {
    final current = order.value;
    if (current == null) return false;
    final updated = await mutate<Order>(
      () => _admin.markPayment(
        orderId: current.id,
        method: method,
        transactionReference: transactionReference,
        isCod: isCod,
      ),
    );
    if (updated != null) {
      order.value = updated;
      announce(
        'Payment recorded as ${updated.paymentStatus.code}. The paid amount on this order came '
        'back from the server, not from this form.',
      );
      return true;
    }
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
    return false;
  }

  /// Requests a refund. [suggestedMaxPaise] is derived from the stored snapshot purely to cap the
  /// input; the function recomputes what is refundable and refuses more.
  Future<bool> requestRefund({required int amountPaise, required String reason}) async {
    final current = order.value;
    if (current == null) return false;
    if (amountPaise <= 0) {
      announce('Enter a refund amount above zero.', error: true);
      return false;
    }
    if (reason.trim().isEmpty) {
      announce('A refund needs a reason — it is written to the audit log.', error: true);
      return false;
    }
    final updated = await mutate<Order>(
      () => _admin.issueRefund(
        orderId: current.id,
        amountPaise: amountPaise,
        reason: reason.trim(),
      ),
    );
    if (updated != null) {
      order.value = updated;
      announce(
        'Refund recorded. Payment status is now ${updated.paymentStatus.code} and the reason is '
        'in the audit log.',
      );
      return true;
    }
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
    return false;
  }

  /// Reprints the invoice by re-reading its URL. A signed URL is never stored, so this asks every
  /// time rather than reusing a link that may have expired.
  Future<String?> loadInvoiceUrl() async {
    final url = await guard<String?>(() => _admin.invoicePdfUrl(orderId), silent: true);
    if (url == null) {
      final error = failure.value;
      if (error != null) announce(error.message, error: true);
      return null;
    }
    invoiceUrl.value = url;
    return url;
  }

  /// Snapshot fields only. Nothing here re-prices a line: the point of the stored item is that a
  /// later product edit cannot rewrite what the buyer actually paid.
  String priceSnapshotNote(OrderItem item) {
    final band = item.slabLabel ??
        (item.slabMinQty == null
            ? 'no band'
            : '${item.slabMinQty}${item.slabMaxQty == null ? '+' : '-${item.slabMaxQty}'} units');
    return '${item.qty} × ${item.unit} at the banded rate, band: $band';
  }
}

/// Failure types are re-exported implicitly through the base controller's failure sink; this
/// helper keeps the detail screen's guards readable without a second copy of the switch.
String orderFailureHint(OmFailure failure) => switch (failure) {
      PermissionFailure() => 'This account no longer holds a store-management role.',
      NotFoundFailure() => 'That order does not exist or was removed.',
      ConflictFailure() => 'Someone else changed this order. Reload before acting again.',
      ValidationFailure() => 'The server refused this change. Check the note and reason fields.',
      _ => 'The order could not be changed.'
    };
