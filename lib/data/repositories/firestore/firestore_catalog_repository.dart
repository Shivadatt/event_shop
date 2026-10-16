import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/firebase/firebase_backend.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/providers/catalog_query_builder.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/data/providers/firestore_converters.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';

/// Shared category resolution for the catalogue repositories. `ProductRepository`, `CategoryRepository`
/// and `VariantRepository` all declare `byId`/`bySlug` with *different* return types, so they must be
/// separate classes; the sub-tree expansion and the active-category cache are pulled in here.
final class _CategoryResolver {
  List<Category>? _cache;
  DateTime? _cacheAt;

  Future<List<Category>> activeCategories() async {
    final now = DateTime.now();
    final cache = _cache;
    if (cache != null && _cacheAt != null && now.difference(_cacheAt!) < const Duration(minutes: 5)) {
      return cache;
    }
    final snap = await Collections.categories_
        .where('isActive', isEqualTo: true)
        .orderBy('order')
        .get();
    final categories = FirestoreConverters.categories(snap.docs);
    _cache = categories;
    _cacheAt = now;
    return categories;
  }

  Future<List<String>> resolveCategoryIds(CatalogQuery query) async {
    if (query.categorySlug == null || query.categorySlug!.isEmpty) {
      return query.categoryId == null ? const <String>[] : <String>[query.categoryId!];
    }
    final all = await activeCategories();
    final root = all.where((c) => c.pathSlug == query.categorySlug).firstOrNull;
    if (root == null) return <String>[query.categorySlug!];
    if (!query.includeSubCategories) return <String>[root.id];
    final byParent = <String, List<Category>>{};
    for (final c in all) {
      byParent.putIfAbsent(c.parentId ?? '', () => <Category>[]).add(c);
    }
    final ids = <String>[root.id];
    final queue = <String>[root.id];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final child in byParent[current] ?? const <Category>[]) {
        ids.add(child.id);
        queue.add(child.id);
      }
    }
    return ids;
  }

  /// When the sub-tree fans out to several categories the slug filter is replaced by an `in` over
  /// ids, so the single-inequality query stays legal.
  CatalogQuery clearSlugIfUsingIds(CatalogQuery query, List<String> categoryIds) {
    if (categoryIds.length <= 1) return query;
    return CatalogQuery(
      search: query.search,
      categoryId: query.categoryId,
      includeSubCategories: false,
      tags: query.tags,
      colors: query.colors,
      sizes: query.sizes,
      minPricePaise: query.minPricePaise,
      maxPricePaise: query.maxPricePaise,
      inStockOnly: query.inStockOnly,
      wholesaleOnly: query.wholesaleOnly,
      featuredOnly: query.featuredOnly,
      status: query.status,
      sort: query.sort,
      pageSize: query.pageSize,
      cursor: query.cursor,
    );
  }
}

/// Reads the public product catalogue. Wholesale entitlement and cost-price visibility are threaded
/// through so retail shoppers never receive wholesale-only rows.
final class FirestoreProductRepository implements ProductRepository {
  FirestoreProductRepository() : _resolver = _CategoryResolver();

  final _CategoryResolver _resolver;

  @override
  Future<Product> byId(String id) async {
    final snap = await Collections.product(id).get();
    if (!snap.exists) throw const NotFoundFailure('That product is no longer available.');
    return FirestoreConverters.product(snap);
  }

