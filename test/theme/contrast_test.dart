// WCAG contrast of the actual brand tokens.
//
// The contract requires >= 4.5:1 for body text and >= 3:1 for large text and non-text UI (icons,
// focus rings, input borders). These tests measure the real OmColors values in both themes, so the
// accessibility claim is arithmetic, not an assertion in a doc comment.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import '../support/om_contrast.dart';

void _expectBody(String label, Color fg, Color bg) {
  final ratio = OmContrast.ratio(fg, bg);
  expect(ratio, greaterThanOrEqualTo(4.5),
      reason: '$label measures ${ratio.toStringAsFixed(2)}:1, needs 4.5:1 for body text');
}

void _expectLargeOrUi(String label, Color fg, Color bg) {
  final ratio = OmContrast.ratio(fg, bg);
  expect(ratio, greaterThanOrEqualTo(3.0),
      reason: '$label measures ${ratio.toStringAsFixed(2)}:1, needs 3:1 for large text/UI');
}

void main() {
  group('dark merchandising surfaces', () {
    test('primary and muted text clear 4.5:1 on every dark background', () {
      for (final bg in [OmColors.black, OmColors.surfaceDark, OmColors.surfaceElevated]) {
        _expectBody('textOnDark on $bg', OmColors.textOnDark, bg);
        _expectBody('textMutedOnDark on $bg', OmColors.textMutedOnDark, bg);
      }
    });

    test('gold reads as a foreground accent on black, not a wash', () {
      _expectBody('gold on black', OmColors.gold, OmColors.black);
      _expectBody('goldBright on black', OmColors.goldBright, OmColors.black);
    });

    test('the loading sub-label (goldSoft) meets the large-text bar on dark', () {
      _expectLargeOrUi('goldSoft on surfaceDark', OmColors.goldSoft, OmColors.surfaceDark);
    });

    test('button labels (onGold) clear 4.5:1 on the gold fills', () {
      _expectBody('onGold on gold', OmColors.onGold, OmColors.gold);
      _expectBody('onGold on goldBright', OmColors.onGold, OmColors.goldBright);
    });
  });

  group('light data surfaces', () {
    test('primary text clears 4.5:1 on paper and cream', () {
      _expectBody('textPrimary on paper', OmColors.textPrimary, OmColors.paper);
      _expectBody('textPrimary on cream', OmColors.textPrimary, OmColors.cream);
    });

    test('muted text clears 4.5:1 on paper', () {
      _expectBody('textMuted on paper', OmColors.textMuted, OmColors.paper);
      _expectBody('textMuted on cream', OmColors.textMuted, OmColors.cream);
    });

    test('semantic colours clear the 3:1 bar as badges/icons on paper', () {
      _expectLargeOrUi('success on paper', OmColors.success, OmColors.paper);
      _expectLargeOrUi('danger on paper', OmColors.danger, OmColors.paper);
      _expectLargeOrUi('warning on paper', OmColors.warning, OmColors.paper);
      _expectLargeOrUi('info on paper', OmColors.info, OmColors.paper);
    });
  });

  // Documented contrast findings — real, measured, deliberately below the ideal bar. They are pinned
  // as `lessThan` so a future change to the palette that fixes them flips these red and forces the
  // QA table to be updated. None of these are body text: gold is an accent on light, and the
  // semantic colours are used as badge/icon fills where the 3:1 UI rule applies.
  group('known contrast findings (recorded, not asserted compliant)', () {
    test('gold is NOT usable as small body text on light surfaces (P2 — theme owner)', () {
      final ratio = OmContrast.ratio(OmColors.gold, OmColors.paper);
      expect(ratio, lessThan(4.5),
          reason: 'measured so the report notes the exact shortfall');
      // The theme only uses gold on light surfaces for `label` (12px) eyebrow text and fills,
      // where the 3:1 non-text/large rule applies — and even that fails here:
      expect(ratio, lessThan(3.0),
          reason: 'NEEDS OWNER: label variant in om_typography.dart paints gold on light bg');
    });

    test('success on pure white sits just under the body-text bar (use as badge, not prose)', () {
      final ratio = OmContrast.ratio(OmColors.success, OmColors.paper);
      expect(ratio, inInclusiveRange(3.0, 4.5));
    });

    test('warning on white is a badge colour, not body text', () {
      final ratio = OmContrast.ratio(OmColors.warning, OmColors.paper);
      expect(ratio, inInclusiveRange(3.0, 4.5));
    });
  });

  group('OmContrast math itself', () {
    test('black/white is the 21:1 ceiling', () {
      expect(OmContrast.ratio(Colors.black, Colors.white), closeTo(21.0, 0.05));
    });

    test('identical colours are 1:1', () {
      expect(OmContrast.ratio(OmColors.gold, OmColors.gold), closeTo(1.0, 0.001));
    });

    test('ratio is symmetric regardless of argument order', () {
      final a = OmContrast.ratio(OmColors.textOnDark, OmColors.black);
      final b = OmContrast.ratio(OmColors.black, OmColors.textOnDark);
      expect(a, closeTo(b, 0.0001));
    });
  });
}
