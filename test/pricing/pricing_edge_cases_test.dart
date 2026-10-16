// Pricing edge cases beyond the four canonical figures in pricing_engine_test.dart: variant-level
// slab grids, a negotiated customer override, and a live sale price moving the discount baseline.
// Money invariants (integer paise, no float) are asserted here because a wrong base price silently
// misprices every line in a wholesale cart.
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';

const _base = Product(
  id: 'p',
  name: 'Balloons',
  retailPricePaise: 20000,
  slabs: <PriceSlab>[
    PriceSlab(minQty: 1, maxQty: 9, unitPricePaise: 20000),
    PriceSlab(minQty: 10, unitPricePaise: 18000),
  ],
);

void main() {
  group('variant-level slabs', () {
    const variant = ProductVariant(
      id: 'v1',
      productId: 'p',
      name: 'Jumbo',
      retailPricePaise: 30000,
      slabs: <PriceSlab>[PriceSlab(minQty: 6, unitPricePaise: 25000)],
    );

    test('a variant with its own grid ignores the product slabs', () {
      final r = PricingEngine.priceFor(product: _base, qty: 10, variant: variant);
      // 10 units of the variant: the variant's 6+ band wins over the product's 10+ band.
      expect(r.unitPricePaise, 25000);
      expect(r.baseUnitPricePaise, 30000);
      expect(r.savedPaise, 50000); // (30000-25000) * 10
    });

    test('below the variant band the variant retail is charged, not the product price', () {
      final r = PricingEngine.priceFor(product: _base, qty: 3, variant: variant);
      expect(r.unitPricePaise, 30000);
      expect(r.lineTotalPaise, 90000);
    });

    test('a variant with no slabs of its own inherits the product grid', () {
      const bare = ProductVariant(
        id: 'v2',
        productId: 'p',
        name: 'Standard',
        retailPricePaise: 20000,
      );
      final r = PricingEngine.priceFor(product: _base, qty: 10, variant: bare);
      expect(r.unitPricePaise, 18000);
    });
  });

  group('negotiated customer override', () {
    test('the override wins over public slabs and is applied to every unit', () {
      final r = PricingEngine.priceFor(product: _base, qty: 4, customerOverrideUnitPricePaise: 15000);
      expect(r.unitPricePaise, 15000);
      expect(r.lineTotalPaise, 60000);
      expect(r.savedPaise, 20000); // against the 20000 shelf price
      expect(r.slab, isNull, reason: 'a contract price is not a volume tier');
    });

    test('an override above shelf price shows no saving, never a negative discount', () {
      final r = PricingEngine.priceFor(product: _base, qty: 2, customerOverrideUnitPricePaise: 25000);
      expect(r.unitPricePaise, 25000);
      expect(r.savedPaise, 0);
    });

    test('a zero or negative override is ignored, falling back to slabs', () {
      final r = PricingEngine.priceFor(product: _base, qty: 10, customerOverrideUnitPricePaise: 0);
      expect(r.unitPricePaise, 18000);
    });
  });

  group('mergeQty aggregates split lines', () {
    test('rows of the same product reach one slab band together', () {
      expect(PricingEngine.mergeQty(<int>[6, 5]), 11);
      final r = PricingEngine.priceFor(product: _base, qty: PricingEngine.mergeQty(<int>[6, 5]));
      expect(r.unitPricePaise, 18000, reason: '11 merged units cross the 10+ band');
    });
  });

  group('granularity accepts/rejects', () {
    test('accepts only in-range multiples', () {
      const g = OrderGranularity(minQty: 5, multiple: 5);
      expect(g.accepts(10), isTrue);
      expect(g.accepts(11), isFalse);
      expect(g.accepts(4), isFalse);
      expect(g.violationFor(3), contains('5'));
      expect(g.violationFor(6), contains('multiple'));
    });
  });
}