  @override
  Future<Product> bySlug(String slug) async {
    final snap = await Collections.products_
        .where('slug', isEqualTo: slug)
        .where('status', isEqualTo: ProductStatus.active.code)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) throw const NotFoundFailure('That product page could not be found.');
    return FirestoreConverters.product(snap.docs.first);
  }

  @override
  Future<Product> bySku(String sku) async {
    final snap = await Collections.products_
        .where('sku', isEqualTo: sku)
        .where('status', isEqualTo: ProductStatus.active.code)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) throw const NotFoundFailure('No product with that SKU.');
    return FirestoreConverters.product(snap.docs.first);
  }

  @override
  Future<List<Product>> byIds(List<String> ids) async {
    if (ids.isEmpty) return const <Product>[];
    final out = <Product>[];
    // Firestore caps `in` at 30 values, so ids are chunked.
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await Collections.products_.where(FieldPath.documentId, whereIn: chunk).get();
      out.addAll(FirestoreConverters.products(snap.docs));
    }
    return out;
  }

  @override
  Future<PagedResult<Product>> search(CatalogQuery query) async {
    final categoryIds = await _resolver.resolveCategoryIds(query);
    final effective = _resolver.clearSlugIfUsingIds(query, categoryIds);
    final q = CatalogQueryBuilder.build(effective, categoryIds: categoryIds);
    final snap = await q.limit(query.pageSize + 1).get();
    return _page(snap, effective);
  }

  @override
  Stream<PagedResult<Product>> watchSearch(CatalogQuery query) {
    final effective = _resolver.clearSlugIfUsingIds(query, const <String>[]);
    final q = CatalogQueryBuilder.build(
      query.copyWith(cursor: null),
      categoryIds: const <String>[],
    ).limit(query.pageSize + 1);
    return q.snapshots().map((snap) => _page(snap, effective));
  }

  PagedResult<Product> _page(QuerySnapshot<Map<String, dynamic>> snap, CatalogQuery query) {
    final docs = snap.docs;
    final hasMore = docs.length > query.pageSize;
    final page = hasMore ? docs.sublist(0, query.pageSize) : docs;
    // Re-apply the client-side filters the server could not express in one legal query.
    final items = page
        .map(FirestoreConverters.product)
        .where((p) => CatalogQueryBuilder.matchesClient(p, query))
        .toList(growable: false);
    final last = page.isEmpty ? null : page.last;
    return PagedResult<Product>(
      items: items,
      nextCursor: hasMore && last != null ? CatalogQueryBuilder.encodeCursor(last, query.sort) : null,
    );
  }

  @override
  Future<List<Product>> homeShelf({
    required int featuredLimit,
    required int bestSellerLimit,
    required int newArrivalLimit,
  }) async {
    final results = await Future.wait(<Future<List<Product>>>[
      _flagged('isFeatured', featuredLimit, secondary: 'createdAt', descending: true),
      _flagged('isBestSeller', bestSellerLimit, secondary: 'soldCount'),
      _flagged('isNewArrival', newArrivalLimit, secondary: 'createdAt', descending: true),
    ]);
    final seen = <String>{};
    final merged = <Product>[];
    for (final list in results) {
      for (final product in list) {
        if (seen.add(product.id)) merged.add(product);
      }
    }
    return merged;
  }

  Future<List<Product>> _flagged(String flag, int limit, {required String secondary, bool descending = false}) async {
    final snap = await Collections.products_
        .where('status', isEqualTo: ProductStatus.active.code)
        .where(flag, isEqualTo: true)
        .orderBy(secondary, descending: descending)
        .limit(limit)
        .get();
    return FirestoreConverters.products(snap.docs);
  }

  @override
  Future<List<Product>> relatedTo(Product product, {int limit = 8}) async {
    final snap = await Collections.products_
        .where('status', isEqualTo: ProductStatus.active.code)
        .where('categoryId', isEqualTo: product.categoryId)
        .orderBy('soldCount', descending: true)
        .limit(limit + 1)
        .get();
    return FirestoreConverters.products(snap.docs)
        .where((p) => p.id != product.id)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<String>> suggestions(String term, {int limit = 8}) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const <String>[];
    final snap = await Collections.products_
        .where('status', isEqualTo: ProductStatus.active.code)
        .orderBy('name')
        .where('name', isGreaterThanOrEqualTo: trimmed.toUpperCase())
        .where('name', isLessThanOrEqualTo: '${trimmed.toUpperCase()}\uf8ff')
        .limit(limit)
        .get();
    return FirestoreConverters.products(snap.docs).map((p) => p.name).toList(growable: false);
  }

  @override
  Future<int> availableStock(String productId, {String? variantId}) async {
    if (variantId == null) {
      final snap = await Collections.product(productId).get();
      if (!snap.exists) throw const NotFoundFailure();
      return FirestoreConverters.product(snap).stockQty;
    }
    // Variant stock lives in a cost-bearing doc that is staff-read-only; the stripped callable still
    // reports stockQty for the checkout pre-check without exposing cost price.
    final data = await FirebaseBackend.call('variantListForProduct', <String, Object?>{'productId': productId});
    final variants = (data['variants'] as List<dynamic>? ?? const <dynamic>[]).cast<Map<String, dynamic>>();
    final match = variants.where((v) => v['id'] == variantId).firstOrNull;
    if (match == null) throw const NotFoundFailure('Variant not found.');
    final stock = match['stockQty'];
    return stock is int ? stock : (stock as num?)?.round() ?? 0;
  }
}

