/// Test harness for the QA suite: a viewport the size we are asserting about, the real brand theme,
/// and a text scaler that matches what `main.dart` clamps production to (0.9–1.6).
///
/// Nothing here fakes a backend. Widgets under test receive the widgets they would receive in the
/// app; repository fakes live in `om_fakes.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

/// Semantics is already on, so opening a client here would only create a leak.
///
/// `testWidgets` defaults to `semanticsEnabled: true`: it calls `tester.ensureSemantics()` before
/// the body and disposes that handle after it, *inside* the run. A handle opened by a reader cannot
/// be disposed the same way — `WidgetTester` counts outstanding handles at the end of the body and
/// only then runs `addTearDown`, so any harness-owned handle reports itself as
/// "A SemanticsHandle was active at the end of the test" even when it is cleaned up correctly.
/// The readers below therefore assert the tree is live and read through the binding's own handle.
///
/// The liveness check reads the root of the pipeline-owner tree
/// (`RendererBinding.rootPipelineOwner`) instead of the deprecated `pipelineOwner` property: that
/// root is attached to the binding's `PipelineManifold` for the whole life of the binding, so its
/// `semanticsOwner` exists exactly while a semantics client is connected — which is what
/// `testWidgets(semanticsEnabled: true)` guarantees.
void enableSemantics(WidgetTester tester) {
  assert(
    tester.binding.rootPipelineOwner.semanticsOwner != null,
    'No semantics owner: the suite must keep `semanticsEnabled: true` (the testWidgets default).',
  );
}

/// The label an announced screen reader would speak for the widget matched by [finder], so the
/// accessibility assertions read what the user hears rather than trusting a widget's doc comment.
String? semanticsLabel(WidgetTester tester, Finder finder) {
  enableSemantics(tester);
  return tester.getSemantics(finder).label;
}

/// Reads a boolean off the live semantics node of the widget matched by [finder] — this is how the
/// suite proves a control announces what it is and which state it is in. In this SDK the node
/// exposes `label` and the collected `flagsCollection` directly (`hasFlag(SemanticsFlag)` is
/// deprecated since 3.32, so the readers here use the flags object):
/// `semanticsFlag(tester, finder, (node) => node.flagsCollection.isButton)`.
bool semanticsFlag(
  WidgetTester tester,
  Finder finder,
  bool Function(SemanticsNode node) read,
) {
  enableSemantics(tester);
  return read(tester.getSemantics(finder));
}

/// Whether the widget matched by [finder] actually *exposes* [action] to an assistive client.
///
/// A label alone is not an accessible control: if the node has no `tap` action a screen-reader user
/// hears the name and cannot press it. Reads the collected node data, which is what the engine
/// serialises, rather than the raw per-widget annotation.
bool semanticsSupportsAction(
  WidgetTester tester,
  Finder finder,
  SemanticsAction action,
) {
  enableSemantics(tester);
  return tester.getSemantics(finder).getSemanticsData().hasAction(action);
}

/// The `SemanticsOwner` that holds the tree a screen reader is actually walking.
///
/// `RendererBinding.pipelineOwner` is deprecated, so this asks the binding for the `RenderView`s it
/// manages and takes the semantics owner of the pipeline owner managing each one — which for the
/// single default view `pumpWidget` installs is the same pipeline owner the deprecated property
/// exposed (the view's render tree is rooted in it). `flutter_test`'s own `WidgetController`, and
/// the framework's accessibility evaluations, read the tree the same way.
SemanticsOwner? _liveSemanticsOwner(WidgetTester tester) {
  for (final renderView in tester.binding.renderViews) {
    final owner = renderView.owner?.semanticsOwner;
    if (owner != null) return owner;
  }
  return null;
}

/// Every string a screen reader would speak in this frame, in traversal order — the order the
/// accessibility service walks the tree, taken from the node tree itself
/// (`DebugSemanticsDumpOrder.traversalOrder`) rather than from widget declaration order, which is
/// exactly the distinction a reading-order bug hides behind.
///
/// Depth-first and *pre-order*: a node is announced, then what is inside it. Post-order would report
/// a button as coming before the heading that introduces it, so the list would not be the order
/// anyone with a screen reader actually hears.
///
/// Nodes that say nothing (no label and no tooltip) are skipped, as are nodes merged into a parent,
/// because their text is already inside the parent's label and repeating them would make a reading
/// order assertion depend on internal merge details. Their children are still walked — merge is a
/// property of the node, not a subtree boundary.
List<String> spokenOrder(WidgetTester tester) {
  enableSemantics(tester);
  final root = _liveSemanticsOwner(tester)?.rootSemanticsNode;
  expect(
    root,
    isNotNull,
    reason: 'semantics must be enabled before asking for the traversal order',
  );
  final spoken = <String>[];
  void visit(SemanticsNode node) {
    if (!node.isMergedIntoParent) {
      final text = (node.label.isNotEmpty ? node.label : node.tooltip).trim();
      if (text.isNotEmpty) spoken.add(text);
    }
    for (final child in node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
      visit(child);
    }
  }
  if (root != null) visit(root);
  return spoken;
}
