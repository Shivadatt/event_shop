import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/features/storefront/cart/widgets/cart_totals.dart';
import 'package:om_events/features/storefront/checkout/checkout_controller.dart';
import 'package:om_events/features/storefront/checkout/widgets/checkout_progress.dart';
import 'package:om_events/features/storefront/checkout/widgets/checkout_review_step.dart';
import 'package:om_events/features/storefront/checkout/widgets/checkout_steps.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';

/// `/checkout`: contact → delivery → review. The payable total the buyer ends up seeing is the
/// `OrderReceipt` from `OrderRepository.createOrder`; every number above it is labelled an
/// estimate.
final class CheckoutView extends GetView<CheckoutController> {
  const CheckoutView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Checkout',
      body: Obx(() {
        final settings = Get.find<SettingsStore>();
        final rows = controller.rows;

        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: OmSpacing.xl),
            child: OmEmptyState(
              title: 'There is nothing to check out',
              message: 'Your cart is empty or the order was already placed. Add items first.',
              icon: Icons.shopping_bag_outlined,
            ),
          );
        }

        if (controller.isGuestCheckout && !controller.guestAllowed) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: OmSpacing.xl),
            child: OmEmptyState(
              title: 'An account is required to order',
              message: controller.guestGate ?? 'Please sign in to continue.',
              icon: Icons.lock_outline,
              actionLabel: 'Sign in',
              onAction: controller.goToLogin,
            ),
          );
        }

        if (settings.failure.value != null && settings.settings.value == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: OmSpacing.xl),
            child: OmErrorState(failure: settings.failure.value!, onRetry: controller.retrySettings),
          );
        }

        final step = controller.step.value;
        final body = switch (step) {
          CheckoutStep.contact => CheckoutContactStep(controller: controller),
          CheckoutStep.delivery => CheckoutDeliveryStep(controller: controller),
          CheckoutStep.review => CheckoutReviewStep(controller: controller),
        };

        final summary = <Widget>[
          CartTotalsPanel.estimate(
            totals: controller.totals,
            couponCode: controller.appliedCouponCode.isEmpty
                ? null
                : controller.appliedCouponCode,
            shippingNote: controller.isPickup
                ? 'Pickup selected — no delivery charge is estimated.'
                : 'Estimated from the delivery band for ${controller.activePincode.value.isEmpty ? 'your pincode' : controller.activePincode.value}.',
          ),
          const SizedBox(height: OmSpacing.md),
          CheckoutSubmitCard(controller: controller),
          const SizedBox(height: OmSpacing.md),
          Obx(
            () => controller.failure.value == null
                ? const SizedBox.shrink()
                : OmErrorState(
                    failure: controller.failure.value!,
                    compact: true,
                    onRetry: controller.next,
                  ),
          ),
          const SizedBox(height: OmSpacing.md),
          OmButton(
            label: 'Back to cart',
            variant: OmButtonVariant.outline,
            expanded: true,
            onPressed: controller.openCart,
          ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: OmSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CheckoutProgress(controller: controller),
              const OmDivider(space: OmSpacing.md),
              if (context.isCompactLayout)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    body,
                    const SizedBox(height: OmSpacing.lg),
                    ...summary,
                    if (step != CheckoutStep.review) ...<Widget>[
                      const SizedBox(height: OmSpacing.md),
                      _StepNav(controller: controller),
                    ] else
                      const _BackToEdit(),
                    const SizedBox(height: OmSpacing.xl),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          body,
                          const SizedBox(height: OmSpacing.lg),
                          if (step != CheckoutStep.review)
                            _StepNav(controller: controller)
                          else
                            const _BackToEdit(),
                        ],
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
            ],
          ),
        );
      }),
    );
  }
}

class _StepNav extends StatelessWidget {
  const _StepNav({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    final isLast = controller.step.value == CheckoutStep.ordered[CheckoutStep.ordered.length - 2];
    return Row(
      children: <Widget>[
        if (controller.step.value != CheckoutStep.contact)
          OmButton(
            label: 'Back',
            variant: OmButtonVariant.outline,
            onPressed: controller.back,
          ),
        const Spacer(),
        OmButton(
          label: isLast ? 'Review order' : 'Continue',
          icon: Icons.arrow_forward,
          onPressed: controller.next,
        ),
      ],
    );
  }
}

class _BackToEdit extends StatelessWidget {
  const _BackToEdit();

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          OmButton(
            label: 'Back to delivery',
            variant: OmButtonVariant.outline,
            size: OmButtonSize.small,
            onPressed: () => Get.find<CheckoutController>().back(),
          ),
        ],
      );
}
