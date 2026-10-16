/// Hand-written repository fakes for widget tests.
///
/// The storefront and admin screens (sub-agents 1 and 2) render through controller -> repository
/// *interface*, so a widget test only needs an object that satisfies that interface — never Firebase
/// or Supabase. Two flavours live here:
///
/// * **Concrete, seedable** fakes (`FakeProductRepository`, `FakeCategoryRepository`) implement the
///   real in-memory behaviour — filtering, sorting, pagination, not-found — so a product grid or
///   listing page test exercises the same code paths it would against Firestore.
/// * **Scaffold** fakes (`Unimplemented*Repository`) forward every method through `noSuchMethod` and
///   throw a named `UnimplementedError`. A screen under test mixes them in and overrides only the
///   one or two reads it actually calls, so a test never silently depends on a fake doing more than
///   it was written to do.
///
/// These are *test* fakes, not the `UnconfiguredMediaRepository` production stand-in; they never
/// fabricate a healthy backend outside a `test()` body.
library;

import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/data/repositories/media_repository.dart';
import 'package:om_events/data/repositories/order_repository.dart';

/// Turns a member name Symbol into a readable method name for the "you forgot to fake this" error.
String _memberName(Symbol symbol) {
  final text = symbol.toString();
  final start = text.indexOf('"');
  final end = text.lastIndexOf('"');
  return (start >= 0 && end > start) ? text.substring(start + 1, end) : text;
}

/// Base for fakes that implement an interface but only back the methods a test opts into.
///
/// Every un-overridden call fails loudly and names itself, which is far more useful in a red test
/// than a `null` returned where a `Future<Product>` was expected.
abstract class UnimplementedRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '${runtimeType} does not fake ${_memberName(invocation.memberName)}. '
      'Override it in the test or extend this fake.',
    );
  }
}

/// A catalogue backed by a fixed list, so `search`/`bySlug`/`byId` behave like the real repository.
///
/// Sorting and pagination mirror the contract: `SortMode` orders by the same fields the Firestore
/// query would, and an opaque cursor is the index of the next page.
final class FakeProductRepository implements ProductRepository {
  FakeProductRepository([List<Product>? products])
      : _products = <Product>[...?products];

  final List<Product> _products;

  /// Records what the UI asked for, so a test can assert the controller issued the right query.
  final List<CatalogQuery> searchLog = <CatalogQuery>[];

  bool throwNotFound = false;

  void seed(Iterable<Product> products) {
    _products
      ..clear()
      ..addAll(products);
  }

  Iterable<Product> get all => _products;

  @override
  Future<Product> byId(String id) async {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    throw NotFoundFailure('No product with id "$id" in the fake catalogue.');
  }

  @override
  Future<Product> bySlug(String slug) async {
    for (final product in _products) {
      if (product.pathSlug == slug) return product;
    }
    throw NotFoundFailure('No product with slug "$slug" in the fake catalogue.');
  }

  @override
  Future<Product> bySku(String sku) async {
    for (final product in _products) {
      if (product.sku == sku) return product;
    }
    throw NotFoundFailure('No product with SKU "$sku" in the fake catalogue.');
  }

  @override
  Future<List<Product>> byIds(List<String> ids) async {
    final wanted = ids.toSet();
    return _products.where((p) => wanted.contains(p.id)).toList(growable: false);
  }

  @override
  Future<PagedResult<Product>> search(CatalogQuery query) async {
    searchLog.add(query);
    if (throwNotFound) throw const NotFoundFailure();
    return _paginate(_apply(query), query);
  }

  @override
  Stream<PagedResult<Product>> watchSearch(CatalogQuery query) =>
      Stream<PagedResult<Product>>.value(_paginate(_apply(query), query));

  @override
  Future<List<Product>> homeShelf({
    required int featuredLimit,
    required int bestSellerLimit,
    required int newArrivalLimit,
  }) async {
    final shelf = <Product>[
      ..._products.where((p) => p.isFeatured).take(featuredLimit),
      ..._products.where((p) => p.isBestSeller).take(bestSellerLimit),
      ..._products.where((p) => p.isNewArrival).take(newArrivalLimit),
    ];
    // De-duplicate by id while preserving order — a product can be featured *and* a best seller.
    final seen = <String>{};
    return shelf.where((p) => seen.add(p.id)).toList(growable: false);
  }

