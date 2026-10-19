import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/cart/widgets/coupon_field.dart';
import 'package:om_events/features/storefront/checkout/checkout_controller.dart';

/// Step 3: read-only recap of the draft, payment choice, and — when the server's receipt disagrees
/// with the local estimate — the explicit re-confirmation panel.
final class CheckoutReviewStep extends StatelessWidget {
  const CheckoutReviewStep({super.key, required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Obx(
          () => controller.awaitingConfirmation.value == null
              ? const SizedBox.shrink()
              : _ChangedTotalPanel(controller: controller),
        ),
        const OmSectionHeader(title: 'Items', eyebrow: 'Order draft'),
        const SizedBox(height: OmSpacing.sm),
        _LinesCard(controller: controller),
        const SizedBox(height: OmSpacing.lg),
        _DeliveryRecap(controller: controller),
        const SizedBox(height: OmSpacing.lg),
        _PaymentPicker(controller: controller),
        const SizedBox(height: OmSpacing.lg),
        CouponField(controller: controller.cartController),
        const SizedBox(height: OmSpacing.lg),
        Obx(
          () => controller.placeFailure.value == null
              ? const SizedBox.shrink()
              : OmErrorState(
                  failure: controller.placeFailure.value!,
                  onRetry: controller.placeOrder,
                ),
        ),
      ],
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Obx(() {
      final rows = controller.rows;
      return OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: 52,
                      width: 52,
                      child: OmMediaImage(ref: row.product?.primaryImage),
                    ),
                    const SizedBox(width: OmSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          OmText(
                            row.product?.name ?? 'An item still being checked',
                            variant: OmTextVariant.bodyStrong,
                          ),
                          const SizedBox(height: 2),
                          OmText(
                            '${row.line.qty} ${row.product?.unit ?? 'units'}'
                            '${row.variant == null ? '' : ' · ${row.variant!.name}'}',
                            variant: OmTextVariant.caption,
                          ),
                          if (row.notice != null) ...<Widget>[
                            const SizedBox(height: 2),
                            OmText(row.notice!, variant: OmTextVariant.caption),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: OmSpacing.sm),
                    OmMoneyText(
                      row.canPrice ? row.price.resolution.lineTotalPaise : 0,
                      style: styles.price,
                    ),
                  ],
                ),
              ),
            const OmText(
              'These are our displayed prices for your quantities. The order server re-prices every '
              'line from the live catalogue when it creates the order.',
              variant: OmTextVariant.caption,
            ),
          ],
        ),
      );
    });
  }
}

class _DeliveryRecap extends StatelessWidget {
  const _DeliveryRecap({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isPickup = controller.isPickup;
      final snapshot = controller.buildShippingSnapshot();
      return OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: OmText(
                    isPickup ? 'Store pickup' : 'Courier delivery',
                    variant: OmTextVariant.bodyStrong,
                  ),
                ),
                OmButton(
                  label: 'Change',
                  variant: OmButtonVariant.ghost,
                  size: OmButtonSize.small,
                  onPressed: () => controller.jumpTo(CheckoutStep.contact),
                ),
              ],
            ),
            const SizedBox(height: OmSpacing.sm),
            OmText(
              <String>[
                snapshot.name,
                snapshot.singleLine,
                '${snapshot.city}, ${snapshot.state} ${snapshot.pincode}'.trim(),
              ].where((line) => line.trim().isNotEmpty).join('\n'),
              variant: OmTextVariant.muted,
              maxLines: 6,
              overflow: TextOverflow.visible,
              selectable: true,
            ),
            const SizedBox(height: OmSpacing.sm),
            OmText(
              'Contact: ${controller.email.text} · ${controller.phone.text}',
              variant: OmTextVariant.caption,
            ),
            const SizedBox(height: OmSpacing.sm),
            OmText(controller.etaLabel, variant: OmTextVariant.caption),
          ],
        ),
      );
    });
  }
}

