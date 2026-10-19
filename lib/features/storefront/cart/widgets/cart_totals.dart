import 'package:flutter/material.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';

/// The single totals breakdown for the cart, the checkout review and the placed-order receipt.
///
/// It has two entry points on purpose:
///  * [CartTotalsPanel.estimate] renders `PricingEngine`'s `CartTotals` — a **display estimate**,
///    always labelled as one;
///  * [CartTotalsPanel.authoritative] renders `OrderTotals` straight off an `OrderReceipt`/`Order`,
///    which is the only figure the store actually charges.
///
/// Volume savings and promo-code savings are separate lines because they come from separate
/// authorities (slab grid vs coupon document) and must stay separately reportable.
final class CartTotalsPanel extends StatelessWidget {
  const CartTotalsPanel._({
    required this.subtotalPaise,
    required this.slabSavingsPaise,
    required this.couponDiscountPaise,
    required this.shippingPaise,
    required this.taxPaise,
    required this.roundingPaise,
    required this.payablePaise,
    required this.lineCount,
    required this.unitCount,
    required this.couponCode,
    required this.title,
    required this.payableLabel,
    required this.note,
  });

  /// Display estimate from the pricing engine. Never a chargeable amount.
  factory CartTotalsPanel.estimate({
    required CartTotals totals,
    String? couponCode,
    String title = 'Order summary',
    String? shippingNote,
    String? taxNote,
  }) =>
      CartTotalsPanel._(
        subtotalPaise: totals.subtotalPaise,
        slabSavingsPaise: totals.slabSavingsPaise,
        couponDiscountPaise: totals.couponDiscountPaise,
        shippingPaise: totals.shippingPaise,
        taxPaise: totals.taxPaise,
        roundingPaise: 0,
        payablePaise: totals.payableRoundedPaise,
        lineCount: totals.lineCount,
        unitCount: totals.unitCount,
        couponCode: couponCode,
        title: title,
        payableLabel: 'Estimated payable',
        note: _estimateNote(shippingNote, taxNote),
      );

  /// The server's answer, from the `orders.createOrder` receipt or an order document.
  factory CartTotalsPanel.authoritative({
    required OrderTotals totals,
    String? couponCode,
    String title = 'Confirmed bill',
    String? shippingNote,
  }) =>
      CartTotalsPanel._(
        subtotalPaise: totals.subtotalPaise,
        slabSavingsPaise: totals.slabDiscountPaise,
        couponDiscountPaise: totals.couponDiscountPaise,
        shippingPaise: totals.shippingPaise,
        taxPaise: totals.taxPaise,
        roundingPaise: totals.roundingPaise,
        payablePaise: totals.grandTotalPaise,
        lineCount: 0,
        unitCount: 0,
        couponCode: couponCode,
        title: title,
        payableLabel: 'Amount payable',
        note: <String>[
          'Confirmed by the order server when this order was created.',
          if (shippingNote != null && shippingNote.isNotEmpty) shippingNote,
        ].join(' '),
      );

  final int subtotalPaise;
  final int slabSavingsPaise;
  final int couponDiscountPaise;
  final int shippingPaise;
  final int taxPaise;
  final int roundingPaise;
  final int payablePaise;
  final int lineCount;
  final int unitCount;
  final String? couponCode;
  final String title;
  final String payableLabel;
  final String note;

  static String _estimateNote(String? shippingNote, String? taxNote) =>
      <String>[
        'Shipping and the final total are confirmed by the server at checkout — this estimate '
        'cannot be charged as-is.',
        if (shippingNote != null && shippingNote.isNotEmpty) shippingNote,
        if (taxNote != null && taxNote.isNotEmpty) taxNote,
      ].join(' ');

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final countNote = lineCount > 0
        ? '$lineCount line${lineCount == 1 ? '' : 's'} · $unitCount units'
        : null;

    return OmCard(
      // The summary is heard as one statement in one order — heading, each line, the payable figure,
      // then the caveat that it is an estimate. Left unmerged, a screen reader walks these loose
      // texts as separate stops and the customer can land on the total before the numbers that make
      // it up.
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: OmText(title, variant: OmTextVariant.h3)),
                if (countNote != null)
                  Padding(
                    padding: const EdgeInsets.only(left: OmSpacing.sm),
                    child: OmText(countNote, variant: OmTextVariant.caption),
                  ),
              ],
            ),
            const SizedBox(height: OmSpacing.md),
            _TotalRow(label: 'Merchandise total', paise: subtotalPaise),
            if (slabSavingsPaise > 0)
              _TotalRow(
                label: 'Quantity (slab) savings',
                paise: slabSavingsPaise,
                asNegative: true,
                tone: OmTone.success,
              ),
            if (couponDiscountPaise > 0)
              _TotalRow(
                label: couponCode == null
                    ? 'Coupon discount'
                    : 'Coupon “$couponCode”',
                paise: couponDiscountPaise,
                asNegative: true,
                tone: OmTone.success,
              ),
            _TotalRow(
              label: 'Shipping',
              paise: shippingPaise,
              absentLabel: shippingPaise == 0 ? 'Not decided yet' : null,
            ),
            if (taxPaise > 0) _TotalRow(label: 'GST', paise: taxPaise),
            if (roundingPaise != 0)
              _TotalRow(label: 'Round off', paise: roundingPaise),
            const OmDivider(space: OmSpacing.sm),
            Semantics(
              // Spoken as an amount, not as a glyph: `OmMoney.format` output reads as "rupee four
              // hundred eighty point zero zero" to some engines and as nothing to others, so the
              // paise figure travels with the label.
              excludeSemantics: true,
              label: '$payableLabel $payablePaise paise',
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(payableLabel, style: styles.bodyStrong),
                  ),
                  Text(
                    OmMoney.format(payablePaise),
                    style: styles.priceLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.verified_user_outlined,
                  size: 15,
                  color: styles.caption.color,
                ),
                const SizedBox(width: OmSpacing.xs),
                Expanded(child: Text(note, style: styles.caption)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.paise,
    this.asNegative = false,
    this.tone,
    this.absentLabel,
  });

  final String label;
  final int paise;

  /// Discount lines: the sign is drawn as a separate glyph so the rupee text itself always comes
  /// from `OmMoney.format` and no currency string is ever hand-assembled.
  final bool asNegative;
  final OmTone? tone;
  final String? absentLabel;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final isZero = paise == 0 && absentLabel != null;
    final color = switch (tone) {
      OmTone.success => OmColors.success,
      _ => styles.body.color,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: OmSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: styles.muted)),
          if (isZero)
            Text(absentLabel!, style: styles.caption)
          else ...<Widget>[
            if (asNegative)
              Text('−', style: styles.body.copyWith(color: OmColors.success)),
            if (asNegative) const SizedBox(width: 2),
            Text(
              OmMoney.format(paise.abs()),
              style: styles.body.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}