final class FirestoreCategoryRepository implements CategoryRepository {
  FirestoreCategoryRepository() : _resolver = _CategoryResolver();

  final _CategoryResolver _resolver;

  @override
  Future<List<Category>> tree() => _resolver.activeCategories();

  @override
  Future<Category> byId(String id) async {
    final snap = await Collections.category(id).get();
    if (!snap.exists) throw const NotFoundFailure('Category not found.');
    return FirestoreConverters.category(snap);
  }

  @override
  Future<Category> bySlug(String slug) async {
    final snap = await Collections.categories_.where('slug', isEqualTo: slug).limit(1).get();
    if (snap.docs.isEmpty) throw const NotFoundFailure('That category does not exist.');
    return FirestoreConverters.category(snap.docs.first);
  }

  @override
  Future<List<Category>> childrenOf(String? parentId) async {
    final all = await _resolver.activeCategories();
    return all.where((c) => (c.parentId ?? '') == (parentId ?? '')).toList(growable: false);
  }
}

final class FirestoreVariantRepository implements VariantRepository {
  FirestoreVariantRepository(this._session);

  final SessionStore _session;

  @override
  Future<List<ProductVariant>> forProduct(String productId) async {
    if (_session.canSeeCostPrice) {
      // Admin/owner may read the raw variant docs (cost price included).
      final snap = await Collections.variants_
          .where('productId', isEqualTo: productId)
          .orderBy('order')
          .get();
      return FirestoreConverters.variants(snap.docs);
    }
    // Everyone else gets the cost-stripped list from the callable; rules keep the collection
    // staff-read-only so a browser query would be denied.
    final data = await FirebaseBackend.call('variantListForProduct', <String, Object?>{'productId': productId});
    final list = (data['variants'] as List<dynamic>? ?? const <dynamic>[]).cast<Map<String, dynamic>>();
    return list.map((m) => ProductVariant.fromMap(m, id: m['id'] as String? ?? '')).toList(growable: false);
  }

  @override
  Future<ProductVariant> byId(String variantId) async {
    final snap = await Collections.variant(variantId).get();
    if (!snap.exists) throw const NotFoundFailure('Variant not found.');
    return FirestoreConverters.variant(snap);
  }
}

final class FirestoreCouponRepository implements CouponRepository {
  @override
  Future<CouponQuote> quote({
    required String code,
    required List<QuoteLine> lines,
    String? uid,
  }) async {
    final data = await FirebaseBackend.call('couponsQuote', <String, Object?>{
      'code': code,
      'lines': lines.map((l) => l.toMap()).toList(),
      'uid': uid,
    });
    final couponMap = data['coupon'];
    final coupon = couponMap is Map<String, dynamic>
        ? Coupon.fromMap(couponMap, id: couponMap['id'] as String? ?? code)
        : Coupon(id: code, code: code, kind: CouponKind.percentage);
    return CouponQuote(
      coupon: coupon,
      discountPaise: (data['discountPaise'] as num?)?.round() ?? 0,
      freeShipping: data['freeShipping'] as bool? ?? false,
      reason: data['reason'] as String? ?? '',
    );
  }
}

/// Local `firstOrNull` so these files do not import `package:collection` (a transitive dep, not a
/// direct one — importing it directly would trip `depend_on_referenced_packages`).
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
