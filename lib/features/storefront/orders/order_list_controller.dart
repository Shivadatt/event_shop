import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/order_repository.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/orders/order_actions.dart';

/// `/account/orders`. Cursor-paged from `OrderRepository.listMine`; nothing is cached beyond the
/// pages the buyer actually loaded, and a failed page is an error state, not an empty list.
final class OrderListController extends GetxController with OrderActionsMixin {
  final RxList<Order> orders = <Order>[].obs;
  final RxBool loading = true.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final Rxn<OrderStatus> statusFilter = Rxn<OrderStatus>();
  final RxString term = RxString('');

  String? _cursor;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    _cursor = null;
    final page = await safeCall<PagedResult<Order>>(
      () => Get.find<OrderRepository>().listMine(),
      onFailure: (f) => failure.value = f,
    );
    loading.value = false;
    if (page == null) return;
    orders.assignAll(page.items);
    _cursor = page.nextCursor;
    hasMore.value = page.hasMore;
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (cursor == null || loadingMore.value) return;
    loadingMore.value = true;
    final page = await safeCall<PagedResult<Order>>(
      () => Get.find<OrderRepository>().listMine(cursor: cursor),
      onFailure: (f) => failure.value = f,
    );
    loadingMore.value = false;
    if (page == null) return;
    orders.addAll(page.items);
    _cursor = page.nextCursor;
    hasMore.value = page.hasMore;
  }

  void setStatusFilter(OrderStatus? status) {
    statusFilter.value = status;
  }

  /// Filter over the pages already loaded. It is labelled as such on screen rather than
  /// pretending to be a server-side query.
  List<Order> get visible {
    final status = statusFilter.value;
    final needle = term.value.trim().toLowerCase();
    return orders
        .where((order) => status == null || order.status == status)
        .where(
          (order) =>
              needle.isEmpty ||
              order.orderNumber.toLowerCase().contains(needle) ||
              order.items.any((item) => item.name.toLowerCase().contains(needle)),
        )
        .toList(growable: false);
  }

  bool get isFiltering => statusFilter.value != null || term.value.trim().isNotEmpty;

  void clearFilters() {
    statusFilter.value = null;
    term.value = '';
  }

  /// Statuses present on the loaded pages, so the filter never offers an option with zero orders.
  List<OrderStatus> get availableStatuses {
    final present = orders.map((order) => order.status).toSet();
    return <OrderStatus>[
      for (final status in OrderStatus.values)
        if (present.contains(status)) status,
    ];
  }
}
