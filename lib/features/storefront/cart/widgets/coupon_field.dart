import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/cart/cart_controller.dart';

/// Coupon entry for the cart and the checkout review step. The discount it displays is the
/// repository's quote for this exact cart, never a locally computed percentage.
final class CouponField extends StatefulWidget {
  const CouponField({super.key, required this.controller});

  final CartController controller;

  @override
  State<CouponField> createState() => _CouponFieldState();
}

class _CouponFieldState extends State<CouponField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.quoteFor.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _apply() {
    final code = _text.text.trim();
    widget.controller.applyCoupon(code);
  }

  void _clear() {
    _text.clear();
    widget.controller.clearCoupon();
  }

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;

    return Obx(() {
      final quote = widget.controller.quote.value;
      final failure = widget.controller.couponFailure.value;
      final applied = widget.controller.quoteFor.value;
      final discount = quote?.discountPaise ?? 0;

      return OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.local_offer_outlined, size: 18, color: OmColors.gold),
                const SizedBox(width: OmSpacing.sm),
                Expanded(child: Text('Promo code', style: styles.bodyStrong)),
                if (applied.isNotEmpty)
                  OmBadge(
                    label: discount > 0
                        ? '${OmMoney.format(discount)} off applied'
                        : 'Applied',
                    tone: OmTone.success,
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: OmSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: OmTextField(
                    label: 'Code',
                    hint: 'ENTER10',
                    controller: _text,
                    prefixIcon: Icons.confirmation_number_outlined,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _apply(),
                    enabled: !widget.controller.applyingCoupon.value,
                  ),
                ),
                const SizedBox(width: OmSpacing.sm),
                if (applied.isNotEmpty)
                  OmButton(
                    label: 'Remove',
                    variant: OmButtonVariant.outline,
                    onPressed: _clear,
                  )
                else
                  OmButton(
                    label: 'Apply',
                    variant: OmButtonVariant.secondary,
                    loading: widget.controller.applyingCoupon.value,
                    busyLabel: 'Checking…',
                    onPressed: _apply,
                  ),
              ],
            ),
            if (quote != null && quote.freeShipping) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              OmText(
                'This code also waives the delivery charge; the server applies it at checkout.',
                variant: OmTextVariant.caption,
              ),
            ],
            if (quote != null && quote.reason.isNotEmpty) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              OmText(quote.reason, variant: OmTextVariant.caption),
            ],
            if (failure != null) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              OmErrorState(failure: failure, compact: true),
            ],
          ],
        ),
      );
    });
  }
}
