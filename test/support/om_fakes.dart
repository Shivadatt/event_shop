/// Hand-written repository fakes for widget tests.
///
/// The storefront and admin screens (sub-agents 1 and 2) render through controller -> repository
/// *interface*, so a widget test only needs an object that satisfies that interface — never Firebase
/// or Supabase. Two flavours live here:
///
/// * **Concrete, seedable** fakes (`FakeProductRepository`, `FakeCategoryRepository`,
///   `FakeAdminRepository`) implement the real in-memory behaviour — filtering, sorting,
///   pagination, not-found, and the admin refusal rules — so a product grid, listing page or admin
///   panel test exercises the same code paths it would against Firestore. `FakeAdminRepository`
///   backs only the privileged paths tests drive and records every call; anything else still
///   throws, and each `fail*` flag makes the matching privileged call fail.
/// * **Scaffold** fakes (`Unimplemented*Repository`) forward every method through `noSuchMethod` and
///   throw a named `UnimplementedError`. A screen under test mixes them in and overrides only the
///   one or two reads it actually calls, so a test never silently depends on a fake doing more than
///   it was written to do.
///
/// These are *test* fakes, not the `UnconfiguredMediaRepository` production stand-in; they never
/// fabricate a healthy backend outside a `test()` body.
library;

import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/wholesale.dart';
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
      '$runtimeType does not fake ${_memberName(invocation.memberName)}. '
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
    final results = _products.where((p) {
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
      if (query.tags.isNotEmpty &&
          p.tags.toSet().intersection(query.tags.toSet()).isEmpty) {
        return false;
      }
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

/// The privileged admin surface, backed by in-memory stores instead of the admin Cloud Functions.
///
/// Only the paths an admin test actually drives are real here: the category write path
/// (`saveCategory`/`deleteCategory`), the contract-price read (`listCustomerPrices`), the order and
/// audit lists with their optional filters, and the three server-summed reports. Everything else
/// still falls through to [UnimplementedRepository], so a screen that quietly starts depending on
/// `dashboard()` fails loudly instead of reading a fabricated number.
///
/// Two things make this a fake rather than a lying stub:
///  * every call is recorded ([calls] plus the per-method capture lists), so a test can assert what
///    the screen asked for, not only what it got;
///  * each `fail*` flag throws the failure the real privileged path throws, so the error branch of
///    a destructive write is testable. Nothing here returns `null` or an empty list to paper over a
///    signature: an unknown id raises [NotFoundFailure] and a non-empty category raises
///    [ConflictFailure], exactly as `adminCategoryDelete` documents.
final class FakeAdminRepository extends UnimplementedRepository implements AdminRepository {
  FakeAdminRepository({
    List<Category>? categories,
    List<Product>? products,
    List<Order>? orders,
    List<CustomerPriceOverride>? overrides,
    List<AuditLog>? logs,
  })  : _categories = <Category>[...?categories],
        _products = <Product>[...?products],
        _orders = <Order>[...?orders],
        _overrides = <CustomerPriceOverride>[...?overrides],
        _logs = <AuditLog>[...?logs];

  final List<Category> _categories;
  final List<Product> _products;
  final List<Order> _orders;
  final List<CustomerPriceOverride> _overrides;
  final List<AuditLog> _logs;

  Iterable<Category> get categories => _categories;
  Iterable<Product> get products => _products;
  Iterable<Order> get orders => _orders;
  Iterable<CustomerPriceOverride> get priceOverrides => _overrides;
  Iterable<AuditLog> get auditLogEntries => _logs;

  void seedCategories(Iterable<Category> categories) {
    _categories
      ..clear()
      ..addAll(categories);
  }

  void seedProducts(Iterable<Product> products) {
    _products
      ..clear()
      ..addAll(products);
  }

  void seedOrders(Iterable<Order> orders) {
    _orders
      ..clear()
      ..addAll(orders);
  }

  void seedOverrides(Iterable<CustomerPriceOverride> overrides) {
    _overrides
      ..clear()
      ..addAll(overrides);
  }

  void seedLogs(Iterable<AuditLog> logs) {
    _logs
      ..clear()
      ..addAll(logs);
  }

  /// Every recorded call, in order, as `method:arguments` — the coarse log a test can assert on
  /// when it only cares that the privileged path was hit.
  final List<String> calls = <String>[];

  /// The exact payloads handed to [saveCategory], including rejected ones, so a test can prove the
  /// screen sent the row it displayed rather than a mutated copy.
  final List<Category> savedCategoryPayloads = <Category>[];
  final List<String> deletedCategoryIds = <String>[];
  final List<String> customerValueRequests = <String>[];
  final List<({DateTime from, DateTime to})> salesByDayRequests = <({DateTime from, DateTime to})>[];
  final List<int> topCustomerLimits = <int>[];
  final List<({String? productId, String? uid})> customerPriceRequests =
      <({String? productId, String? uid})>[];
  final List<({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    DeliveryMode? deliveryMode,
    String? customerId,
    String? search,
  })> listOrdersRequests = <({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    DeliveryMode? deliveryMode,
    String? customerId,
    String? search,
  })>[];
  final List<({String? entityType, String? action, String? actorUid, DateTime? from, DateTime? to})>
      auditLogRequests =
      <({String? entityType, String? action, String? actorUid, DateTime? from, DateTime? to})>[];

  /// Failure injection, one flag per privileged path.
  bool failCategoryWrites = false;
  bool failCategoryDeletes = false;
  bool failCustomerPriceReads = false;
  bool failReportReads = false;
  bool failAuditReads = false;
  bool failOrderList = false;

  @override
  Future<Category> saveCategory(Category category) async {
    calls.add('saveCategory:${category.id}');
    savedCategoryPayloads.add(category);
    if (failCategoryWrites) {
      throw const ServerFailure('adminCategorySave refused the write.');
    }
    if (category.name.trim().isEmpty) {
      throw ValidationFailure('Category "${category.id}" has no name.', field: 'name');
    }
    final index = _categories.indexWhere((c) => c.id == category.id);
    if (index >= 0) {
      _categories[index] = category;
    } else {
      _categories.add(category);
    }
    return category;
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    calls.add('deleteCategory:$categoryId');
    deletedCategoryIds.add(categoryId);
    if (failCategoryDeletes) {
      throw const ServerFailure('adminCategoryDelete refused the write.');
    }
    final index = _categories.indexWhere((c) => c.id == categoryId);
    if (index < 0) {
      throw NotFoundFailure('No category with id "$categoryId" in the fake catalogue.');
    }
    final children =
        _categories.where((c) => c.parentId == categoryId).toList(growable: false).length;
    final attached = _products
        .where((p) => p.categoryId == categoryId && p.status != ProductStatus.archived)
        .toList(growable: false)
        .length;
    if (children > 0 || attached > 0) {
      throw ConflictFailure(
        message: 'Category "$categoryId" still has $children subcategory(s) and '
            '$attached live product(s).',
        code: 'category-not-empty',
        details: <String, Object?>{'children': children, 'products': attached},
      );
    }
    _categories.removeAt(index);
  }

  @override
  Future<List<CustomerPriceOverride>> listCustomerPrices({
    String? productId,
    String? uid,
  }) async {
    calls.add('listCustomerPrices:${productId ?? '*'}/${uid ?? '*'}');
    customerPriceRequests.add((productId: productId, uid: uid));
    if (failCustomerPriceReads) {
      throw const PermissionFailure(
        'customerPrices is read-forbidden to clients; only the admin callable may list it.',
      );
    }
    return _overrides
        .where((o) =>
            (productId == null || o.productId == productId) && (uid == null || o.uid == uid))
        .toList(growable: false);
  }

  @override
  Future<PagedResult<Order>> listOrders({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    DeliveryMode? deliveryMode,
    String? customerId,
    String? search,
    DateTime? from,
    DateTime? to,
    int pageSize = 25,
    String? cursor,
  }) async {
    calls.add('listOrders:${customerId ?? '*'}/${deliveryMode?.code ?? '*'}');
    listOrdersRequests.add((
      status: status,
      paymentStatus: paymentStatus,
      deliveryMode: deliveryMode,
      customerId: customerId,
      search: search,
    ));
    if (failOrderList) throw const NetworkFailure();
    final needle = (search ?? '').trim().toLowerCase();
    final matched = _orders.where((o) {
      if (status != null && o.status != status) return false;
      if (paymentStatus != null && o.paymentStatus != paymentStatus) return false;
      if (deliveryMode != null && o.deliveryMode != deliveryMode) return false;
      if (customerId != null && o.userId != customerId) return false;
      final at = o.createdAt;
      if (from != null && (at == null || at.isBefore(from))) return false;
      if (to != null && (at == null || at.isAfter(to))) return false;
      if (needle.isNotEmpty &&
          !o.orderNumber.toLowerCase().contains(needle) &&
          !o.contactPhone.toLowerCase().contains(needle) &&
          !o.userId.toLowerCase().contains(needle)) {
        return false;
      }
      return true;
    }).toList(growable: false);
    return _page(matched, pageSize, cursor);
  }

  @override
  Future<PagedResult<AuditLog>> auditLogs({
    String? entityType,
    String? action,
    String? actorUid,
    DateTime? from,
    DateTime? to,
    int pageSize = 50,
    String? cursor,
  }) async {
    calls.add('auditLogs:${entityType ?? '*'}/${action ?? '*'}/${actorUid ?? '*'}');
    auditLogRequests.add((
      entityType: entityType,
      action: action,
      actorUid: actorUid,
      from: from,
      to: to,
    ));
    if (failAuditReads) {
      throw const PermissionFailure('The audit log is readable by staff roles only.');
    }
    final matched = _logs.where((log) {
      if (entityType != null && log.entityType != entityType) return false;
      if (action != null && log.action != action) return false;
      if (actorUid != null && log.actorUid != actorUid) return false;
      final at = log.createdAt;
      if (from != null && (at == null || at.isBefore(from))) return false;
      if (to != null && (at == null || at.isAfter(to))) return false;
      return true;
    }).toList(growable: false);
    return _page(matched, pageSize, cursor);
  }

  @override
  Future<List<ReportRow>> salesByDay({required DateTime from, required DateTime to}) async {
    calls.add('salesByDay:$from/$to');
    salesByDayRequests.add((from: from, to: to));
    if (failReportReads) throw const ServerFailure('adminSalesByDay is unavailable.');
    final byDay = <String, List<Order>>{};
    for (final order in _orders) {
      final at = order.createdAt;
      if (at == null || !_earnsRevenue(order)) continue;
      final day = at.toUtc();
      if (day.isBefore(from.toUtc()) || day.isAfter(to.toUtc())) continue;
      byDay.putIfAbsent(_dayKey(day), () => <Order>[]).add(order);
    }
    final days = byDay.keys.toList()..sort();
    return <ReportRow>[
      for (final day in days) _rowFor(day, day, byDay[day]!),
    ];
  }

  @override
  Future<List<ReportRow>> topCustomers({int limit = 20}) async {
    calls.add('topCustomers:$limit');
    topCustomerLimits.add(limit);
    if (failReportReads) throw const ServerFailure('adminTopCustomers is unavailable.');
    final byCustomer = <String, List<Order>>{};
    for (final order in _orders) {
      if (!_earnsRevenue(order) || order.userId.isEmpty) continue;
      byCustomer.putIfAbsent(order.userId, () => <Order>[]).add(order);
    }
    final rows = <ReportRow>[
      for (final entry in byCustomer.entries) _rowFor(entry.key, entry.key, entry.value),
    ]..sort((a, b) {
      final byRevenue = b.revenuePaise.compareTo(a.revenuePaise);
      return byRevenue != 0 ? byRevenue : a.key.compareTo(b.key);
    });
    return rows.take(limit < 1 ? 0 : limit).toList(growable: false);
  }

  @override
  Future<ReportRow> customerValue(String uid) async {
    calls.add('customerValue:$uid');
    customerValueRequests.add(uid);
    if (failReportReads) throw const ServerFailure('adminCustomerValue is unavailable.');
    final owned = _orders
        .where((o) => o.userId == uid && _earnsRevenue(o))
        .toList(growable: false);
    if (owned.isEmpty) {
      throw NotFoundFailure('Customer "$uid" has no revenue-bearing order in the fake store.');
    }
    return _rowFor(uid, uid, owned);
  }

  /// Cancelled and refunded orders carry no lifetime revenue — the same rule the server-side
  /// aggregators apply, so a fake can never make a lost month look profitable.
  static bool _earnsRevenue(Order order) =>
      order.status != OrderStatus.cancelled && order.status != OrderStatus.refunded;

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// Summed exactly like `adminSalesByDay`: revenue is the server-rounded grand total, units are
  /// line quantities. `costPaise` is left at zero on purpose — the fake has no cost ledger, and
  /// [ReportRow.hasCostData] then correctly reports that margin is unknown.
  static ReportRow _rowFor(String key, String label, List<Order> orders) {
    var revenue = 0;
    var units = 0;
    var discount = 0;
    var refunded = 0;
    for (final order in orders) {
      revenue += order.totals.grandTotalPaise;
      units += order.totalQty;
      discount += order.totals.slabDiscountPaise + order.totals.couponDiscountPaise;
      refunded += order.totals.refundedPaise;
    }
    return ReportRow(
      key: key,
      label: label,
      units: units,
      revenuePaise: revenue,
      discountPaise: discount,
      orderCount: orders.length,
      refundedPaise: refunded,
    );
  }

  /// Opaque index cursor, matching [FakeProductRepository] and the contract.
  PagedResult<T> _page<T>(List<T> items, int pageSize, String? cursor) {
    final start = int.tryParse(cursor ?? '') ?? 0;
    final size = pageSize < 1 ? items.length : pageSize;
    final page = items.skip(start).take(size).toList(growable: false);
    final next = start + page.length;
    return PagedResult<T>(
      items: page,
      nextCursor: next < items.length ? '$next' : null,
      totalEstimate: items.length,
    );
  }
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
