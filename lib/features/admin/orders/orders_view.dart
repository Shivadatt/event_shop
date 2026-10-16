import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/orders/orders_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// Orders queue.
///
/// Filters are sent to the server and the table shows the page it returned. Money columns are the
/// stored snapshot values formatted for display — nothing here adds up a payable total.
final class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  OrdersController get controller => Get.find<OrdersController>();
  late final TextEditingController _search =
      TextEditingController(text: controller.search.value);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (controller.rows.isEmpty) {
      Get.snackbar('Nothing to export', 'Load at least one order first.');
      return;
    }
    await omShowAdminCsv(
      context,
      title: 'Orders export',
      csv: controller.exportLoaded(),
      totalRows: controller.rows.length,
    );
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
        child: Obx(() => OmAdminPanel<Order>(
              isLoading: controller.isLoading.value,
              hasLoaded: controller.hasLoaded.value,
              failure: controller.failure.value,
              isEmpty: controller.rows.isEmpty,
              onRetry: controller.loadFirstPage,
              empty: OmEmptyState(
                icon: Icons.receipt_long_outlined,
                title: controller.hasFilters ? 'No orders match' : 'No orders yet',
                message: controller.hasFilters
                    ? 'Nothing matched the current filters. Orders are filtered server-side, so '
                        'an empty page means the query genuinely matched nothing.'
                    : 'No order has been placed yet. Counter and WhatsApp orders land here too '
                        'once they are created.',
                actionLabel: controller.hasFilters ? 'Clear filters' : null,
                onAction: controller.hasFilters ? controller.clearFilters : null,
              ),
              builder: (context) => OmAdminPage(
                title: 'Orders',
                eyebrow: 'Fulfilment',
                subtitle: '${controller.rows.length} orders on this page',
                actions: <Widget>[
                  OmButton(
                    label: 'Export loaded rows',
                    icon: Icons.file_download_outlined,
                    variant: OmButtonVariant.secondary,
                    onPressed: controller.rows.isEmpty ? null : _export,
                  ),
                  OmButton(
                    label: 'Reload',
                    variant: OmButtonVariant.ghost,
                    icon: Icons.refresh,
                    onPressed: controller.loadFirstPage,
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Filters(controller: controller, search: _search),
                    const SizedBox(height: OmSpacing.md),
                    OmAdminResponsiveList(
                      itemCount: controller.rows.length,
                      onTapRow: (index) => controller.openDetail(controller.rows[index].id),
                      columns: <OmAdminColumn>[
                        OmAdminColumn(
                          heading: 'Order',
                          cell: (context, index) => _OrderCell(order: controller.rows[index]),
                        ),
                        OmAdminColumn(
                          heading: 'Customer',
                          cell: (context, index) => _CustomerCell(order: controller.rows[index]),
                        ),
                        OmAdminColumn(
                          heading: 'Items',
                          numeric: true,
                          cell: (context, index) {
                            final order = controller.rows[index];
                            return OmText(
                              '${order.totalQty} in ${order.items.length} line(s)',
                              variant: OmTextVariant.caption,
                            );
                          },
                        ),
                        OmAdminColumn(
                          heading: 'Total (stored)',
                          numeric: true,
                          cell: (context, index) {
                            final totals = controller.rows[index].totals;
                            final styles = context.omText;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(OmMoney.format(totals.grandTotalPaise), style: styles.price),
                                if (totals.refundedPaise > 0)
                                  Text(
                                    'refunded ${OmMoney.format(totals.refundedPaise)}',
                                    style: styles.caption,
                                  ),
                              ],
                            );
                          },
                        ),
                        OmAdminColumn(
                          heading: 'Status',
                          cell: (context, index) => Wrap(
                            spacing: OmSpacing.xs,
                            runSpacing: OmSpacing.xs,
                            children: <Widget>[
                              orderBadge(controller.rows[index].status),
                              paymentBadge(controller.rows[index].paymentStatus),
                            ],
                          ),
                        ),
                        OmAdminColumn(
                          heading: 'Delivery',
                          cell: (context, index) {
                            final order = controller.rows[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                deliveryBadge(order.deliveryMode),
                                OmText(order.source, variant: OmTextVariant.caption),
                              ],
                            );
                          },
                        ),
                        OmAdminColumn(
                          heading: 'Actions',
                          cell: (context, index) => Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              OmIconButton(
                                icon: Icons.open_in_new,
                                tooltip: 'Open order ${controller.rows[index].orderNumber}',
                                size: 34,
                                onPressed: () => controller.openDetail(controller.rows[index].id),
                              ),
                            ],
                          ),
                        ),
                      ],
                      cardBuilder: (context, index) {
                        final order = controller.rows[index];
                        return OmAdminRowCard(
                          title: order.orderNumber.isEmpty ? order.id : order.orderNumber,
                          badges: <Widget>[
                            orderBadge(order.status),
                            paymentBadge(order.paymentStatus),
                            deliveryBadge(order.deliveryMode),
                          ],
                          lines: <String>[
                            AdminFormat.dateTime(order.createdAt),
                            order.isGuest
                                ? 'Guest · ${AdminFormat.missing(order.contactPhone)}'
                                : 'User ${order.userId}',
                            '${order.totalQty} unit(s) in ${order.items.length} line(s) · '
                                '${OmMoney.format(order.totals.grandTotalPaise)} (stored total)',
                          ],
                          onTap: () => controller.openDetail(order.id),
                          actions: <Widget>[
                            OmButton(
                              label: 'Open',
                              size: OmButtonSize.small,
                              onPressed: () => controller.openDetail(order.id),
                            ),
                          ],
                        );
                      },
                      footer: OmAdminPager(
                        loadedCount: controller.rows.length,
                        hasMore: controller.hasMore,
                        isLoading: controller.isLoading.value,
                        onLoadMore: controller.loadMore,
                        onRefresh: controller.refresh,
                        totalEstimate: null,
                      ),
                    ),
                    const SizedBox(height: OmSpacing.lg),
                    const OmAdminNotice(
                      message: 'Totals shown here are the values the server stored when the order '
                          'was created. They are never recomputed from the current catalogue, so a '
                          'later price change cannot rewrite an old order.',
                    ),
                  ],
                ),
              ),
            )),
      );
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller, required this.search});

  final OrdersController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) => Obx(() {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmAdminFilterBar(
              searchController: search,
              searchHint: 'Order number, phone or name',
              onSearch: controller.applySearch,
              children: <Widget>[
                SizedBox(
                  width: 190,
                  child: OmDropdown<OrderStatus>(
                    label: 'Order status',
                    value: controller.statusFilter.value,
                    hint: 'Any status',
                    items: OrderStatus.values,
                    itemLabel: orderStatusLabel,
                    onChanged: controller.applyStatus,
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: OmDropdown<PaymentStatus>(
                    label: 'Payment',
                    value: controller.paymentFilter.value,
                    hint: 'Any payment state',
                    items: PaymentStatus.values,
                    itemLabel: paymentStatusLabel,
                    onChanged: controller.applyPaymentStatus,
                  ),
                ),
                Wrap(
                  spacing: OmSpacing.xs,
                  runSpacing: OmSpacing.xs,
                  children: <Widget>[
                    OmFilterChip(
                      label: 'Courier',
                      selected: controller.deliveryFilter.value == DeliveryMode.courier,
                      onTap: () => controller.applyDeliveryMode(
                        controller.deliveryFilter.value == DeliveryMode.courier
                            ? null
                            : DeliveryMode.courier,
                      ),
                    ),
                    OmFilterChip(
                      label: 'Store pickup',
                      selected: controller.deliveryFilter.value == DeliveryMode.pickup,
                      onTap: () => controller.applyDeliveryMode(
                        controller.deliveryFilter.value == DeliveryMode.pickup
                            ? null
                            : DeliveryMode.pickup,
                      ),
                    ),
                  ],
                ),
                if (controller.hasFilters)
                  OmButton(
                    label: 'Clear',
                    variant: OmButtonVariant.ghost,
                    size: OmButtonSize.small,
                    onPressed: () {
                      search.clear();
                      controller.clearFilters();
                    },
                  ),
              ],
            ),
            const SizedBox(height: OmSpacing.md),
            OmAdminFormGrid(
              children: <Widget>[
                OmAdminDateField(
                  label: 'Placed from',
                  value: controller.from.value,
                  onChanged: controller.applyFrom,
                  helper: 'Inclusive. Empty means no lower bound is sent.',
                ),
                OmAdminDateField(
                  label: 'Placed to',
                  value: controller.to.value,
                  onChanged: controller.applyTo,
                  helper: 'Inclusive through 23:59 of that day.',
                ),
              ],
            ),
          ],
        );
      });
}

class _OrderCell extends StatelessWidget {
  const _OrderCell({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          OmText(
            order.orderNumber.isEmpty ? order.id : order.orderNumber,
            variant: OmTextVariant.bodyStrong,
            maxLines: 1,
          ),
          OmText(
            AdminFormat.dateTime(order.createdAt),
            variant: OmTextVariant.caption,
          ),
          if (order.invoiceNumber.isNotEmpty)
            OmText('Invoice ${order.invoiceNumber}', variant: OmTextVariant.caption),
        ],
      );
}

class _CustomerCell extends StatelessWidget {
  const _CustomerCell({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final shipping = order.shipping;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        OmText(
          order.isGuest
              ? (shipping?.name.isNotEmpty == true ? shipping!.name : 'Guest order')
              : order.userId,
          variant: OmTextVariant.bodyStrong,
          maxLines: 2,
        ),
        OmText(
          AdminFormat.missing(order.contactPhone.isEmpty ? order.contactEmail : order.contactPhone),
          variant: OmTextVariant.caption,
        ),
        if (order.couponCode.isNotEmpty)
          OmText('Coupon ${order.couponCode}', variant: OmTextVariant.caption),
      ],
    );
  }
}