  @override
  Future<List<Product>> relatedTo(Product product, {int limit = 8}) async {
    final related = _products
        .where((p) => p.id != product.id && p.categoryId == product.categoryId)
        .take(limit)
        .toList(growable: false);
    if (related.isNotEmpty) return related;
    return _products
        .where((p) => p.id != product.id)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<String>> suggestions(String term, {int limit = 8}) async {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return const <String>[];
    final matches = <String>{};
    for (final p in _products) {
      if (p.name.toLowerCase().contains(needle)) matches.add(p.name);
      if (p.sku.toLowerCase().contains(needle)) matches.add(p.sku);
      if (matches.length >= limit) break;
    }
    return matches.take(limit).toList(growable: false);
  }

  @override
  Future<int> availableStock(String productId, {String? variantId}) async {
    for (final p in _products) {
      if (p.id == productId) return p.stockQty;
    }
    return 0;
  }

  List<Product> _apply(CatalogQuery query) {
    final needle = query.search.trim().toLowerCase();
    var results = _products.where((p) {
      if (p.status != query.status) return false;
      if (needle.isNotEmpty &&
          !p.name.toLowerCase().contains(needle) &&
          !p.sku.toLowerCase().contains(needle) &&
          !p.keywords.any((k) => k.toLowerCase().contains(needle))) {
        return false;
      }
      if (query.categoryId != null && p.categoryId != query.categoryId) return false;
      if (query.categorySlug != null && p.categorySlug != query.categorySlug) return false;
      if (query.inStockOnly && !p.isInStock) return false;
      if (query.featuredOnly && !p.isFeatured) return false;
      if (query.wholesaleOnly != null && p.isWholesaleOnly != query.wholesaleOnly) return false;
      final min = query.minPricePaise;
      final max = query.maxPricePaise;
      if (min != null && p.basePricePaise < min) return false;
      if (max != null && p.basePricePaise > max) return false;
      if (query.tags.isNotEmpty && p.tags.intersection(query.tags.toSet()).isEmpty) return false;
      return true;
    }).toList();

    switch (query.sort) {
      case SortMode.priceLowHigh:
        results.sort((a, b) => a.basePricePaise.compareTo(b.basePricePaise));
      case SortMode.priceHighLow:
        results.sort((a, b) => b.basePricePaise.compareTo(a.basePricePaise));
      case SortMode.newest:
        results.sort((a, b) => (b.createdAt ?? DateTime(1970))
            .compareTo(a.createdAt ?? DateTime(1970)));
      case SortMode.bestSelling:
        results.sort((a, b) => b.soldCount.compareTo(a.soldCount));
      case SortMode.rating:
        results.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
      case SortMode.relevance:
        break;
    }
    return results;
  }

  PagedResult<Product> _paginate(List<Product> items, CatalogQuery query) {
    final start = int.tryParse(query.cursor ?? '') ?? 0;
    final size = query.pageSize < 1 ? items.length : query.pageSize;
    final page = items.skip(start).take(size).toList(growable: false);
    final next = start + page.length;
    return PagedResult<Product>(
      items: page,
      nextCursor: next < items.length ? '$next' : null,
      totalEstimate: items.length,
    );
  }
}

final class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository([List<Category>? categories])
      : _categories = <Category>[...?categories];

  final List<Category> _categories;

  void seed(Iterable<Category> categories) {
    _categories
      ..clear()
      ..addAll(categories);
  }

  @override
  Future<List<Category>> tree() async {
    final sorted = [..._categories]
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    return sorted;
  }

  @override
  Future<Category> byId(String id) async {
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    throw NotFoundFailure('No category with id "$id" in the fake catalogue.');
  }

  @override
  Future<Category> bySlug(String slug) async {
    for (final category in _categories) {
      if (category.pathSlug == slug) return category;
    }
    throw NotFoundFailure('No category with slug "$slug" in the fake catalogue.');
  }

  @override
  Future<List<Category>> childrenOf(String? parentId) async => _categories
      .where((c) => (c.parentId ?? '') == (parentId ?? ''))
      .toList(growable: false);
}

/// Scaffolds — override only what a test exercises. Named `Unimplemented*` so a bare use is an
/// obvious bug rather than a mysterious silent success.
final class UnimplementedAuthRepository extends UnimplementedRepository
    implements AuthRepository {
  UnimplementedAuthRepository();
}

final class UnimplementedVariantRepository extends UnimplementedRepository
    implements VariantRepository {
  UnimplementedVariantRepository();
}

final class UnimplementedCouponRepository extends UnimplementedRepository
    implements CouponRepository {
  UnimplementedCouponRepository();
}

final class UnimplementedOrderRepository extends UnimplementedRepository
    implements OrderRepository {
  UnimplementedOrderRepository();
}

final class UnimplementedAccountRepository extends UnimplementedRepository
    implements AccountRepository {
  UnimplementedAccountRepository();
}

final class UnimplementedAddressRepository extends UnimplementedRepository
    implements AddressRepository {
  UnimplementedAddressRepository();
}

final class UnimplementedWishlistRepository extends UnimplementedRepository
    implements WishlistRepository {
  UnimplementedWishlistRepository();
}

final class UnimplementedReviewRepository extends UnimplementedRepository
    implements ReviewRepository {
  UnimplementedReviewRepository();
}

final class UnimplementedAdminRepository extends UnimplementedRepository
    implements AdminRepository {
  UnimplementedAdminRepository();
}

final class UnimplementedMediaRepository extends UnimplementedRepository
    implements MediaRepository {
  UnimplementedMediaRepository();
}
