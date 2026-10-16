import 'package:flutter/material.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';

/// Renders an integer-paise value. Any widget that formats currency goes through this so the
/// thousands separators, the ₹ glyph and the "hide .00" rule stay identical site-wide.
final class OmMoneyText extends StatelessWidget {
  const OmMoneyText(this.paise, {super.key, this.style, this.decimals = true});

  final int paise;
  final TextStyle? style;

  /// Cards drop paise for a tighter grid; invoices and totals never do.
  final bool decimals;

  @override
  Widget build(BuildContext context) => Text(
        decimals ? OmMoney.format(paise) : OmMoney.formatRupees(paise),
        style: style ?? context.omText.price,
      );
}

/// One price line for a card or a PDP: what this quantity costs now, what it would have cost,
/// and the band that produced it.
final class OmPriceTag extends StatelessWidget {
  const OmPriceTag({
    super.key,
    required this.resolution,
    this.compact = false,
    this.showStrikeThrough = true,
    this.alignment = CrossAxisAlignment.start,
  });

  final PriceResolution resolution;
  final bool compact;
  final bool showStrikeThrough;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final discounted = resolution.hasSlabDiscount;

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            OmMoneyText(
              resolution.lineTotalPaise,
              style: compact ? styles.price : styles.priceLarge,
              decimals: false,
            ),
            if (!compact && resolution.qty > 1) ...<Widget>[
              const SizedBox(width: OmSpacing.xs),
              Text(
                '· ${OmMoney.format(resolution.unitPricePaise)} each',
                style: styles.caption,
              ),
            ],
          ],
        ),
        if (discounted && showStrikeThrough)
          Text(
            OmMoney.format(resolution.baseUnitPricePaise * resolution.qty),
            style: styles.caption.copyWith(
              decoration: TextDecoration.lineThrough,
              decorationColor: OmColors.textMuted,
            ),
          ),
        if (discounted)
          Padding(
            padding: const EdgeInsets.only(top: OmSpacing.xs),
            child: OmBadge(
              dense: true,
              tone: OmTone.success,
              label: 'You save ${OmMoney.format(resolution.savedPaise)}',
            ),
          ),
      ],
    );
  }
}

/// The slab table. Read on the PDP, cart line and admin product form — one widget, so a buyer
/// can never see two different promises about the same quantity band.
final class OmSlabTable extends StatelessWidget {
  const OmSlabTable({
    super.key,
    required this.slabs,
    required this.basePricePaise,
    this.currentQty = 1,
    this.title = 'Quantity discounts',
  });

  final List<PriceSlab> slabs;
  final int basePricePaise;
  final int currentQty;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (slabs.length < 2) return const SizedBox.shrink();
    final styles = context.omText;
    final sorted = [...slabs]..sort((a, b) => a.minQty.compareTo(b.minQty));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: styles.bodyStrong),
        const SizedBox(height: OmSpacing.sm),
        ...sorted.map((slab) {
          final active = slab.contains(currentQty);
          final range = slab.maxQty == null
              ? '${slab.minQty}+'
              : slab.minQty == slab.maxQty
                  ? '${slab.minQty}'
                  : '${slab.minQty}–${slab.maxQty}';
          final off = OmMoney.discountPercent(basePricePaise, slab.unitPricePaise);
          return Container(
            margin: const EdgeInsets.only(bottom: OmSpacing.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: OmSpacing.sm,
              vertical: OmSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: active
                  ? OmColors.goldSoft.withValues(alpha: 0.35)
                  : Colors.transparent,
              borderRadius: OmRadius.smAll,
              border: Border.all(
                color: active ? OmColors.gold : Theme.of(context).dividerColor,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '$range units',
                    style: styles.body.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                if (off > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: OmSpacing.sm),
                    child: OmBadge(dense: true, tone: OmTone.gold, label: '$off% off'),
                  ),
                Text(OmMoney.format(slab.unitPricePaise), style: styles.price),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// "Add N more to reach ₹X" — the nudge that makes a slab table actionable instead of decorative.
final class OmNextSlabHint extends StatelessWidget {
  const OmNextSlabHint({super.key, required this.resolution});

  final PriceResolution resolution;

  @override
  Widget build(BuildContext context) {
    final next = resolution.nextSlab;
    if (next == null || resolution.unitsToNextSlab <= 0) return const SizedBox.shrink();
    final styles = context.omText;
    return Row(
      children: <Widget>[
        const Icon(Icons.local_offer_outlined, size: 15, color: OmColors.gold),
        const SizedBox(width: OmSpacing.xs),
        Expanded(
          child: Text(
            'Add ${resolution.unitsToNextSlab} more '
            '${resolution.qty > 1 ? 'units ' : ''}'
            'to pay ${OmMoney.format(next.unitPricePaise)} each',
            style: styles.caption.copyWith(color: OmColors.gold),
          ),
        ),
      ],
    );
  }
}
