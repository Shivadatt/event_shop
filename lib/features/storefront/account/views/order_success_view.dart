import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/account/account_order_controller.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/orders/widgets/order_details_cards.dart';
import 'package:om_events/features/storefront/orders/widgets/order_status_timeline.dart';

/// `/order-success/:orderId`.
///
/// The payable figure comes from `OrderReceipt` (the server's answer) or the order document —
/// never from a client total. `priceChanged` / `wasReplay` are surfaced here as well, because a
/// buyer who reloads this page must be able to tell a fresh order from a replayed one.
final class OrderSuccessView extends GetView<OrderSuccessController> {
  const OrderSuccessView({super.key});

  @override
  Widget build(BuildContext context) {
    final receipt = controller.receipt;
    return StoreScaffold(
      title: 'Order confirmed',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: OmSpacing.lg),
          OmCard(
            elevated: true,
            borderColor: OmColors.success,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.check_circle_outline, color: OmColors.success, size: 28),
                    const SizedBox(width: OmSpacing.sm),
                    Expanded(
                      child: OmText(
                        receipt == null
                            ? 'Order ${controller.orderId.isEmpty ? 'pending' : controller.orderId}'
                            : 'Order ${receipt.orderNumber}',
                        variant: OmTextVariant.h2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OmSpacing.sm),
                const OmText(
                  'Thank you. The store has recorded this order; packing, dispatch and delivery '
                  'updates follow on this page.',
                  variant: OmTextVariant.muted,
                  overflow: TextOverflow.visible,
                ),
                if (controller.receiptNotice != null) ...<Widget>[
                  const SizedBox(height: OmSpacing.md),
                  OmCard(
                    borderColor: OmColors.warning,
                    padding: const EdgeInsets.all(OmSpacing.sm),
                    child: OmText(
                      controller.receiptNotice!,
                      variant: OmTextVariant.caption,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
                if (receipt != null) ...<Widget>[
                  const SizedBox(height: OmSpacing.lg),
                  const OmText(
                    'Amount confirmed by the store',
                    variant: OmTextVariant.label,
                  ),
                  const SizedBox(height: OmSpacing.xs),
                  OmMoneyText(receipt.totals.grandTotalPaise,
                      style: context.omText.priceLarge),
                  const SizedBox(height: OmSpacing.md),
                  _ReceiptTotals(
                    subtotal: receipt.totals.subtotalPaise,
                    slab: receipt.totals.slabDiscountPaise,
                    coupon: receipt.totals.couponDiscountPaise,
                    shipping: receipt.totals.shippingPaise,
                    tax: receipt.totals.taxPaise,
                  ),
                  if (receipt.message.isNotEmpty) ...<Widget>[
                    const SizedBox(height: OmSpacing.md),
                    OmText(receipt.message, variant: OmTextVariant.caption,
                        overflow: TextOverflow.visible),
                  ],
                ],
                const SizedBox(height: OmSpacing.lg),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  children: <Widget>[
                    OmButton(
                      label: 'View full order',
                      onPressed: controller.openOrderDetail,
                    ),
                    OmButton(
                      label: 'All my orders',
                      variant: OmButtonVariant.secondary,
                      onPressed: controller.openAccountOrders,
                    ),
                    OmButton(
                      label: 'Keep shopping',
                      variant: OmButtonVariant.ghost,
                      onPressed: controller.keepShopping,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: OmSpacing.lg),
          Obx(() {
            if (controller.loading.value && controller.order.value == null) {
              return const OmLoading(message: 'Loading the order the store wrote…');
            }
            final order = controller.order.value;
            if (order == null) {
              return OmErrorState(
                failure: controller.failure.value ??
                    const NotFoundFailure(
                      'We could not re-read this order. Your receipt above is still the store’s '
                      'confirmed copy.',
                    ),
                onRetry: controller.load,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Expanded(child: OmText('Status', variant: OmTextVariant.h3)),
                          OrderStatusChip(status: order.status),
                        ],
                      ),
                      const SizedBox(height: OmSpacing.sm),
                      OrderStatusTimeline(order: order),
                    ],
                  ),
                ),
                const SizedBox(height: OmSpacing.lg),
                OrderItemsCard(items: order.items),
                const SizedBox(height: OmSpacing.lg),
                OrderMetaCard(order: order),
                const SizedBox(height: OmSpacing.lg),
                InvoicePrintActions(order: order),
              ],
            );
          }),
          const SizedBox(height: OmSpacing.xl),
        ],
      ),
    );
  }
}

class _ReceiptTotals extends StatelessWidget {
  const _ReceiptTotals({
    required this.subtotal,
    required this.slab,
    required this.coupon,
    required this.shipping,
    required this.tax,
  });

  final int subtotal;
  final int slab;
  final int coupon;
  final int shipping;
  final int tax;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _line(context, 'Merchandise', subtotal),
          if (slab > 0) _line(context, 'Quantity savings already applied', slab),
          if (coupon > 0) _line(context, 'Coupon discount already applied', coupon),
          _line(context, 'Delivery', shipping),
          _line(context, 'Tax', tax),
        ],
      );

  Widget _line(BuildContext context, String label, int paise) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(child: OmText(label)),
            OmMoneyText(paise),
          ],
        ),
      );
}
