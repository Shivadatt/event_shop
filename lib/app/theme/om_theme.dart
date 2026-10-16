import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

/// Two themes, one brand.
///
/// `dark` is the merchandising surface (home, category, product hero, footer): black + gold.
/// `light` is where data lives: forms, tables, admin screens, and product detail bodies, where
/// black-on-cream reads faster than gold-on-black.
abstract final class OmTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final text = OmTextStyles.forBrightness(brightness);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? OmColors.goldBright : OmColors.gold,
      onPrimary: OmColors.onGold,
      secondary: isDark ? OmColors.goldSoft : OmColors.gold,
      onSecondary: OmColors.onGold,
      surface: isDark ? OmColors.surfaceDark : OmColors.paper,
      onSurface: isDark ? OmColors.textOnDark : OmColors.textPrimary,
      surfaceContainerHighest:
          isDark ? OmColors.surfaceElevated : OmColors.cream,
      onSurfaceVariant: isDark ? OmColors.textMutedOnDark : OmColors.textMuted,
      outline: isDark ? OmColors.lineDark : OmColors.line,
      outlineVariant: isDark ? OmColors.lineDark : OmColors.line,
      error: isDark ? OmColors.goldSoft : OmColors.danger,
      onError: isDark ? OmColors.onGold : OmColors.paper,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? OmColors.black : OmColors.cream,
      canvasColor: isDark ? OmColors.black : OmColors.paper,
      dividerColor: isDark ? OmColors.lineDark : OmColors.line,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[text],
      textTheme: TextTheme(
        displayLarge: text.display,
        displayMedium: text.h1,
        headlineSmall: text.h2,
        titleLarge: text.h3,
        titleMedium: text.bodyStrong,
        bodyLarge: text.lead,
        bodyMedium: text.body,
        bodySmall: text.caption,
        labelLarge: text.label,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? OmColors.black : OmColors.paper,
        foregroundColor: isDark ? OmColors.textOnDark : OmColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: isDark ? 0 : 1,
        centerTitle: false,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: text.h3,
      ),
      cardTheme: CardThemeData(
        color: isDark ? OmColors.surfaceDark : OmColors.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: OmRadius.mdAll,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? OmColors.goldBright : OmColors.gold,
          foregroundColor: OmColors.onGold,
          disabledBackgroundColor: isDark ? OmColors.lineDark : OmColors.line,
          disabledForegroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(0, OmBreakpoints.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: OmSpacing.lg),
          textStyle: text.bodyStrong,
          shape: RoundedRectangleBorder(borderRadius: OmRadius.smAll),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? OmColors.textOnDark : OmColors.textPrimary,
          minimumSize: const Size(0, OmBreakpoints.minTouchTarget),
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: OmSpacing.lg),
          textStyle: text.bodyStrong,
          shape: RoundedRectangleBorder(borderRadius: OmRadius.smAll),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? OmColors.goldBright : OmColors.gold,
          textStyle: text.bodyStrong,
          minimumSize: const Size(0, OmBreakpoints.minTouchTarget),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: isDark ? OmColors.textOnDark : OmColors.textPrimary,
          minimumSize: const Size(
            OmBreakpoints.minTouchTarget,
            OmBreakpoints.minTouchTarget,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? OmColors.surfaceElevated : OmColors.paper,
        hintStyle: text.caption,
        labelStyle: text.caption,
        helperStyle: text.caption,
        errorStyle: text.caption.copyWith(color: OmColors.danger),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: OmSpacing.md,
          vertical: OmSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: OmRadius.smAll,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: OmRadius.smAll,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: OmRadius.smAll,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: OmRadius.smAll,
          borderSide: const BorderSide(color: OmColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: OmRadius.smAll,
          borderSide: const BorderSide(color: OmColors.danger, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? OmColors.surfaceElevated : OmColors.cream,
        selectedColor: isDark ? OmColors.gold : OmColors.goldSoft,
        side: BorderSide(color: scheme.outline),
        labelStyle: text.caption,
        shape: RoundedRectangleBorder(borderRadius: OmRadius.pillAll),
        padding: const EdgeInsets.symmetric(horizontal: OmSpacing.sm, vertical: OmSpacing.xs),
      ),
      sliderTheme: const SliderThemeData(activeTrackColor: OmColors.gold),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? OmColors.gold
              : (isDark ? OmColors.textMutedOnDark : OmColors.paper),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? OmColors.goldSoft
              : (isDark ? OmColors.lineDark : OmColors.line),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: OmColors.gold,
        linearTrackColor: OmColors.line,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? OmColors.surfaceElevated : OmColors.textPrimary,
        contentTextStyle: text.body.copyWith(color: OmColors.textOnDark),
        actionTextColor: OmColors.goldBright,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: OmRadius.smAll),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? OmColors.surfaceDark : OmColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: OmRadius.lgAll),
        titleTextStyle: text.h3,
        contentTextStyle: text.body,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? OmColors.surfaceDark : OmColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(OmRadius.lg)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? OmColors.surfaceElevated : OmColors.textPrimary,
          borderRadius: OmRadius.smAll,
        ),
        textStyle: text.caption.copyWith(color: OmColors.textOnDark),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          (isDark ? OmColors.gold : OmColors.textMuted).withValues(alpha: 0.35),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? OmColors.surfaceDark : OmColors.paper,
        indicatorColor: (isDark ? OmColors.gold : OmColors.goldSoft)
            .withValues(alpha: 0.22),
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(text.caption),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isDark ? OmColors.surfaceDark : OmColors.paper,
        indicatorColor: isDark ? OmColors.gold : OmColors.goldSoft,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? OmColors.goldBright : OmColors.gold,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: isDark ? OmColors.goldBright : OmColors.gold,
        labelStyle: text.bodyStrong,
        unselectedLabelStyle: text.body,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyStrong,
        subtitleTextStyle: text.caption,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: OmSpacing.md, vertical: OmSpacing.xs),
      ),
    );
  }
}
