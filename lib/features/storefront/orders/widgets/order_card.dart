import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';
import 'package:om_events/features/storefront/orders/order_actions.dart';
import 'package:om_events/features/storefront/orders/widgets/order_status_timeline.dart';

/// One order in the history list. Table form on wide screens, card form on narrow ones, so the
/// list never needs a horizontal scrollbar.
final class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    this.actions,
    this.onOpen,
  });

  final Order order;
  final OrderActionsMixin? actions;
  final VoidCallback? onOpen;

  void _open() => Get.toNamed<dynamic>(OmRoutes.forOrder(order.id));

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return OmCard(
      onTap: onOpen ?? _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      order.orderNumber.isEmpty ? order.id : order.orderNumber,
                      style: styles.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(OmDates.dateTime(order.createdAt), style: styles.caption),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  OmMoneyText(order.totals.grandTotalPaise, style: styles.price),
                  const SizedBox(height: 2),
                  Text('${order.items.length} lines · ${order.totalQty} units', style: styles.caption),
                ],
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.xs,
            children: <Widget>[
              OrderStatusChip(status: order.status, dense: true),
              PaymentStatusChip(status: order.paymentStatus, dense: true),
              if (order.isGuest)
                const OmBadge(label: 'Guest order', dense: true),
              if (order.couponCode.isNotEmpty)
                OmBadge(label: order.couponCode, tone: OmTone.gold, dense: true, icon: Icons.local_offer),
            ],
          ),
          if (order.items.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            Text(
              order.items
                  .take(2)
                  .map((item) => '${item.qty} × ${item.name}')
                  .join(', '),
              style: styles.muted,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (order.items.length > 2)
              Text('+${order.items.length - 2} more lines', style: styles.caption),
          ],
          if (order.trackingUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.xs),
            Text('Carrier: ${order.carrier.isEmpty ? 'shared by the store' : order.carrier}',
                style: styles.caption),
          ],
          if (actions != null) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            OrderActionButtons(order: order, actions: actions!),
          ],
        ],
      ),
    );
  }
}

/// Wide list of orders. The card form is the same widget, so a column change cannot make a field
/// disappear on one breakpoint only.
final class OrderListBody extends StatelessWidget {
  const OrderListBody({
    super.key,
    required this.orders,
    this.actions,
    this.onOpen,
  });

  final List<Order> orders;
  final OrderActionsMixin? actions;
  final void Function(Order order)? onOpen;

  @override
  Widget build(BuildContext context) => OmResponsiveTable(
        minTableWidth: 1100,
        table: DataTable(
          headingRowHeight: 40,
          columnSpacing: OmSpacing.xl,
          columns: const <DataColumn>[
            DataColumn(label: Text('Order')),
            DataColumn(label: Text('Placed')),
            DataColumn(label: Text('Lines')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Payment')),
          ],
          rows: <DataRow>[
            for (final order in orders)
              DataRow(
                onSelectChanged: (_) {
                  final open = onOpen;
                  if (open != null) {
                    open(order);
                  } else {
                    Get.toNamed<dynamic>(OmRoutes.forOrder(order.id));
                  }
                },
                cells: <DataCell>[
                  DataCell(Text(order.orderNumber.isEmpty ? order.id : order.orderNumber)),
                  DataCell(Text(OmDates.date(order.createdAt))),
                  DataCell(Text('${order.items.length} · ${order.totalQty}u')),
                  DataCell(OmMoneyText(order.totals.grandTotalPaise)),
                  DataCell(OrderStatusChip(status: order.status, dense: true)),
                  DataCell(PaymentStatusChip(status: order.paymentStatus, dense: true)),
                ],
              ),
          ],
        ),
        asCards: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final order in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.md),
                child: OrderCard(order: order, actions: actions),
              ),
          ],
        ),
      );
}
