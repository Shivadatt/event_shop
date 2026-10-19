// The accessibility contract, asserted against the live semantics tree instead of doc comments.
//
// The project claims a screen-reader customer can buy an item and a screen-reader admin can delete
// one. That is four guarantees per control: the node *says* something, it says the right thing, an
// assistive client can actually press it, and the page is walked in an order that makes sense.
// `om_harness.dart` grew the readers for all four in round 2 but nothing called them, so until this
// file the claim was untested.
//
// Everything asserted here is a real control: `OmButton`/`OmIconButton`/`OmQuantityStepper` are what
// `ProductBuyBox` and every cart line render, `CartTotalsPanel` is the checkout summary the buyer
// commits to, and `omConfirmAdminAction` is the gate every privileged admin mutation — delete
// category, delete variant, delete image, delete override, change role, archive product — passes
// through.
//
// Two of these guarantees were broken when round 3 started: `OmButton` handed the engine a tap
// action without the button role (so the shop's primary CTA was announced as plain text) and
// `OmQuantityStepper`'s +/- steps carried only a `Tooltip`, which is a description and not an
// accessible name. `lib/app/core/widgets/om_buttons.dart` and `om_inputs.dart` now wrap both in
// `Semantics(button: true, label: …)`; the tests that used to be left RED on purpose are ordinary
// passing tests now, and they are the regression net that keeps the checkout reachable.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/storefront/cart/widgets/cart_totals.dart';
import '../support/om_harness.dart';

/// The first spoken entry containing [phrase], or a failure that prints the whole spoken order so a
/// regression shows what the user would actually hear.
int _spokenAt(List<String> spoken, String phrase) {
  final index = spoken.indexWhere((s) => s.contains(phrase));
  expect(
    index,
    greaterThanOrEqualTo(0),
    reason: 'nothing announced contains "$phrase" — the screen reader hears: $spoken',
  );
  return index;
}

/// The node a screen reader lands on for an announced control, found by what it says.
///
/// Reading by label rather than `find.byType` matters twice over. `OmButton` wraps its `InkWell` in
/// a `Focus`/`DecoratedBox`, and the semantics node attached to that wrapper is empty, so
/// `getSemantics(find.byType(OmButton))` returns the wrapper and a label assertion fails for the
/// wrong reason. And the announced text is usually a *fragment* of a longer label — the stepper says
/// `"Quantity for Latex Balloon Pack, 4"`, the cart line says `"Remove X from cart"` inside a longer
/// merged string — while `find.bySemanticsLabel(String)` demands exact equality. Matching a pattern
/// is both what an assistive client's find-by-phrase does and what these controls really say.
Finder _saying(String phrase) => find.bySemanticsLabel(RegExp(RegExp.escape(phrase)));

/// Asserts the three things every control in the buy or delete path must satisfy, in one place, so
/// no test can quietly assert only "it exists". [roleRequired] is false only where the widget
/// deliberately is not a button (nothing here qualifies).
void expectAnnouncedControl(
  WidgetTester tester,
  String phrase, {
  required String reason,
  bool pressable = true,
}) {
  final finder = _saying(phrase);
  expect(
    finder,
    findsOneWidget,
    reason: '$phrase: a screen reader finds no node saying this. $reason',
  );
  final label = semanticsLabel(tester, finder);
  expect(
    label?.trim(),
    isNotNull,
    reason: '$phrase: no semantics node at all — the control is invisible to assistive tech',
  );
  expect(
    label!.trim(),
    isNotEmpty,
    reason:
        '$phrase: the node exists but says nothing. $reason A named widget with an empty label is '
        'an unreachable control, and this suite fails it rather than documenting it.',
  );
  expect(
    label,
    contains(phrase),
    reason: 'the node that matched must really say "$phrase", not merely be nearby: "$label"',
  );
  expect(
    semanticsFlag(tester, finder, (node) => node.flagsCollection.isButton),
    isTrue,
    reason: '$phrase is announced without the button role, so the reader says the words but the '
        'user is never told they can be pressed: $reason',
  );
  expect(
    semanticsSupportsAction(tester, finder, SemanticsAction.tap),
    isTrue,
    reason: '$phrase carries a label but no tap action — a screen reader can hear it and cannot '
        'press it: $reason',
  );
}

