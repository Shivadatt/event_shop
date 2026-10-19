/// WCAG 2.1 contrast maths, computed in the test suite instead of asserted in a document.
///
/// Ratio = (L_lighter + 0.05) / (L_darker + 0.05) where L is the sRGB relative luminance with each
/// channel linearised. Thresholds: 4.5:1 for normal body text, 3:1 for large text (>=18pt regular /
/// >=14pt bold) and for non-text UI such as icons, focus rings and input borders.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

abstract final class OmContrast {
  OmContrast._();

  static double luminance(Color color) {
    final channels = <double>[color.r, color.g, color.b];
    final linear = channels.map(_linearize).toList(growable: false);
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  }

  static double ratio(Color foreground, Color background) {
    final a = luminance(foreground);
    final b = luminance(background);
    final lighter = math.max(a, b);
    final darker = math.min(a, b);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// A channel at or below the sRGB knee is scaled, otherwise it is gamma-expanded. Uses the exact
  /// 0.04045 / 12.92 / 2.4 constants from the specification so the numbers here match what any
  /// auditor's tool reports.
  static double _linearize(double channel) {
    final srgb = channel < 0 ? 0.0 : (channel > 1 ? 1.0 : channel);
    return srgb <= 0.04045 ? srgb / 12.92 : math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Passes AA for normal body text.
  static bool meetsBodyText(double value) => value >= 4.5;

  /// Passes AA for large text (>=24px regular / >=18.66px bold at Flutter's 96dpi scale) or UI.
  static bool meetsLargeTextOrUi(double value) => value >= 3.0;

  /// AAA for body text.
  static bool meetsEnhanced(double value) => value >= 7.0;

  /// A one-line, sortable description of a measurement, for the QA report table.
  static String describe(String pair, double value, {bool large = false}) {
    final required = large ? 3.0 : 4.5;
    final verdict = value >= required ? 'PASS' : 'FAIL';
    return '${pair.padRight(38)} ${value.toStringAsFixed(2)}:1  (needs $required:1)  $verdict';
  }
}
