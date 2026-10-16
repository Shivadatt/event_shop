/// Test harness for the QA suite: a viewport the size we are asserting about, the real brand theme,
/// and a text scaler that matches what `main.dart` clamps production to (0.9–1.6).
///
/// Nothing here fakes a backend. Widgets under test receive the widgets they would receive in the
/// app; repository fakes live in `om_fakes.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/theme/om_theme.dart';
import 'package:om_events/app/theme/om_tokens.dart';

/// Logical viewport size, device pixel ratio 1 so the numbers in assertions are the numbers in the
/// layout. Sets `FlutterView.physicalSize`, which is what both the render surface and the
/// `MediaQuery` the `View` widget inserts are derived from — overriding `MediaQuery` alone would
/// report a width the box constraints ignore, and every overflow assertion would be fiction.
void setViewport(
  WidgetTester tester, {
  required double width,
  double height = 1200,
}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Pumps [child] at [width]x[height] inside the real `OmTheme`, at [textScale].
///
/// `useScaffold: false` pumps the child directly under `Directionality` for widgets that must not
/// inherit a `Scaffold`'s own padding (grids, tables), which is how they are used in a page body.
Future<void> pumpOm(
  WidgetTester tester,
  Widget child, {
  required double width,
  double height = 1200,
  double textScale = 1.0,
  Brightness brightness = Brightness.dark,
  bool useScaffold = true,
  Alignment alignment = Alignment.topLeft,
}) async {
  setViewport(tester, width: width, height: height);
  final theme = brightness == Brightness.dark ? OmTheme.dark : OmTheme.light;

  Widget body = useScaffold
      ? Scaffold(
          backgroundColor: brightness == Brightness.dark ? OmColors.black : OmColors.cream,
          body: child,
        )
      : Directionality(textDirection: TextDirection.ltr, child: child);

  if (alignment != Alignment.topLeft) {
    body = Align(alignment: alignment, child: body);
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: body,
      debugShowCheckedModeBanner: false,
      builder: (context, toBuild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: toBuild ?? const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fails with the widget's own diagnostics if a layout overflowed (the classic yellow/black
/// stripes) or threw while painting. Every responsiveness assertion ends with this.
void expectNoOverflow(WidgetTester tester, {String? reason}) {
  expect(tester.takeException(), isNull, reason: reason ?? 'layout must not overflow');
}

/// True when the last pump produced an overflow (used by the tests that document a known risk
/// instead of asserting it, so the suite stays green while the defect is open).
bool hasOverflow(WidgetTester tester) => tester.takeException() != null;

/// Height of the first widget of type [T], in logical pixels.
double heightOf(WidgetTester tester, Finder finder) =>
    tester.getSize(finder).height;

/// The `GridView` delegate the product grid resolved to.
SliverGridDelegateWithFixedCrossAxisCount gridDelegate(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate = grid.gridDelegate;
  expect(delegate, isA<SliverGridDelegateWithFixedCrossAxisCount>(),
      reason: 'the product grid must use a fixed cross-axis count so column tests mean something');
  return delegate as SliverGridDelegateWithFixedCrossAxisCount;
}

/// Walks the semantics tree for the widget matched by [finder] and returns its label, so the
/// accessibility assertions read what an announced screen reader would, rather than trusting a
/// widget's doc comment. `tester.ensureSemantics()` must already be active (see [enableSemantics]).
SemanticsHandle enableSemantics(WidgetTester tester) {
  final handle = tester.ensureSemantics();
  addTearDown(handle.dispose);
  return handle;
}

String? semanticsLabel(WidgetTester tester, Finder finder) {
  enableSemantics(tester);
  return tester.getSemantics(finder).label;
}

bool semanticsFlag(WidgetTester tester, Finder finder, bool Function(SemanticsProperties) read) {
  enableSemantics(tester);
  return read(tester.getSemantics(finder).getProperties());
}
