import 'package:flutter/material.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

/// The card every product, category and admin panel sits in.
final class OmCard extends StatelessWidget {
  const OmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OmSpacing.md),
    this.onTap,
    this.highlight = false,
    this.borderRadius,
    this.elevated = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  /// Gold edge for the recommended plan / selected option.
  final bool highlight;
  final bool elevated;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? OmRadius.mdAll;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: elevated
            ? (isDark ? OmColors.surfaceElevated : OmColors.paper)
            : (isDark ? OmColors.surfaceDark : OmColors.paper),
        borderRadius: radius,
        border: Border.all(
          color: borderColor ??
              (highlight ? OmColors.gold : theme.dividerColor),
          width: highlight ? 1.6 : 1,
        ),
        boxShadow: elevated || highlight
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Section heading with the brand's eyebrow/label + display pairing.
final class OmSectionHeader extends StatelessWidget {
  const OmSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.action,
    this.onActionTap,
    this.align = TextAlign.start,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final String? action;
  final VoidCallback? onActionTap;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Column(
      crossAxisAlignment: switch (align) {
        TextAlign.center => CrossAxisAlignment.center,
        _ => CrossAxisAlignment.start,
      },
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(
            eyebrow!.toUpperCase(),
            textAlign: align,
            style: styles.label,
          ),
          const SizedBox(height: OmSpacing.xs),
        ],
        Text(title, textAlign: align, style: styles.h2),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: OmSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(subtitle!, textAlign: align, style: styles.muted),
          ),
        ],
        if (action != null && onActionTap != null) ...<Widget>[
          const SizedBox(height: OmSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onActionTap,
              child: Text('$action →', style: styles.bodyStrong),
            ),
          ),
        ],
      ],
    );
  }
}

enum OmTone { neutral, gold, success, warning, danger, info }

/// Status pill: order state, stock state, "wholesale", "verified purchase".
/// Never the *only* signal — the label text always states the condition, so colourblind users
/// are not guessing.
final class OmBadge extends StatelessWidget {
  const OmBadge({
    super.key,
    required this.label,
    this.tone = OmTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final OmTone tone;
  final IconData? icon;
  final bool dense;

  (Color, Color) get _palette => switch (tone) {
      OmTone.neutral => (OmColors.textMuted, OmColors.cream),
      OmTone.gold => (OmColors.onGold, OmColors.goldBright),
      OmTone.success => (OmColors.paper, OmColors.success),
      OmTone.warning => (OmColors.paper, OmColors.warning),
      OmTone.danger => (OmColors.paper, OmColors.danger),
      OmTone.info => (OmColors.paper, OmColors.info),
    };

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = _palette;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? OmSpacing.sm : OmSpacing.md * 0.75,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: OmRadius.pillAll,
        border: Border.all(color: fg.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 12 : 14, color: fg),
            const SizedBox(width: OmSpacing.xs + 2),
          ],
          Text(
            label,
            style: context.omText.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable filter pill used by the catalogue sidebar and chips row.
final class OmFilterChip extends StatelessWidget {
  const OmFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.trailingCount,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? trailingCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label filter ${selected ? 'on' : 'off'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: OmRadius.pillAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: OmSpacing.md,
            vertical: OmSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? OmColors.gold : OmColors.goldSoft)
                : Colors.transparent,
            borderRadius: OmRadius.pillAll,
            border: Border.all(
              color: selected ? OmColors.gold : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: context.omText.caption.copyWith(
                  color: selected
                      ? OmColors.onGold
                      : (isDark ? OmColors.textOnDark : OmColors.textPrimary),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (trailingCount != null) ...<Widget>[
                const SizedBox(width: OmSpacing.xs),
                Text('($trailingCount)', style: context.omText.caption),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class OmDivider extends StatelessWidget {
  const OmDivider({super.key, this.indent = 0, this.space = OmSpacing.lg});

  final double indent;
  final double space;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: space, horizontal: indent),
        child: Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor),
      );
}

/// Thin gold rule used under display headings.
final class OmGoldRule extends StatelessWidget {
  const OmGoldRule({super.key, this.width = 72, this.thickness = 2});

  final double width;
  final double thickness;

  @override
  Widget build(BuildContext context) => Container(
        height: thickness,
        width: width,
        decoration: const BoxDecoration(
          gradient: OmColors.goldSheen,
          borderRadius: BorderRadius.all(Radius.circular(OmRadius.pill)),
        ),
      );
}
