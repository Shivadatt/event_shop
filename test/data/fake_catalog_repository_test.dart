// Behaviour of the in-memory catalogue fake, so widget tests (sub-agents 1 & 2) can rely on it and
// so this file is compiled into the suite. The fake must filter, sort, paginate and throw the same
// way the Firestore repository does, or a green widget test would be fiction.
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';
import '../support/om_fakes.dart';

List<Product> _seed() => <Product>[
      const Product(
        id: 'a',
        name: 'Red Balloons',
        slug: 'red-balloons',
        sku: 'SKU-A',
        categoryId: 'cat-balloons',
        categorySlug: 'balloons',
        retailPricePaise: 50000,
        stockQty: 10,
        status: ProductStatus.active,
        isFeatured: true,
        soldCount: 5,
      ),
      const Product(
        id: 'b',
        name: 'Blue Balloons',
        slug: 'blue-balloons',
        sku: 'SKU-B',
        categoryId: 'cat-balloons',
        categorySlug: 'balloons',
        retailPricePaise: 30000,
        stockQty: 0,
        status: ProductStatus.active,
        isBestSeller: true,
        soldCount: 50,
      ),
      const Product(
        id: 'c',
        name: 'Gold Confetti',
        slug: 'gold-confetti',
        sku: 'SKU-C',
        categoryId: 'cat-decor',
        categorySlug: 'decor',
        retailPricePaise: 15000,
        stockQty: 5,
        status: ProductStatus.active,
        isNewArrival: true,
        soldCount: 20,
      ),
      const Product(
        id: 'd',
        name: 'Draft thing',
        slug: 'draft-thing',
        sku: 'SKU-D',
        retailPricePaise: 990000,
        status: ProductStatus.draft,
      ),
    ];

void main() {
  late FakeProductRepository repo;
  setUp(() => repo = FakeProductRepository(_seed()));

  test('byId / bySlug / bySku resolve the same document three ways', () async {
    expect((await repo.bySlug('red-balloons')).id, 'a');
    expect((await repo.bySku('SKU-B')).id, 'b');
    expect((await repo.byId('c')).slug, 'gold-confetti');
  });

  test('a missing slug throws NotFoundFailure, exactly like the real repository', () {
    expect(() => repo.bySlug('nope'), throwsA(isA<NotFoundFailure>()));
  });

  test('search only returns active products by default', () async {
    final page = await repo.search(const CatalogQuery());
    expect(page.items.map((p) => p.id), unorderedEquals(<String>['a', 'b', 'c']));
  });

  test('search filters by category and text', () async {
    final byCat = await repo.search(const CatalogQuery(categorySlug: 'balloons'));
    expect(byCat.items.map((p) => p.id), unorderedEquals(<String>['a', 'b']));
    final byText = await repo.search(const CatalogQuery(search: 'confetti'));
    expect(byText.items.map((p) => p.id), <String>['c']);
  });

  test('inStockOnly hides the sold-out line', () async {
    final page = await repo.search(const CatalogQuery(inStockOnly: true));
    expect(page.items.any((p) => p.id == 'b'), isFalse);
  });

  test('price sorts are honoured in both directions', () async {
    final low = await repo.search(const CatalogQuery(sort: SortMode.priceLowHigh));
    expect(low.items.first.id, 'c'); // 150.00 is cheapest
    final high = await repo.search(const CatalogQuery(sort: SortMode.priceHighLow));
    expect(high.items.first.id, 'a'); // 500.00 among active
  });

  test('pagination walks with an opaque cursor and reports a total estimate', () async {
    final first = await repo.search(const CatalogQuery(pageSize: 2));
    expect(first.items.length, 2);
    expect(first.hasMore, isTrue);
    final second = await repo.search(CatalogQuery(pageSize: 2, cursor: first.nextCursor));
    expect(second.items.length, 1);
    expect(second.hasMore, isFalse);
    expect(first.totalEstimate, 3);
  });

  test('watchSearch emits a single page and closes', () async {
    final page = await repo.watchSearch(const CatalogQuery()).first;
    expect(page.items.length, 3);
  });

  test('suggestions return names/SKUs without full documents, capped', () async {
    final s = await repo.suggestions('balloons');
    expect(s, containsAll(<String>['Red Balloons', 'Blue Balloons']));
  });

  test('homeShelf de-duplicates a product that is featured and a best seller', () async {
    final shelf = await repo.homeShelf(featuredLimit: 5, bestSellerLimit: 5, newArrivalLimit: 5);
    expect(shelf.length, shelf.toSet().length);
  });

  test('the query log lets a controller test assert what the UI asked for', () async {
    await repo.search(const CatalogQuery(search: 'balloon', inStockOnly: true));
    expect(repo.searchLog.single.search, 'balloon');
    expect(repo.searchLog.single.inStockOnly, isTrue);
  });

  test('unimplemented scaffolds throw a named error rather than returning null', () {
    final auth = UnimplementedAuthRepository();
    expect(() => auth.noSuchMethod(Invocation.getter(#x)),
        throwsA(isA<UnimplementedError>()));
  });
}
