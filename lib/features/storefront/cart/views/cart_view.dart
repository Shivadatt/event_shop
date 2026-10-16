import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/cart/cart_controller.dart';
import 'package:om_events/features/storefront/cart/widgets/cart_lines.dart';
import 'package:om_events/features/storefront/cart/widgets/cart_totals.dart';
import 'package:om_events/features/storefront/cart/widgets/coupon_field.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';

/// `/cart`. Quantity intent lives in `CartStore`; every rupee here is `PricingEngine` display
/// math, and the panel says in plain words that the payable total is the server's to decide.
final class CartView extends GetView<CartController> {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Your cart',
      body: Obx(() {
        if (controller.loading.value && controller.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: OmSpacing.xxl),
            child: OmLoading(message: 'Loading your cart…'),
          );
        }

        if (controller.isEmpty) {
          final failure = controller.failure.value;
          if (failure != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: OmSpacing.xl),
              child: OmErrorState(failure: failure, onRetry: controller.retry),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: OmSpacing.xl),
            child: OmEmptyState.emptyCart(
              onBrowse: () => Get.toNamed<dynamic>(OmRoutes.search),
            ),
          );
        }

        final totals = controller.totals;
        final settings = Get.find<SettingsStore>().value;
        final lines = <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OmText(
                  '${controller.lineCount} item'
                  '${controller.lineCount == 1 ? '' : 's'} · '
                  '${controller.unitCount} units',
                  variant: OmTextVariant.h2,
                ),
              ),
              OmButton(
                label: 'Clear cart',
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                icon: Icons.delete_sweep_outlined,
                onPressed: () => _confirmClear(context),
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.md),
          if (controller.failure.value != null)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.md),
              child: OmErrorState(
                failure: controller.failure.value!,
                compact: true,
                onRetry: controller.retry,
              ),
            ),
          CartLines(controller: controller),
          const SizedBox(height: OmSpacing.lg),
          CouponField(controller: controller),
          const SizedBox(height: OmSpacing.lg),
          if (controller.belowMinimumOrderValue)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.md),
              child: _Advisory(
                icon: Icons.minimum_outlined,
                text: 'This store ships from ${OmMoney.format(settings.minOrderValuePaise)}. '
                    'You are at ${OmMoney.format(totals.subtotalPaise)} right now — checkout '
                    'will tell you if that is still not enough.',
              ),
            ),
          if (settings.taxInclusive)
            const Padding(
              padding: EdgeInsets.only(bottom: OmSpacing.md),
              child: _Advisory(
                icon: Icons.receipt_long_outlined,
                text: 'Listed prices already include GST, so no tax line is added.',
              ),
            ),
        ];

        final summary = <Widget>[
          CartTotalsPanel.estimate(
            totals: totals,
            couponCode: controller.quoteFor.value.isEmpty
                ? null
                : controller.quoteFor.value,
            shippingNote: 'Delivery is calculated from your pincode on the next step.',
          ),
          const SizedBox(height: OmSpacing.md),
          OmButton(
            label: 'Proceed to checkout',
            icon: Icons.lock_outline,
            size: OmButtonSize.large,
            expanded: true,
            onPressed: controller.openCheckout,
          ),
          const SizedBox(height: OmSpacing.md),
          OmButton(
            label: 'Keep shopping',
            variant: OmButtonVariant.outline,
            expanded: true,
            onPressed: () => Get.toNamed<dynamic>(OmRoutes.search),
          ),
          const SizedBox(height: OmSpacing.lg),
          _TrustNotes(controller: controller),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: OmSpacing.md),
          child: context.isCompactLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ...lines,
                    ...summary,
                    const SizedBox(height: OmSpacing.xl),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: lines,
                      ),
                    ),
                    const SizedBox(width: OmSpacing.xl),
                    SizedBox(
                      width: 380,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: summary,
                      ),
                    ),
                  ],
                ),
        );
      }),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final styles = context.omText;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty your cart?'),
        content: const Text(
          'Every line and the applied promo code will be removed. Saved wishlist items are '
          'not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep them', style: styles.body),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Empty cart', style: styles.bodyStrong.copyWith(color: OmColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) controller.clearCart();
  }
}

class _Advisory extends StatelessWidget {
  const _Advisory({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => OmCard(
        borderColor: OmColors.warning,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: OmColors.warning),
            const SizedBox(width: OmSpacing.sm),
            Expanded(child: OmText(text, variant: OmTextVariant.caption)),
          ],
        ),
      );
}

/// Which payment routes the store has switched on, read from `StoreSettings` — the cart only
/// describes them; eligibility is re-decided by the server at order creation.
class _TrustNotes extends StatelessWidget {
  const _TrustNotes({required this.controller});

  final CartController controller;

  @override
  Widget build(BuildContext context) {
    final methods = controller.enabledPaymentMethods;
    return OmCard(
      padding: const EdgeInsets.symmetric(
        horizontal: OmSpacing.md,
        vertical: OmSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OmText('What happens next', variant: OmTextVariant.bodyStrong),
          const SizedBox(height: OmSpacing.sm),
          OmText(
            '· Checkout re-prices every line on our servers; nothing here is a confirmed charge.\n'
            '· Stock, coupon eligibility and shipping are validated when the order is created.\n'
            '· Payment methods available to you: '
            '${methods.isEmpty ? 'confirmed at checkout' : methods.map((m) => m.label).join(', ')}.',
            variant: OmTextVariant.caption,
            maxLines: 8,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }
}
