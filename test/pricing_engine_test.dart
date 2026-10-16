import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';

/// The four figures from the brief, as executable assertions. If any of these move, the pricing
/// engine and `functions/lib/pricing.js` have diverged and every cart total in the store is
/// suspect.
Product _balloons() => const Product(
      id: 'p1',
      name: 'Latex Balloon Pack',
      retailPricePaise: 11000,
      slabs: <PriceSlab>[
        PriceSlab(minQty: 1, maxQty: 9, unitPricePaise: 11000),
        PriceSlab(minQty: 10, maxQty: 20, unitPricePaise: 10000),
        PriceSlab(minQty: 21, unitPricePaise: 9500),
      ],
    );

void main() {
  group('PricingEngine slab boundaries', () {
    final product = _balloons();

    test('1 pack pays the retail price', () {
      final r = PricingEngine.priceFor(product: product, qty: 1);
      expect(r.unitPricePaise, 11000);
      expect(r.lineTotalPaise, 11000);
      expect(r.savedPaise, 0);
    });

    test('10 packs cross into the second slab for every unit', () {
      final r = PricingEngine.priceFor(product: product, qty: 10);
      expect(r.unitPricePaise, 10000);
      expect(r.lineTotalPaise, 100000);
      expect(r.savedPaise, 1000);
    });

    test('20 packs stay in the middle slab', () {
      final r = PricingEngine.priceFor(product: product, qty: 20);
      expect(r.unitPricePaise, 10000);
      expect(r.lineTotalPaise, 200000);
    });

    test('21 packs drop to the open-ended slab', () {
      final r = PricingEngine.priceFor(product: product, qty: 21);
      expect(r.unitPricePaise, 9500);
      expect(r.lineTotalPaise, 199950);
    });

    test('the gap between 9 and 10 has no unpriced quantity', () {
      for (final qty in <int>[9, 10, 20, 21, 500]) {
        expect(
          PricingEngine.priceFor(product: product, qty: qty).unitPricePaise,
          greaterThan(0),
          reason: 'quantity $qty must resolve to a price',
        );
      }
    });

    test('below the first band the buyer pays retail, not the nearest discount', () {
      final p = const Product(
        id: 'p2',
        name: 'Only bulk discounted',
        retailPricePaise: 50000,
        slabs: <PriceSlab>[PriceSlab(minQty: 50, unitPricePaise: 40000)],
      );
      expect(PricingEngine.priceFor(product: p, qty: 49).unitPricePaise, 50000);
      expect(PricingEngine.priceFor(product: p, qty: 50).unitPricePaise, 40000);
    });

    test('next-slab nudge counts the units actually missing', () {
      final r = PricingEngine.priceFor(product: product, qty: 8);
      expect(r.unitsToNextSlab, 2);
      expect(r.nextSlab?.unitPricePaise, 10000);
    });

    test('zero and negative quantity price nothing instead of crashing a cart line', () {
      expect(PricingEngine.priceFor(product: product, qty: 0).lineTotalPaise, 0);
      expect(PricingEngine.priceFor(product: product, qty: -5).lineTotalPaise, 0);
    });
  });

  group('Ambiguous slab grids are refused', () {
    test('two slabs claiming the same quantity throws rather than picking one', () {
      const product = Product(
        id: 'p3',
        name: 'Broken grid',
        retailPricePaise: 10000,
        slabs: <PriceSlab>[
          PriceSlab(minQty: 1, maxQty: 10, unitPricePaise: 10000),
          PriceSlab(minQty: 5, maxQty: 20, unitPricePaise: 9000),
        ],
      );
      expect(
        () => PricingEngine.priceFor(product: product, qty: 7),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('validateSlabGrid rejects overlap, inversion and an open-ended middle band', () {
      expect(
        () => validateSlabGrid(const <PriceSlab>[
          PriceSlab(minQty: 1, maxQty: 10, unitPricePaise: 10000),
          PriceSlab(minQty: 10, unitPricePaise: 9000),
        ]),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => validateSlabGrid(const <PriceSlab>[
          PriceSlab(minQty: 20, maxQty: 10, unitPricePaise: 9000),
        ]),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => validateSlabGrid(const <PriceSlab>[
          PriceSlab(minQty: 1, unitPricePaise: 10000),
          PriceSlab(minQty: 10, unitPricePaise: 9000),
        ]),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a clean contiguous grid passes', () {
      validateSlabGrid(const <PriceSlab>[
        PriceSlab(minQty: 1, maxQty: 9, unitPricePaise: 11000),
        PriceSlab(minQty: 10, maxQty: 20, unitPricePaise: 10000),
        PriceSlab(minQty: 21, unitPricePaise: 9500),
      ]);
    });
  });

  group('Order granularity', () {
    test('a carton multiple rounds up, never down', () {
      const g = OrderGranularity(minQty: 12, multiple: 12);
      expect(g.clampQty(1), 12);
      expect(g.clampQty(13), 24);
      expect(g.clampQty(24), 24);
      expect(g.violationFor(13), isNotNull);
      expect(g.violationFor(24), isNull);
    });
  });

  group('Cart totals', () {
    test('slab savings and coupon discounts are kept separate', () {
      final product = _balloons();
      final lines = <PriceResolution>[
        PricingEngine.priceFor(product: product, qty: 21),
        PricingEngine.priceFor(product: product, qty: 1),
      ];
      final totals = CartTotals.from(lines, couponDiscountPaise: 5000);

      expect(totals.subtotalPaise, 199950 + 11000);
      expect(totals.slabSavingsPaise, 21050);
      expect(totals.couponDiscountPaise, 5000);
      expect(totals.grandTotalPaise, 199950 + 11000 - 5000);
    });

    test('a coupon cannot exceed the cart', () {
      final totals = CartTotals.from(
        <PriceResolution>[
          PriceResolution(
            qty: 1,
            unitPricePaise: 1000,
            lineTotalPaise: 1000,
            baseUnitPricePaise: 1000,
            savedPaise: 0,
          ),
        ],
        couponDiscountPaise: 99999,
      );
      expect(totals.couponDiscountPaise, 1000);
      expect(totals.grandTotalPaise, 0);
    });

    test('GST-exclusive adds tax on the discounted subtotal, inclusive adds none', () {
      final line = const PriceResolution(
        qty: 2,
        unitPricePaise: 10000,
        lineTotalPaise: 20000,
        baseUnitPricePaise: 10000,
        savedPaise: 0,
      );
      final exclusive = CartTotals.from(<PriceResolution>[line], taxRateBps: 1800);
      expect(exclusive.taxPaise, 3600);
      final inclusive =
          CartTotals.from(<PriceResolution>[line], taxRateBps: 1800, taxInclusive: true);
      expect(inclusive.taxPaise, 0);
    });
  });
}