/// `pumpOm` with the semantics client opened *first*.
///
/// `find.bySemanticsLabel` searches the node tree rather than the widget tree, and it throws
/// outright when semantics are off, so the client has to exist before the frame is pumped —
/// otherwise every finder here fails for a reason that has nothing to do with accessibility.
Future<void> _pumpSpoken(WidgetTester tester, Widget child, {required double width}) async {
  enableSemantics(tester);
  await pumpOm(tester, child, width: width);
}

void main() {
  group('storefront buy and cart controls', () {
    testWidgets('the add-to-cart CTA says what it adds, is a button, and fires', (tester) async {
      var taps = 0;
      await _pumpSpoken(
        tester,
        OmButton(
          label: 'Add 2 to cart',
          icon: Icons.shopping_bag_outlined,
          size: OmButtonSize.large,
          expanded: true,
          onPressed: () => taps++,
        ),
        width: 420,
      );

      // The buy box spells the quantity into the label ('Add $qty to cart'), which is the whole
      // point: a blind buyer hears how many units they are about to order.
      expectAnnouncedControl(
        tester,
        'Add 2 to cart',
        reason: 'this is the storefront cart CTA — ProductBuyBox renders it for every product page.',
      );

      await tester.tap(_saying('Add 2 to cart'));
      await tester.pump();
      expect(taps, 1, reason: 'the node the screen reader announces is the node that actually adds');
    });

    testWidgets('the checkout CTA announces itself as a button', (tester) async {
      await _pumpSpoken(
        tester,
        OmButton(label: 'Proceed to checkout', onPressed: () {}),
        width: 420,
      );

      expectAnnouncedControl(
        tester,
        'Proceed to checkout',
        reason: 'OmButton is built on a bare InkWell, which historically handed the engine a tap '
            'action without SemanticsFlag.isButton; the role must be on the node or the last step '
            'of the funnel is announced as static text.',
      );
    });

    testWidgets('a sold-out buy button says so instead of offering a dead press', (tester) async {
      await _pumpSpoken(
        tester,
        const OmButton(label: 'Out of stock', icon: Icons.shopping_bag_outlined),
        width: 420,
      );

      final finder = _saying('Out of stock');
      expect(
        finder,
        findsOneWidget,
        reason: 'a disabled button that says nothing reads as a broken app',
      );
      expect(
        semanticsLabel(tester, finder)!.trim(),
        contains('Out of stock'),
        reason: 'the sold-out state has to be spoken, not only greyed out',
      );
      expect(
        semanticsSupportsAction(tester, finder, SemanticsAction.tap),
        isFalse,
        reason: 'the sold-out button must not advertise a press that goes nowhere',
      );
    });

    testWidgets('the cart/wishlist icon buttons name the product they act on', (tester) async {
      var removed = 0;
      await _pumpSpoken(
        tester,
        Row(
          children: <Widget>[
            OmIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove Latex Balloon Pack from cart',
              onPressed: () => removed++,
            ),
            const OmIconButton(
              icon: Icons.favorite,
              tooltip: 'Save Latex Balloon Pack to wishlist',
              selected: true,
            ),
          ],
        ),
        width: 560,
      );

      // An icon button's tooltip must reach the node as a *label*: `Tooltip` alone is a description,
      // so without the label every line action in the cart is announced as an unnamed "button".
      expectAnnouncedControl(
        tester,
        'Remove Latex Balloon Pack from cart',
        reason: 'a cart line action that does not name its product deletes the wrong line.',
      );
      await tester.tap(_saying('Remove Latex Balloon Pack from cart'));
      await tester.pump();
      expect(removed, 1);

      final saved = _saying('Save Latex Balloon Pack to wishlist');
      expect(saved, findsOneWidget, reason: 'the wishlist toggle must be findable by what it says');
      expect(
        semanticsLabel(tester, saved)!.trim(),
        contains('Save Latex Balloon Pack to wishlist'),
      );
      expect(
        semanticsFlag(tester, saved, (node) => node.flagsCollection.isButton),
        isTrue,
        reason: 'OmIconButton promises Semantics(button: true)',
      );
    });

    testWidgets('the quantity stepper is bound to a named product and value', (tester) async {
      final requests = <int>[];
      await _pumpSpoken(
        tester,
        OmQuantityStepper(
          value: 4,
          onChanged: requests.add,
          label: 'Quantity for Latex Balloon Pack',
        ),
        width: 420,
      );

      final finder = _saying('Quantity for Latex Balloon Pack');
      expect(finder, findsOneWidget);
      final label = semanticsLabel(tester, finder)!;
      expect(
        label,
        contains('Quantity for Latex Balloon Pack'),
        reason: 'wholesale products are bought in packs; the label is what ties this stepper to the '
            'product it orders',
      );
      expect(
        label,
        contains('4'),
        reason: 'the current quantity has to be spoken, or the buyer cannot tell what the CTA\'s '
            '"Add 4 to cart" refers to',
      );

      final spoken = spokenOrder(tester);
      expect(
        _spokenAt(spoken, 'Quantity for Latex Balloon Pack'),
        lessThan(_spokenAt(spoken, 'Increase quantity')),
        reason: 'the field is announced before the buttons that change it: $spoken',
      );
    });

    testWidgets('the +/- steps are named, pressable controls — not bare tooltips', (tester) async {
      final requests = <int>[];
      await _pumpSpoken(
        tester,
        OmQuantityStepper(
          value: 4,
          onChanged: requests.add,
          label: 'Quantity for Latex Balloon Pack',
        ),
        width: 420,
      );

      for (final phrase in <String>['Decrease quantity', 'Increase quantity']) {
        // `OmQuantityStepper._stepButton` renders Tooltip + InkWell + Icon. A tooltip is a
        // description, not an accessible name: unless the step also carries
        // `Semantics(label: tooltip)` a voice-control customer cannot say "tap Increase quantity",
        // and an icon-only control in the middle of the buy flow has no name at all.
        expectAnnouncedControl(
          tester,
          phrase,
          reason: 'stepping a 100-unit pack of wholesale balloons is exactly the gesture that needs '
              'a name.',
        );
      }

      await tester.tap(_saying('Increase quantity'));
      await tester.pump();
      expect(
        requests,
        <int>[5],
        reason: 'the announced step is the working step: pressing "Increase quantity" must reach '
            'onChanged with the next quantity',
      );

      await tester.tap(_saying('Decrease quantity'));
      await tester.pump();
      expect(requests, <int>[5, 3], reason: 'and the same for the other direction');
    });

    testWidgets('a sold-out stepper keeps its names but loses its presses', (tester) async {
      await _pumpSpoken(
        tester,
        OmQuantityStepper(
          value: 1,
          enabled: false,
          onChanged: (int next) {},
          label: 'Quantity for Latex Balloon Pack',
        ),
        width: 420,
      );

      for (final phrase in <String>['Decrease quantity', 'Increase quantity']) {
        final finder = _saying(phrase);
        expect(
          finder,
          findsOneWidget,
          reason: 'a disabled control still has to say what it was, or the buyer cannot tell a sold-'
              'out stepper from a missing one',
        );
        expect(semanticsLabel(tester, finder)!.trim(), contains(phrase));
        expect(
          semanticsSupportsAction(tester, finder, SemanticsAction.tap),
          isFalse,
          reason: 'disabled steps must not advertise a press',
        );
      }
    });
  });

  group('checkout summary', () {
    testWidgets('the payable amount is announced as an amount, after the lines that make it up',
        (tester) async {
      await _pumpSpoken(
        tester,
        CartTotalsPanel.estimate(
          totals: const CartTotals(
            subtotalPaise: 48000,
            slabSavingsPaise: 3000,
            couponDiscountPaise: 0,
            shippingPaise: 6000,
            taxPaise: 0,
            lineCount: 2,
            unitCount: 6,
          ),
        ),
        width: 520,
      );

      final finder = _saying('Estimated payable');
      expect(
        finder,
        findsOneWidget,
        reason: 'CartTotalsPanel sets an explicit semantics label on the payable line so the amount '
            'is spoken as an amount — the last line of defence against a screen reader passing over '
            'the rupee glyph as nothing',
      );
      final summary = semanticsLabel(tester, finder)!;
      expect(
        summary.trim(),
        isNotEmpty,
        reason: 'the summary node exists but says nothing',
      );
      expect(
        summary,
        contains('Estimated payable'),
        reason: 'the one figure a customer commits to must be announced, not just drawn',
      );
      expect(summary, contains('54000 paise'), reason: 'the spoken payable must be the paise amount');
      expect(summary, contains('₹480'), reason: 'merchandise total must be spoken');
      expect(summary, contains('₹30'), reason: 'slab savings must be spoken');
      expect(summary, contains('₹60'), reason: 'shipping must be spoken');
      expect(
        summary,
        contains('confirmed by the server at checkout'),
        reason: 'an estimate presented as a charge is a mispricing claim; the caveat has to be '
            'audible, not only visible',
      );

      // The panel is one merged semantics node, so its reading order lives *inside* the label:
      // comparing node indices here would compare one entry with itself.
      expect(
        summary.indexOf('Order summary'),
        lessThan(summary.indexOf('Estimated payable')),
        reason: 'the heading must be announced before the amount it introduces: $summary',
      );
      expect(
        summary.indexOf('Merchandise total'),
        lessThan(summary.indexOf('Estimated payable')),
        reason: 'a buyer hears the components before the total',
      );
      expect(
        summary.indexOf('Shipping'),
        lessThan(summary.indexOf('Estimated payable')),
      );
    });

    testWidgets('the checkout CTA is announced after the total it charges', (tester) async {
      await _pumpSpoken(
        tester,
        Column(
          children: <Widget>[
            CartTotalsPanel.estimate(totals: CartTotals.empty),
            OmButton(label: 'Proceed to checkout', onPressed: () {}),
          ],
        ),
        width: 520,
      );

      final spoken = spokenOrder(tester);
      expect(
        _spokenAt(spoken, 'Estimated payable'),
        lessThan(_spokenAt(spoken, 'Proceed to checkout')),
        reason: 'the buyer hears what they are paying before the button that charges them: $spoken',
      );
    });
  });

  group('admin destructive actions', () {
    Future<void> pumpDeleteGate(WidgetTester tester) async {
      await _pumpSpoken(
        tester,
        Builder(
          builder: (context) => OmButton(
            label: 'Open the delete gate',
            variant: OmButtonVariant.danger,
            onPressed: () => omConfirmAdminAction(
              context: context,
              title: 'Delete “Latex”?',
              message: 'Products in this category must be moved first. This is written to the '
                  'audit log.',
              confirmLabel: 'Delete category',
              destructive: true,
            ),
          ),
        ),
        width: 800,
      );
      await tester.tap(_saying('Open the delete gate'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    testWidgets('the confirm-before-write gate names the destructive action', (tester) async {
      await pumpDeleteGate(tester);

      expectAnnouncedControl(
        tester,
        'Delete category',
        reason: 'omConfirmAdminAction is the gate every privileged admin mutation passes through; a '
            'confirm button with no spoken label is how a category gets deleted by accident.',
      );
      expect(
        _saying('Cancel'),
        findsOneWidget,
        reason: 'the safe exit must be reachable too, not only the destructive one',
      );
      expect(
        semanticsFlag(
          tester,
          _saying('Cancel'),
          (node) => node.flagsCollection.isButton,
        ),
        isTrue,
        reason: 'the exit from a destructive dialog has to be announced as a control',
      );
    });

    testWidgets('pressing the announced destructive control is what commits the action',
        (tester) async {
      late Future<bool> gate;
      await _pumpSpoken(
        tester,
        Builder(
          builder: (context) => OmButton(
            label: 'Open the delete gate',
            onPressed: () => gate = omConfirmAdminAction(
              context: context,
              title: 'Delete “Latex”?',
              message: 'This is written to the audit log.',
              confirmLabel: 'Delete category',
              destructive: true,
            ),
          ),
        ),
        width: 800,
      );
      await tester.tap(_saying('Open the delete gate'));
      await tester.pumpAndSettle();

      await tester.tap(_saying('Delete category'));
      await tester.pumpAndSettle();
      expect(
        await gate,
        isTrue,
        reason: 'the node an assistive client presses must resolve the gate as a confirmation — '
            'otherwise the label is decoration over a dead target',
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancelling the gate resolves false instead of performing the mutation',
        (tester) async {
      late Future<bool> gate;
      await _pumpSpoken(
        tester,
        Builder(
          builder: (context) => OmButton(
            label: 'Open the delete gate',
            onPressed: () => gate = omConfirmAdminAction(
              context: context,
              title: 'Archive this product',
              message: 'Archiving hides it from the storefront.',
              confirmLabel: 'Archive product',
              destructive: true,
            ),
          ),
        ),
        width: 800,
      );
      await tester.tap(_saying('Open the delete gate'));
      await tester.pumpAndSettle();

      await tester.tap(_saying('Cancel'));
      await tester.pumpAndSettle();
      expect(
        await gate,
        isFalse,
        reason: 'the announced safe exit must back out of the write, not confirm it',
      );
    });

    testWidgets('the gate is read in the order the decision is made', (tester) async {
      await pumpDeleteGate(tester);

      final spoken = spokenOrder(tester);
      expect(
        _spokenAt(spoken, 'Delete “Latex”?'),
        lessThan(_spokenAt(spoken, 'written to the audit log')),
        reason: 'the consequence must be spoken before the buttons, or the user presses first and '
            'reads after: $spoken',
      );
      expect(
        _spokenAt(spoken, 'written to the audit log'),
        lessThan(_spokenAt(spoken, 'Delete category')),
        reason: 'nothing destructive is announced-then-pressable before the warning has been heard: '
            '$spoken',
      );
      expect(
        _spokenAt(spoken, 'Cancel'),
        lessThan(_spokenAt(spoken, 'Delete category')),
        reason: 'the safe exit has to come before the destructive one in traversal order: $spoken',
      );
    });

    testWidgets('a danger-variant row action is labelled, not just coloured red', (tester) async {
      await _pumpSpoken(
        tester,
        OmButton(label: 'Delete override', variant: OmButtonVariant.danger, onPressed: () {}),
        width: 420,
      );

      expectAnnouncedControl(
        tester,
        'Delete override',
        reason: 'the pricing table deletes a contract price on colour alone, and colour carries no '
            'meaning to a screen reader.',
      );
    });
  });

  group('buy-box reading order', () {
    testWidgets('quantity is announced before the buy button, and the buy button before the '
        'wishlist toggle', (tester) async {
      await _pumpSpoken(
        tester,
        Row(
          children: <Widget>[
            OmQuantityStepper(
              value: 2,
              onChanged: (int next) {},
              label: 'Quantity for Latex Balloon Pack',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OmButton(
                label: 'Add 2 to cart',
                icon: Icons.shopping_bag_outlined,
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 8),
            OmIconButton(
              icon: Icons.favorite_border,
              tooltip: 'Save Latex Balloon Pack to wishlist',
              onPressed: () {},
            ),
          ],
        ),
        width: 720,
      );

      final spoken = spokenOrder(tester);
      expect(
        _spokenAt(spoken, 'Quantity for Latex Balloon Pack'),
        lessThan(_spokenAt(spoken, 'Add 2 to cart')),
        reason: 'a customer must hear the quantity before the button whose label repeats it: $spoken',
      );
      expect(
        _spokenAt(spoken, 'Add 2 to cart'),
        lessThan(_spokenAt(spoken, 'Save Latex Balloon Pack to wishlist')),
        reason: 'the primary action comes before the secondary one, matching the visual order: '
            '$spoken',
      );
      expect(
        _spokenAt(spoken, 'Increase quantity'),
        lessThan(_spokenAt(spoken, 'Add 2 to cart')),
        reason: 'both steps of the stepper are announced before the CTA that reads their value',
      );
    });
  });
}
