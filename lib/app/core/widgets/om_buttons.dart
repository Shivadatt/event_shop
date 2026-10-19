import 'package:flutter/material.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

enum OmButtonVariant { primary, secondary, outline, ghost, danger }

enum OmButtonSize { small, medium, large }

/// The storefront's call-to-action. `primary` is gold-on-near-black and is reserved for the one
/// action that moves the buyer forward per screen — add to cart, checkout, save.
final class OmButton extends StatelessWidget {
  const OmButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = OmButtonVariant.primary,
    this.size = OmButtonSize.medium,
    this.icon,
    this.expanded = false,
    this.loading = false,
    this.busyLabel,
    this.numeric = false,
  });

  const OmButton.buy({
    super.key,
    required this.label,
    this.onPressed,
    this.size = OmButtonSize.medium,
    this.icon,
    this.expanded = false,
    this.loading = false,
    this.busyLabel,
    this.numeric = false,
  }) : variant = OmButtonVariant.primary;

  final String label;
  final VoidCallback? onPressed;
  final OmButtonVariant variant;
  final OmButtonSize size;
  final IconData? icon;
  final bool expanded;
  final bool loading;

  /// Replaces the label while in flight, so a spinner cannot be mistaken for a dead button.
  final String? busyLabel;

  /// Keeps the width fixed while the number changes, stopping the layout jumping on every
  /// quantity tap.
  final bool numeric;

  double get _height => switch (size) {
        OmButtonSize.small => 36,
        OmButtonSize.medium => 44,
        OmButtonSize.large => 52,
      };

  double get _fontSize => switch (size) {
        OmButtonSize.small => 13,
        OmButtonSize.medium => 15,
        OmButtonSize.large => 16,
      };

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null && !loading;

    final (Color bg, Color fg, Color border) = switch (variant) {
      OmButtonVariant.primary => (
          isDark ? OmColors.goldBright : OmColors.gold,
          OmColors.onGold,
          Colors.transparent
        ),
      OmButtonVariant.secondary => (
          isDark ? OmColors.surfaceElevated : OmColors.cream,
          isDark ? OmColors.textOnDark : OmColors.textPrimary,
          isDark ? OmColors.lineDark : OmColors.line
        ),
      OmButtonVariant.outline => (
          Colors.transparent,
          isDark ? OmColors.textOnDark : OmColors.textPrimary,
          isDark ? OmColors.gold : OmColors.gold
        ),
      OmButtonVariant.ghost => (
          Colors.transparent,
          isDark ? OmColors.goldBright : OmColors.gold,
          Colors.transparent
        ),
      OmButtonVariant.danger => (
          OmColors.danger,
          OmColors.paper,
          OmColors.danger
        ),
    };

    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (loading)
          SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: size == OmButtonSize.large ? 20 : 18, color: fg),
        if (loading || icon != null) const SizedBox(width: OmSpacing.sm),
        Text(
          loading ? (busyLabel ?? label) : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.bodyStrong.copyWith(
            fontSize: _fontSize,
            color: enabled ? fg : fg.withValues(alpha: 0.45),
          ),
        ),
      ],
    );

    final button = SizedBox(
      height: numeric ? _height : null,
      child: Material(
        color: bg,
        borderRadius: OmRadius.smAll,
        // InkWell hands the node a tap action but never the button role, so the storefront's
        // primary CTA used to be announced as plain text. OmIconButton below sets the same flag.
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: OmRadius.smAll,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size == OmButtonSize.small ? OmSpacing.md : OmSpacing.lg,
                vertical: OmSpacing.sm,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

    return Focus(
      canRequestFocus: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: OmRadius.smAll,
          border: Border.all(color: border.withValues(alpha: enabled ? 1 : 0.4)),
        ),
        child: button,
      ),
    );
  }
}

/// Compact icon-only control. The label is mandatory: an icon button without a semantics label
/// is unreachable by a screen reader.
final class OmIconButton extends StatelessWidget {
  const OmIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.filled = false,
    this.selected = false,
    this.size = 40,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = selected
        ? OmColors.gold
        : (isDark ? OmColors.textOnDark : OmColors.textPrimary);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: OmRadius.pillAll,
          child: Container(
            height: size,
            width: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (isDark ? OmColors.surfaceElevated : OmColors.cream)
                  : Colors.transparent,
              border: Border.all(
                color: selected ? OmColors.gold : Theme.of(context).dividerColor,
              ),
            ),
            child: Icon(icon, size: size * 0.45, color: color),
          ),
        ),
      ),
    );
  }
}