class _PaymentPicker extends StatelessWidget {
  const _PaymentPicker({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmText('How you pay', variant: OmTextVariant.bodyStrong),
          const SizedBox(height: OmSpacing.sm),
          Obx(() {
            final methods = controller.offeredMethods;
            if (methods.isEmpty) {
              return const OmText(
                'This store has not published any payment method yet, so the server will confirm '
                'what is available when the order is created.',
                variant: OmTextVariant.caption,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final method in methods)
                  _MethodTile(
                    label: method.label,
                    description: method.description,
                    detail: controller.methodBlockReason(method) ??
                        (method.extraFeePaise > 0
                            ? 'Adds ${OmMoney.format(method.extraFeePaise)}.'
                            : null),
                    selected: controller.paymentCode.value == method.code,
                    allowed: controller.isMethodAllowedFor(method),
                    onTap: () => controller.selectPayment(method.code),
                  ),
                const SizedBox(height: OmSpacing.xs),
                Text(
                  'Availability above is this page reading the store configuration. Payment '
                  'success is never decided here — it is the gateway and the order server.',
                  style: styles.caption,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.allowed,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String description;
  final String? detail;
  final bool selected;
  final bool allowed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Opacity(
      opacity: allowed ? 1 : 0.55,
      child: OmCard(
        onTap: allowed ? onTap : null,
        highlight: selected,
        padding: const EdgeInsets.symmetric(
          horizontal: OmSpacing.md,
          vertical: OmSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? OmColors.gold : styles.muted.color,
            ),
            const SizedBox(width: OmSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OmText(label, variant: OmTextVariant.bodyStrong),
                  if (description.isNotEmpty)
                    OmText(description, variant: OmTextVariant.caption),
                  if (detail != null)
                    OmText(
                      detail!,
                      variant: OmTextVariant.caption,
                      color: allowed ? null : OmColors.warning,
                    ),
                ],
              ),
            ),
            if (!allowed) const OmBadge(label: 'Not eligible', tone: OmTone.warning, dense: true),
          ],
        ),
      ),
    );
  }
}

/// Shown when `OrderReceipt.priceChanged` or `wasReplay` is true. The order already exists at this
/// point, so the buyer either accepts the confirmed amount explicitly or asks for it to be
/// cancelled — there is no path that silently continues.
class _ChangedTotalPanel extends StatelessWidget {
  const _ChangedTotalPanel({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final receipt = controller.awaitingConfirmation.value;
    if (receipt == null) return const SizedBox.shrink();
    final changes = controller.changes;

    return OmCard(
      borderColor: OmColors.warning,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.update, color: OmColors.warning),
              const SizedBox(width: OmSpacing.sm),
              Expanded(
                child: OmText(
                  controller.confirmationHeadline,
                  variant: OmTextVariant.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          OmText(
            'Order ${receipt.orderNumber} has been created with the amounts below. Read them '
            'against what this page estimated before you continue.',
            variant: OmTextVariant.muted,
          ),
          if (receipt.message.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            OmText('Server note: ${receipt.message}', variant: OmTextVariant.caption),
          ],
          const SizedBox(height: OmSpacing.md),
          for (final change in changes)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.xs),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(change.label, style: styles.body)),
                  // Both figures are the paise the controller carried: this page never re-derives
                  // a total, it only formats what the estimate and the receipt already said.
                  OmMoneyText(change.estimatePaise, style: styles.caption),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: OmSpacing.sm),
                    child: Text('→', style: TextStyle(fontSize: 12)),
                  ),
                  OmMoneyText(
                    change.serverPaise,
                    style: styles.bodyStrong.copyWith(
                      color: change.deltaPaise > 0
                          ? OmColors.danger
                          : (change.deltaPaise < 0 ? OmColors.success : null),
                    ),
                  ),
                ],
              ),
            ),
          if (controller.serverOrder.value == null) ...<Widget>[
            const SizedBox(height: OmSpacing.xs),
            const OmText(
              'Per-line detail needs the order document, which was not readable for this guest '
              'order. The totals above are still the server\'s own figures.',
              variant: OmTextVariant.caption,
            ),
          ],
          const OmDivider(space: OmSpacing.md),
          OmSwitchRow(
            label: 'I accept the confirmed amount of ${OmMoney.format(receipt.totals.grandTotalPaise)}',
            value: controller.changesAccepted.value,
            onChanged: (value) => controller.changesAccepted.value = value,
            description: 'Until this is ticked, nothing moves you to the success page.',
          ),
          const SizedBox(height: OmSpacing.sm),
          OmTextField(
            label: 'Reason if you would rather we cancel it (optional)',
            controller: controller.declineReason,
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: OmSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OmButton(
                  label: 'Cancel this order',
                  variant: OmButtonVariant.danger,
                  loading: controller.placing.value,
                  busyLabel: 'Cancelling…',
                  onPressed: controller.declineChanges,
                ),
              ),
              const SizedBox(width: OmSpacing.md),
              Expanded(
                child: OmButton(
                  label: 'Accept and continue',
                  loading: controller.placing.value,
                  onPressed: controller.changesAccepted.value
                      ? controller.acceptChangesAndContinue
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sidebar submit control, shared by the wide and compact checkout layouts.
final class CheckoutSubmitCard extends StatelessWidget {
  const CheckoutSubmitCard({super.key, required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
        final blocked = controller.submitIssueFor(CheckoutStep.review) != null;
        return OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OmButton(
                label: 'Place order',
                icon: Icons.check_circle_outline,
                size: OmButtonSize.large,
                loading: controller.placing.value,
                busyLabel: 'Creating your order…',
                onPressed: controller.step.value == CheckoutStep.review && !blocked
                    ? controller.placeOrder
                    : null,
              ),
              const SizedBox(height: OmSpacing.sm),
              OmText(
                blocked
                    ? 'Finish the steps above first — nothing has been charged yet.'
                    : 'Placing the order asks our servers to confirm stock, prices, shipping and '
                        'payment. No amount on this page is a charge by itself.',
                variant: OmTextVariant.caption,
              ),
            ],
          ),
        );
      });
}
