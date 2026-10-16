import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';

/// Runs the authoritative Dart [PricingEngine] over the SAME fixture that drives the trusted
/// `functions/lib/pricing.js` (via `node functions/scripts/check_pricing_fixtures.js`). Because
/// the fixture carries the expected figures independently, keeping both engines green against it
/// is what proves the server and the client price a line identically. If these numbers move, the
/// server's `orders.createOrder` total will disagree with every cart the buyer was shown.
///
/// Money is integer paise; slab price applies to EVERY unit in the band.
Map<String, dynamic> _loadFixture() {
  // `flutter test` runs from the package root, so this relative path resolves there.
  final file = File('test/data/slab_fixtures.json');
  expect(file.existsSync(), isTrue, reason: 'fixture must exist at test/data/slab_fixtures.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Product _productFrom(Map<String, dynamic> m) => Product.fromMap(m, id: 'fixture');

ProductVariant? _variantFrom(Map<String, dynamic>? m) =>
    m == null ? null : ProductVariant.fromMap(m, id: 'fixture-variant');

void main() {
  final fixture = _loadFixture();

  group('Dart engine matches the shared slab fixtures', () {
    for (final raw in (fixture['priceCases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final id = raw['id'] as String;
      final product = _productFrom(raw['product'] as Map<String, dynamic>);
      final variant = _variantFrom(
        raw.containsKey('variant') ? raw['variant'] as Map<String, dynamic> : null,
      );
      final qty = raw['qty'] as int;
      final override = raw['customerOverrideUnitPricePaise'] as int?;
      final expectThrow = raw['expectThrow'] as bool? ?? false;

      test(id, () {
        if (expectThrow) {
          expect(
            () => PricingEngine.priceFor(
              product: product,
              qty: qty,
              variant: variant,
              customerOverrideUnitPricePaise: override,
            ),
            throwsA(isA<ValidationFailure>()),
            reason: raw['description'] as String? ?? '',
          );
          return;
        }

        final expected = raw['expected'] as Map<String, dynamic>;
        final resolution = PricingEngine.priceFor(
          product: product,
          qty: qty,
          variant: variant,
          customerOverrideUnitPricePaise: override,
        );

        expect(resolution.unitPricePaise, expected['unitPricePaise'], reason: id);
        expect(resolution.lineTotalPaise, expected['lineTotalPaise'], reason: id);
        expect(resolution.savedPaise, expected['savedPaise'], reason: id);
      });
    }
  });

  group('validateSlabGrid matches the shared grid fixtures', () {
    for (final raw in (fixture['gridCases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final id = raw['id'] as String;
      final slabs = (raw['slabs'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PriceSlab.fromMap)
          .toList(growable: false);
      final expectThrow = raw['expectThrow'] as bool;

      test(id, () {
        if (expectThrow) {
          expect(() => validateSlabGrid(slabs), throwsA(isA<ValidationFailure>()), reason: id);
        } else {
          expect(() => validateSlabGrid(slabs), returnsNormally, reason: id);
        }
      });
    }
  });

  group('CartTotals tax/shipping/rounding matches the shared tax fixtures', () {
    for (final raw in (fixture['taxCases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final id = raw['id'] as String;
      final lineTotal = raw['lineTotalPaise'] as int;
      final qty = raw['qty'] as int;
      final expected = raw['expected'] as Map<String, dynamic>;

      test(id, () {
        final line = PriceResolution(
          qty: qty,
          unitPricePaise: qty == 0 ? 0 : (lineTotal / qty).round(),
          lineTotalPaise: lineTotal,
          baseUnitPricePaise: lineTotal,
          savedPaise: 0,
        );
        final totals = CartTotals.from(
          <PriceResolution>[line],
          couponDiscountPaise: raw['couponDiscountPaise'] as int? ?? 0,
          shippingPaise: raw['shippingPaise'] as int? ?? 0,
          taxRateBps: raw['taxRateBps'] as int? ?? 0,
          taxInclusive: raw['taxInclusive'] as bool? ?? false,
        );

        expect(totals.subtotalPaise, expected['subtotalPaise'], reason: id);
        expect(totals.couponDiscountPaise, expected['couponDiscountPaise'], reason: id);
        expect(totals.taxPaise, expected['taxPaise'], reason: id);
        expect(totals.grandTotalPaise, expected['grandTotalPaise'], reason: id);
        expect(totals.payableRoundedPaise, expected['payableRoundedPaise'], reason: id);
      });
    }
  });
}
