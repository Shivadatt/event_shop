import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:om_events/app/theme/om_tokens.dart';

/// Display serif for brand moments, a neutral sans everywhere else. Product data — price, SKU,
/// quantity — always uses the sans, because a decorative face costs legibility exactly where
/// legibility earns money.
abstract final class OmFontFamilies {
  static const String displayFamily = 'Cormorant Garamond';
  static const String bodyFamily = 'Inter';

  /// Loaded over the network by google_fonts on first use. If that fetch fails the engine falls
  /// back to the platform font, so a blocked CDN degrades typography and nothing else.
  static TextStyle serif(double size, {FontWeight weight = FontWeight.w600, Color? color}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: weight,
        height: 1.12,
        letterSpacing: -0.2,
        color: color,
      );

  static TextStyle sans(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: 1.45,
        color: color,
      );
}

/// Registered as a `ThemeExtension` so `Theme.of(context).extension<OmTextStyles>()` is the only
/// way screens reach type — no widget invents its own font size.
@immutable
final class OmTextStyles extends ThemeExtension<OmTextStyles> {
  const OmTextStyles({
    required this.display,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.lead,
    required this.body,
    required this.bodyStrong,
    required this.caption,
    required this.label,
    required this.price,
    required this.priceLarge,
    required this.muted,
  });

  final TextStyle display;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle lead;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle caption;
  final TextStyle label;
  final TextStyle price;
  final TextStyle priceLarge;
  final TextStyle muted;

  static OmTextStyles forBrightness(Brightness brightness) {
    final onDark = brightness == Brightness.dark;
    final primary = onDark ? OmColors.textOnDark : OmColors.textPrimary;
    final mutedColor = onDark ? OmColors.textMutedOnDark : OmColors.textMuted;

    return OmTextStyles(
      display: OmFontFamilies.serif(56, color: primary),
      h1: OmFontFamilies.serif(40, color: primary),
      h2: OmFontFamilies.serif(30, color: primary),
      h3: OmFontFamilies.sans(20, weight: FontWeight.w600, color: primary),
      lead: OmFontFamilies.sans(17, color: primary),
      body: OmFontFamilies.sans(15, color: primary),
      bodyStrong: OmFontFamilies.sans(15, weight: FontWeight.w600, color: primary),
      caption: OmFontFamilies.sans(12.5, color: mutedColor),
      label: OmFontFamilies.sans(
        12,
        weight: FontWeight.w600,
        color: onDark ? OmColors.goldBright : OmColors.gold,
      ),
      price: OmFontFamilies.sans(16, weight: FontWeight.w700, color: primary),
      priceLarge: OmFontFamilies.sans(24, weight: FontWeight.w700, color: primary),
      muted: OmFontFamilies.sans(14, color: mutedColor),
    );
  }

  @override
  OmTextStyles copyWith({
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? lead,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? caption,
    TextStyle? label,
    TextStyle? price,
    TextStyle? priceLarge,
    TextStyle? muted,
  }) =>
      OmTextStyles(
        display: display ?? this.display,
        h1: h1 ?? this.h1,
        h2: h2 ?? this.h2,
        h3: h3 ?? this.h3,
        lead: lead ?? this.lead,
        body: body ?? this.body,
        bodyStrong: bodyStrong ?? this.bodyStrong,
        caption: caption ?? this.caption,
        label: label ?? this.label,
        price: price ?? this.price,
        priceLarge: priceLarge ?? this.priceLarge,
        muted: muted ?? this.muted,
      );

  @override
  OmTextStyles lerp(covariant OmTextStyles? other, double t) {
    if (other == null) return this;
    return OmTextStyles(
      display: TextStyle.lerp(display, other.display, t)!,
      h1: TextStyle.lerp(h1, other.h1, t)!,
      h2: TextStyle.lerp(h2, other.h2, t)!,
      h3: TextStyle.lerp(h3, other.h3, t)!,
      lead: TextStyle.lerp(lead, other.lead, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      price: TextStyle.lerp(price, other.price, t)!,
      priceLarge: TextStyle.lerp(priceLarge, other.priceLarge, t)!,
      muted: TextStyle.lerp(muted, other.muted, t)!,
    );
  }
}

extension OmTypographyOnContext on BuildContext {
  /// Throws in debug if a screen builds outside `OmTheme`. Failing loudly beats silently
  /// rendering default Material type.
  OmTextStyles get omText =>
      Theme.of(this).extension<OmTextStyles>() ?? OmTextStyles.forBrightness(
          Theme.of(this).brightness);
}

enum OmTextVariant {
  display,
  h1,
  h2,
  h3,
  lead,
  body,
  bodyStrong,
  caption,
  label,
  price,
  priceLarge,
  muted;

  TextStyle resolve(OmTextStyles styles) => switch (this) {
        OmTextVariant.display => styles.display,
        OmTextVariant.h1 => styles.h1,
        OmTextVariant.h2 => styles.h2,
        OmTextVariant.h3 => styles.h3,
        OmTextVariant.lead => styles.lead,
        OmTextVariant.body => styles.body,
        OmTextVariant.bodyStrong => styles.bodyStrong,
        OmTextVariant.caption => styles.caption,
        OmTextVariant.label => styles.label,
        OmTextVariant.price => styles.price,
        OmTextVariant.priceLarge => styles.priceLarge,
        OmTextVariant.muted => styles.muted,
      };
}

/// The one text widget screens should use, so every label in the app is traceable to a token.
final class OmText extends StatelessWidget {
  const OmText(
    this.data, {
    super.key,
    this.variant = OmTextVariant.body,
    this.align,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.color,
    this.softWrap = true,
    this.selectable = false,
  });

  final String data;
  final OmTextVariant variant;
  final TextAlign? align;
  final int? maxLines;
  final TextOverflow overflow;
  final Color? color;
  final bool softWrap;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final style = variant.resolve(context.omText).copyWith(color: color);
    final text = Text(
      data,
      textAlign: align,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      style: style,
    );
    return selectable ? SelectionArea(child: text) : text;
  }
}
