import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/storefront/account/account_order_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';
import 'package:om_events/features/storefront/orders/order_actions.dart';
import 'package:om_events/features/storefront/orders/widgets/order_details_cards.dart';
import 'package:om_events/features/storefront/orders/widgets/order_status_timeline.dart';

/// `/account/order/:orderId`. Status, lines and totals exactly as the server stored them.
final class AccountOrderView extends GetView<AccountOrderController> {
  const AccountOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'Order',
      currentRoute: OmRoutes.accountOrders,
      actions: <Widget>[
        OmButton(
          label: 'All orders',
          icon: Icons.arrow_back,
          variant: OmButtonVariant.ghost,
          size: OmButtonSize.small,
          onPressed: () => Get.offNamed<dynamic>(OmRoutes.accountOrders),
        ),
      ],
      body: Obx(() {
        if (controller.loading.value && controller.order.value == null) {
          return const OmLoading(message: 'Loading your order…');
        }
        final order = controller.order.value;
        if (order == null) {
          return OmErrorState(
            failure: controller.failure.value ?? const ServerFailure(),
            onRetry: controller.load,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmCard(
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OmText(
                          order.orderNumber.isEmpty ? order.id : order.orderNumber,
                          variant: OmTextVariant.h2,
                        ),
                      ),
                      OrderStatusChip(status: order.status),
                    ],
                  ),
                  const SizedBox(height: OmSpacing.sm),
                  Wrap(
                    spacing: OmSpacing.sm,
                    runSpacing: OmSpacing.xs,
                    children: <Widget>[
                      PaymentStatusChip(status: order.paymentStatus),
                      OmBadge(
                        label: order.deliveryMode == DeliveryMode.pickup
                            ? 'Store pickup'
                            : 'Courier delivery',
                        dense: true,
                        icon: Icons.local_shipping_outlined,
                      ),
                      OmText(
                        'Placed ${OmDates.dateTime(order.createdAt)}',
                        variant: OmTextVariant.caption,
                      ),
                    ],
                  ),
                  const SizedBox(height: OmSpacing.md),
                  OrderTotalsPanel(totals: order.totals),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            OmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const OmSectionHeader(title: 'Progress'),
                  const SizedBox(height: OmSpacing.sm),
                  OrderStatusTimeline(order: order),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            OrderItemsCard(items: order.items),
            const SizedBox(height: OmSpacing.lg),
            OmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const OmSectionHeader(title: 'What you can do'),
                  const SizedBox(height: OmSpacing.sm),
                  OrderActionButtons(order: order, actions: controller),
                  if (order.status == OrderStatus.delivered) ...<Widget>[
                    const SizedBox(height: OmSpacing.md),
                    const OmText('Review an item', variant: OmTextVariant.bodyStrong),
                    const SizedBox(height: OmSpacing.sm),
                    for (final item in order.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: OmSpacing.xs),
                        child: Row(
                          children: <Widget>[
                            Expanded(child: OmText(item.name)),
                            OmButton(
                              label: 'Write a review',
                              variant: OmButtonVariant.outline,
                              size: OmButtonSize.small,
                              onPressed: () => controller.reviewItem(item),
                            ),
                          ],
                        ),
                      ),
                  ],
                  OrderActionError(failure: controller.actionFailure.value),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            OrderMetaCard(order: order),
            const SizedBox(height: OmSpacing.lg),
            InvoicePrintActions(order: order),
            const SizedBox(height: OmSpacing.xl),
          ],
        );
      }),
    );
  }
}

/// The server's totals, read back from the order document. This widget never adds anything up.
final class OrderTotalsPanel extends StatelessWidget {
  const OrderTotalsPanel({super.key, required this.totals});

  final OrderTotals totals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _TotalLine(label: 'Merchandise subtotal', money: OmMoneyText(totals.subtotalPaise)),
        if (totals.slabDiscountPaise > 0)
          _TotalLine(
            label: 'Quantity (slab) savings, deducted',
            money: OmMoneyText(totals.slabDiscountPaise),
          ),
        if (totals.couponDiscountPaise > 0)
          _TotalLine(
            label: 'Coupon discount, deducted',
            money: OmMoneyText(totals.couponDiscountPaise),
          ),
        _TotalLine(label: 'Delivery', money: OmMoneyText(totals.shippingPaise)),
        _TotalLine(label: 'Tax', money: OmMoneyText(totals.taxPaise)),
        if (totals.roundingPaise != 0)
          _TotalLine(label: 'Rounding', money: OmMoneyText(totals.roundingPaise)),
        const OmDivider(space: OmSpacing.sm),
        Row(
          children: <Widget>[
            const Expanded(child: OmText('Payable', variant: OmTextVariant.h3)),
            OmMoneyText(totals.grandTotalPaise, style: context.omText.priceLarge),
          ],
        ),
        if (totals.paidPaise > 0)
          _TotalLine(label: 'Recorded as paid', money: OmMoneyText(totals.paidPaise)),
        if (totals.refundedPaise > 0)
          _TotalLine(label: 'Refunded', money: OmMoneyText(totals.refundedPaise)),
      ],
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.money});

  final String label;
  final Widget money;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(child: OmText(label)),
            money,
          ],
        ),
      );
}
