// Responsive behaviour of the foundation layout widgets. These are the primitives every
// storefront and admin screen is built from (per CONTRACT), so pinning their breakpoint behaviour
// here means a column-count regression is caught in one place rather than in twelve screens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import '../support/om_harness.dart';

Widget _placeholder(int index) => Center(child: Text('item-$index', textDirection: TextDirection.ltr));

void main() {
  group('product grid column counts', () {
    Future<int> columnsAt(WidgetTester tester, double width) async {
      await pumpOm(
        tester,
        OmProductGrid(itemCount: 12, itemBuilder: (context, i) => _placeholder(i)),
        width: width,
        useScaffold: false,
      );
      return gridDelegate(tester).crossAxisCount;
    }

    test('mobile (360) gets 2 columns', (tester) async {
      expect(await columnsAt(tester, 360), 2);
      expectNoOverflow(tester);
    });

    test('tablet (700) gets 3 columns', (tester) async {
      expect(await columnsAt(tester, 700), 3);
    });

    test('laptop (1200) gets 4 columns', (tester) async {
      expect(await columnsAt(tester, 1200), 4);
    });

    test('desktop (1600) gets 5 columns', (tester) async {
      expect(await columnsAt(tester, 1600), 5);
    });

    test('an explicit columns override wins over the breakpoint', (tester) async {
      await pumpOm(
        tester,
        OmProductGrid(itemCount: 6, columns: 1, itemBuilder: (c, i) => _placeholder(i)),
        width: 1600,
        useScaffold: false,
      );
      expect(gridDelegate(tester).crossAxisCount, 1);
    });
  });

  group('context extension mapping', () {
    Future<OmDeviceClass> classAt(WidgetTester tester, double width) async {
      late OmDeviceClass found;
      await pumpOm(
        tester,
        Builder(builder: (context) {
          found = context.deviceClass;
          return const SizedBox.shrink();
        }),
        width: width,
      );
      return found;
    }

    test('breakpoints classify width exactly as the token thresholds', (tester) async {
      expect(await classAt(tester, 599), OmDeviceClass.mobile);
      expect(await classAt(tester, 600), OmDeviceClass.tablet);
      expect(await classAt(tester, 1023), OmDeviceClass.tablet);
      expect(await classAt(tester, 1024), OmDeviceClass.laptop);
      expect(await classAt(tester, 1439), OmDeviceClass.laptop);
      expect(await classAt(tester, 1440), OmDeviceClass.desktop);
    });

    test('omColumnCount tracks the device class', (tester) async {
      late int columns;
      await pumpOm(
        tester,
        Builder(builder: (context) {
          columns = context.omColumnCount;
          return const SizedBox.shrink();
        }),
        width: 1200,
      );
      expect(columns, 4);
    });
  });

  group('OmBreakpointBuilder', () {
    Future<String> slotAt(WidgetTester tester, double width) async {
      await pumpOm(
        tester,
        const OmBreakpointBuilder(
          mobile: Text('mobile', textDirection: TextDirection.ltr),
          tablet: Text('tablet', textDirection: TextDirection.ltr),
          laptop: Text('laptop', textDirection: TextDirection.ltr),
          desktop: Text('desktop', textDirection: TextDirection.ltr),
        ),
        width: width,
      );
      return width < 600
          ? 'mobile'
          : width < 1024
              ? 'tablet'
              : width < 1440
                  ? 'laptop'
                  : 'desktop';
    }

    test('renders exactly one slot for the current class', (tester) async {
      for (final width in <double>[360, 700, 1200, 1600]) {
        final expected = await slotAt(tester, width);
        expect(find.text(expected), findsOneWidget, reason: 'width $width');
        for (final other in <String>['mobile', 'tablet', 'laptop', 'desktop']) {
          if (other != expected) expect(find.text(other), findsNothing, reason: width.toString());
        }
      }
    });
  });

  group('OmCompactSwitch', () {
    test('shows the compact branch on mobile/tablet and the wide branch on laptop/desktop',
        (tester) async {
      await pumpOm(
        tester,
        const OmCompactSwitch(
          compact: Text('compact', textDirection: TextDirection.ltr),
          wide: Text('wide', textDirection: TextDirection.ltr),
        ),
        width: 400,
      );
      expect(find.text('compact'), findsOneWidget);
      expect(find.text('wide'), findsNothing);

      await pumpOm(
        tester,
        const OmCompactSwitch(
          compact: Text('compact', textDirection: TextDirection.ltr),
          wide: Text('wide', textDirection: TextDirection.ltr),
        ),
        width: 1280,
      );
      expect(find.text('wide'), findsOneWidget);
      expect(find.text('compact'), findsNothing);
    });
  });

  group('OmResponsiveTable', () {
    test('swaps the table for cards below minTableWidth (never forces horizontal scroll)',
        (tester) async {
      Widget subject() => const OmResponsiveTable(
            minTableWidth: 900,
            table: Text('table', textDirection: TextDirection.ltr),
            asCards: Text('cards', textDirection: TextDirection.ltr),
          );

      await pumpOm(tester, subject(), width: 800, useScaffold: false);
      expect(find.text('cards'), findsOneWidget);
      expect(find.text('table'), findsNothing);

      await pumpOm(tester, subject(), width: 1200, useScaffold: false);
      expect(find.text('table'), findsOneWidget);
      expect(find.text('cards'), findsNothing);
    });
  });

  group('OmContentWidth', () {
    test('caps the body so a 4K viewport shows a centred column, not 12 stretched cards',
        (tester) async {
      final probe = Container(key: const Key('probe'), height: 10, color: Colors.white);
      await pumpOm(
        tester,
        OmContentWidth(maxWidth: 1200, child: probe),
        width: 2560,
        useScaffold: false,
      );
      final width = tester.getSize(find.byKey(const Key('probe'))).width;
      expect(width, lessThanOrEqualTo(1200));
      expectNoOverflow(tester);
    });

    test('does not stretch a child that is narrower than the cap', (tester) async {
      await pumpOm(
        tester,
        OmContentWidth(
          maxWidth: 1440,
          child: const SizedBox(key: Key('fixed'), width: 300, height: 10),
        ),
        width: 1440,
        alignment: Alignment.center,
      );
      expect(tester.getSize(find.byKey(const Key('fixed'))).width, 300);
    });
  });

  group('grid at text scale extremes (main.dart clamps 0.9-1.6)', () {
    for (final scale in <double>[0.9, 1.3, 1.6]) {
      test('mobile product grid does not overflow at textScale $scale', (tester) async {
        await pumpOm(
          tester,
          OmProductGrid(
            itemCount: 6,
            itemBuilder: (c, i) => const Padding(
              padding: EdgeInsets.all(4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Latex Balloon Pack ₹1,234', textDirection: TextDirection.ltr),
              ),
            ),
          ),
          width: 360,
          textScale: scale,
        );
        expectNoOverflow(tester);
      });
    }
  });
}
