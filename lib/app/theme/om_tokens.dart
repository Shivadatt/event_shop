import 'package:flutter/material.dart';

/// Premium black-and-gold brand values. Hex literals belong here and nowhere else: a component
/// that types a colour directly is a defect, because the theme cannot be changed in one place.
abstract final class OmColors {
  static const Color black = Color(0xFF0B0B0C);
  static const Color surfaceDark = Color(0xFF141416);
  static const Color surfaceElevated = Color(0xFF1D1D21);
  static const Color gold = Color(0xFFC9A227);
  static const Color goldBright = Color(0xFFE5C158);
  static const Color goldSoft = Color(0xFFF2E2B0);
  static const Color cream = Color(0xFFFBF8F1);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE3E0D8);
  static const Color lineDark = Color(0xFF2A2A2F);
  static const Color textPrimary = Color(0xFF16151A);
  static const Color textMuted = Color(0xFF6B6A72);
  static const Color textOnDark = Color(0xFFF5F3EE);
  static const Color textMutedOnDark = Color(0xFFA9A6B0);
  static const Color success = Color(0xFF1F8A4C);
  static const Color warning = Color(0xFFC4761A);
  static const Color danger = Color(0xFFB42318);
  static const Color info = Color(0xFF2C6E9B);

  /// Gold is a foreground accent on dark and a background only under text-dark-on-gold, so it
  /// never becomes a low-contrast wash behind body copy.
  static const Color onGold = Color(0xFF1A1500);

  static const LinearGradient goldSheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[gold, goldBright],
  );

  static const RadialGradient heroGlow = RadialGradient(
    center: Alignment(0, -0.6),
    radius: 1.1,
    colors: <Color>[Color(0xFF23232A), black],
  );
}

abstract final class OmSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double pageMaxWidth = 1440;

  static EdgeInsets get page =>
      const EdgeInsets.symmetric(horizontal: md, vertical: lg);

  static EdgeInsets get card => const EdgeInsets.all(md);

  static const EdgeInsets listRow = EdgeInsets.symmetric(horizontal: md, vertical: sm);
}

abstract final class OmRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

/// Breakpoints. The names describe the *device class*, not the upper bound, and thresholds are
/// inclusive at the lower edge — read the helpers, do not infer them from the name.
abstract final class OmBreakpoints {
  static const double mobile = 0;
  static const double tablet = 600;
  static const double laptop = 1024;
  static const double desktop = 1440;

  static const double minTouchTarget = 44;
}

enum OmDeviceClass {
  mobile,
  tablet,
  laptop,
  desktop;

  bool get isCompact => this == mobile || this == tablet;
  bool get isWide => this == laptop || this == desktop;
}

extension OmDeviceClassOnContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  OmDeviceClass get deviceClass {
    final width = screenWidth;
    if (width >= OmBreakpoints.desktop) return OmDeviceClass.desktop;
    if (width >= OmBreakpoints.laptop) return OmDeviceClass.laptop;
    if (width >= OmBreakpoints.tablet) return OmDeviceClass.tablet;
    return OmDeviceClass.mobile;
  }

  bool get isMobile => deviceClass == OmDeviceClass.mobile;
  bool get isTablet => deviceClass == OmDeviceClass.tablet;
  bool get isLaptop => deviceClass == OmDeviceClass.laptop;
  bool get isDesktop => deviceClass == OmDeviceClass.desktop;
  bool get isCompactLayout => deviceClass.isCompact;
  bool get isWideLayout => deviceClass.isWide;

  /// Product grid columns: 2 / 3 / 4 / 5 across mobile → desktop.
  int get omColumnCount => switch (deviceClass) {
        OmDeviceClass.mobile => 2,
        OmDeviceClass.tablet => 3,
        OmDeviceClass.laptop => 4,
        OmDeviceClass.desktop => 5,
      };

  double get omGridAspectRatio => deviceClass == OmDeviceClass.mobile ? 0.72 : 0.68;

  /// Content is capped so a 4K monitor gets a centred column, not 12 stretched cards.
  double get omContentMaxWidth => OmSpacing.pageMaxWidth;

  bool get prefersDarkSurfaces => MediaQuery.platformBrightnessOf(this) == Brightness.dark;
}
