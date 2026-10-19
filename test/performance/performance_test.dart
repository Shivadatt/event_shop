// Performance guardrails for the hot paths a shopper hits on every interaction: pricing resolution
// (runs for every cart line on every keystroke), slug generation (runs on every admin save), money
// formatting (runs on every price label) and catalogue query keying (runs on every filter change).
//
// These are not micro-optimisation benchmarks — they are regression traps for accidental quadratic
// behaviour. Thresholds are deliberately generous so a normal test host is never flaky, but a real
// algorithmic regression (an O(n^2) sort, a re-parse per call) would blow past them.
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/utils/om_slug.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';
import 'package:om_events/data/query.dart';

Product _wideGrid(int slabCount) => Product(
      id: 'wide',
      name: 'Wide Grid',
      retailPricePaise: 100000,
      slabs: <PriceSlab>[
        for (var i = 0; i < slabCount; i++)
          PriceSlab(
            minQty: i * 10 + 1,
            maxQty: i == slabCount - 1 ? null : i * 10 + 10,
            unitPricePaise: 100000 - i * 100,
          ),
      ],
    );

void main() {
  test('priceFor resolves a 500-slab product in a bounded number of operations', () {
    final product = _wideGrid(500);
    final sw = Stopwatch()..start();
    for (var qty = 1; qty <= 2000; qty++) {
      final r = PricingEngine.priceFor(product: product, qty: qty);
      expect(r.lineTotalPaise, r.unitPricePaise * qty);
    }
    sw.stop();
    // 2000 resolutions over a 500-band grid. Anything super-linear lands far past this.
    expect(sw.elapsedMilliseconds, lessThan(4000),
        reason: 'slab resolution must stay near-linear in the number of lookups');
  });

  test('validateSlabGrid accepts a large contiguous grid without pathological cost', () {
    final product = _wideGrid(400);
    final sw = Stopwatch()..start();
    validateSlabGrid(product.slabs);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('slug generation is fast and allocation-stable over a batch of names', () {
    final names = <String>[
      for (var i = 0; i < 5000; i++) 'Balloon Arch Kit #$i — Chrome & Party ($i)',
    ];
    final sw = Stopwatch()..start();
    final slugs = names.map(OmSlug.from).toList();
    sw.stop();
    expect(slugs.every((s) => s.isNotEmpty), isTrue);
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('OmSlug.from is deterministic (a stable id for a stable name)', () {
    const name = '12ft Chrome Balloon Arch & Kit';
    expect(OmSlug.from(name), OmSlug.from(name));
    expect(OmSlug.from(name), '12ft-chrome-balloon-arch-and-kit');
  });

  test('money formatting over a large cart stays linear and cheap', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20000; i++) {
      OmMoney.format(i * 137);
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('money parse/format round-trips for the common case', () {
    for (final rupees in [1, 49, 100, 1234, 99999]) {
      final paise = rupees * 100;
      expect(OmMoney.parseRupeeString(OmMoney.format(paise)), paise);
    }
  });

  test('cacheKey is stable and collision-free across distinct queries', () {
    const a = CatalogQuery(search: 'balloon');
    const b = CatalogQuery(search: 'balloon', categoryId: 'c1');
    expect(a.cacheKey == b.cacheKey, isFalse);
    expect(a.cacheKey, const CatalogQuery(search: 'balloon').cacheKey);
  });

  test('filterCount counts independent filter dimensions', () {
    const query = CatalogQuery(
      search: 'x',
      categoryId: 'c',
      tags: <String>['a', 'b'],
      minPricePaise: 100,
      inStockOnly: true,
    );
    expect(query.filterCount, 5);
    expect(query.hasFilters, isTrue);
    expect(const CatalogQuery().hasFilters, isFalse);
  });

  test('clearing a query keeps only sort and page size', () {
    const query = CatalogQuery(search: 'x', categoryId: 'c', sort: SortMode.priceLowHigh, pageSize: 12);
    final cleared = query.cleared();
    expect(cleared.hasFilters, isFalse);
    expect(cleared.sort, SortMode.priceLowHigh);
    expect(cleared.pageSize, 12);
  });
}
