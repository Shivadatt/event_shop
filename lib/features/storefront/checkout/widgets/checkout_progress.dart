import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/checkout/checkout_controller.dart';

/// Step rail for checkout. Completed steps are tappable to go back and edit; later steps are not,
/// because validation is what unlocks them.
final class CheckoutProgress extends StatelessWidget {
  const CheckoutProgress({super.key, required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = controller.step.value;
      if (context.isCompactLayout) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OmText(
              'Step ${current.index + 1} of ${CheckoutStep.ordered.length} · ${current.label}',
              variant: OmTextVariant.label,
            ),
            const SizedBox(height: OmSpacing.sm),
            OmText(current.subtitle, variant: OmTextVariant.h3),
          ],
        );
      }

      return Semantics(
        label: 'Checkout progress',
        child: Row(
          children: <Widget>[
            for (final step in CheckoutStep.ordered) ...<Widget>[
              Expanded(
                child: _StepPill(
                  step: step,
                  state: step.index < current.index
                      ? _StepState.done
                      : (step == current ? _StepState.active : _StepState.upcoming),
                  onTap: step.index < current.index ? () => controller.jumpTo(step) : null,
                ),
              ),
              if (step != CheckoutStep.ordered.last)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.omText.muted.color,
                ),
            ],
          ],
        ),
      );
    });
  }
}

enum _StepState { done, active, upcoming }

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.step,
    required this.state,
    required this.onTap,
  });

  final CheckoutStep step;
  final _StepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final isActive = state == _StepState.active;
    final isDone = state == _StepState.done;
    return InkWell(
      onTap: onTap,
      borderRadius: OmRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm, horizontal: OmSpacing.xs),
        child: Row(
          children: <Widget>[
            Container(
              height: 24,
              width: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? OmColors.gold
                    : (isDone ? OmColors.success : Colors.transparent),
                border: Border.all(
                  color: isActive
                      ? OmColors.gold
                      : (isDone ? OmColors.success : styles.muted.color!),
                ),
              ),
              child: Icon(
                isDone ? Icons.check : Icons.circle_outlined,
                size: 14,
                color: isActive || isDone ? OmColors.paper : styles.muted.color,
              ),
            ),
            const SizedBox(width: OmSpacing.sm),
            Flexible(
              child: Text(
                step.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isActive ? styles.bodyStrong : styles.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
