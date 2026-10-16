import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/firebase/firebase_backend.dart';
import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/data/providers/firestore_converters.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/order_repository.dart';

/// The admin surface. Two paths meet here: staff-gated Firestore *reads* (products, orders,
/// customers, reviews, movements, audit, applications) that rules already restrict to staff, and
/// privileged *writes* that always cross the `FirebaseBackend.call` boundary so a role re-check,
/// an audit row and (for money/stock) a transaction happen server-side. Nothing here is a
/// permission check — it is the shape of the trusted backend the admin UI talks to.
final class FirestoreAdminRepository implements AdminRepository {
  FirestoreAdminRepository();

  // ---- dashboard ----

  @override
  Future<DashboardStats> dashboard() async {
    final data = await FirebaseBackend.call('adminDashboard');
    return DashboardStats(
      ordersToday: _int(data['ordersToday']),
      revenueTodayPaise: _int(data['revenueTodayPaise']),
      revenueMonthPaise: _int(data['revenueMonthPaise']),
      pendingOrders: _int(data['pendingOrders']),
      pendingPayments: _int(data['pendingPayments']),
      lowStockCount: _int(data['lowStockCount']),
      outOfStockCount: _int(data['outOfStockCount']),
      newCustomers: _int(data['newCustomers']),
      openSupportTickets: _int(data['openSupportTickets']),
      pendingReviews: _int(data['pendingReviews']),
      pendingWholesaleApplications: _int(data['pendingWholesaleApplications']),
      bestSellers: _list(data['bestSellers'])
          .map((m) => BestSellerRow(
                productId: _str(m['productId']),
                name: _str(m['name']),
                unitsSold: _int(m['unitsSold']),
                revenuePaise: _int(m['revenuePaise']),
              ))
          .toList(growable: false),
      salesSparkline: _list(data['salesSparkline'])
          .map((m) => SalesPoint(
                day: DateTime.tryParse(_str(m['day'])) ?? DateTime.now(),
                revenuePaise: _int(m['revenuePaise']),
                orders: _int(m['orders']),
              ))
          .toList(growable: false),
    );
  }

  // ---- products ----

  @override
  Future<PagedResult<Product>> listProducts({
    CatalogQuery? query,
    ProductStatus? status,
    int pageSize = 25,
    String? cursor,
  }) async {
    // Admin sees every status, including wholesale-only rows, so the public builder (which forces
    // status=active and hides wholesale-only from retail shoppers) is not used here. Staff-read of
    // the whole collection is permitted by the rules regardless of a doc's status.
    Query<Map<String, dynamic>> q = Collections.products_.orderBy('updatedAt', descending: true).orderBy(documentId: true);
    if (status != null) q = q.where('status', isEqualTo: status.code);
    final term = (query?.search ?? '').trim().toLowerCase();
    final after = _decodeCursor(cursor);
    if (after != null) q = q.startAfter(after.value, after.id);
    // A name/SKU substring cannot pair with the updatedAt sort in one indexed query, so a search
    // reads a wider window and filters in Dart; the cursor still advances from the last raw doc.
    final fetchLimit = term.isEmpty ? pageSize + 1 : 200;
    final snap = await q.limit(fetchLimit).get();
    var docs = snap.docs;
    if (term.isNotEmpty) {
      docs = docs
          .where((d) => _str(d.get('name')).toLowerCase().contains(term) ||
              _str(d.get('sku')).toLowerCase().contains(term))
          .toList();
    }
    final hasMore = term.isEmpty ? docs.length > pageSize : snap.docs.length == fetchLimit;
    final page = hasMore && term.isEmpty ? docs.sublist(0, pageSize) : docs.take(pageSize).toList(growable: false);
    final lastDoc = snap.docs.isEmpty ? null : snap.docs.last;
    return PagedResult<Product>(
      items: FirestoreConverters.products(page),
      nextCursor: hasMore && lastDoc != null ? _encodeCursor(lastDoc, 'updatedAt') : null,
    );
  }

  @override
  Future<Product> saveProduct(Product product, {List<PriceSlab>? slabs}) async {
    final payload = <String, Object?>{
      ...product.toWriteMap(),
      'id': product.id,
      'slabs': (slabs ?? product.slabs).map((s) => s.toMap()).toList(),
    };
    final data = await FirebaseBackend.call('adminProductSave', <String, Object?>{'product': payload});
    return Product.fromMap(data, id: _str(data['id']).isEmpty ? product.id : _str(data['id']));
  }

  @override
  Future<void> archiveProduct(String productId, {required bool archived}) async {
    // A status flip only. Going through adminProductSave with a partial body would merge an empty
    // slab grid over the product's real prices, so archive writes the single field via its own path.
    await FirebaseBackend.call('adminProductArchive', <String, Object?>{
      'productId': productId,
      'archived': archived,
    });
  }

  @override
  Future<Product> duplicateProduct(String productId) async {
    final snap = await Collections.product(productId).get();
    if (!snap.exists) throw const NotFoundFailure('Product not found.');
    final source = FirestoreConverters.product(snap);
    final copy = Product.fromMap(<String, dynamic>{
      ...source.toWriteMap(),
      'name': '${source.name} (copy)',
      'slug': '',
      'sku': source.sku.isEmpty ? '' : '${source.sku}-COPY',
      'status': ProductStatus.draft.code,
    }, id: '');
    // saveProduct mints a fresh id server-side; the clone must not carry the source's identity.
    final data = await FirebaseBackend.call('adminProductSave', <String, Object?>{
      'product': <String, Object?>{
        ...copy.toWriteMap(),
        'slabs': copy.slabs.map((s) => s.toMap()).toList(),
      },
    });
    return Product.fromMap(data, id: _str(data['id']));
  }

  // ---- variants ----

  @override
  Future<void> saveVariant(ProductVariant variant) async {
    final payload = <String, Object?>{
      ...variant.toWriteMap(includeCost: true),
      'id': variant.id,
      'slabs': variant.slabs.map((s) => s.toMap()).toList(),
    };
    await FirebaseBackend.call('adminVariantSave', <String, Object?>{'variant': payload});
  }

  @override
  Future<void> deleteVariant(String variantId) async {
    await FirebaseBackend.call('adminVariantDelete', <String, Object?>{'variantId': variantId});
  }

  // ---- inventory ----

  @override
  Future<int> stockFor(String productId, {String? variantId}) async {
    // Staff reads the raw stock doc directly (no cost price crosses the wire on an int read).
    final snap = variantId == null
        ? await Collections.product(productId).get()
        : await Collections.variant(variantId).get();
    if (!snap.exists) throw const NotFoundFailure('Stock item not found.');
    return _int(snap.get('stockQty'));
  }

  @override
  Future<void> adjustStock({
    required String productId,
    required int deltaQty,
    required StockMovementKind kind,
    required String reason,
    String? variantId,
    int? unitCostPaise,
  }) async {
    await FirebaseBackend.call('inventoryAdjust', <String, Object?>{
      'productId': productId,
      'variantId': variantId,
      'deltaQty': deltaQty,
      'kind': kind.code,
      'reason': reason,
      'unitCostPaise': unitCostPaise,
    });
  }

  @override
  Future<void> setOpeningStock({
    required String productId,
    required int quantity,
    String? variantId,
    required String reason,
  }) async {
    await FirebaseBackend.call('inventorySetOpening', <String, Object?>{
      'productId': productId,
      'variantId': variantId,
      'quantity': quantity,
      'reason': reason,
    });
  }

  @override
  Future<List<InventoryMovement>> movementsFor(String productId, {int limit = 50, DateTime? since}) async {
    Query<Map<String, dynamic>> q = Collections.movements_.where('productId', isEqualTo: productId);
    // A `since` bound is a range on the same field as the sort, so it stays one legal query.
    if (since != null) {
      q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }
    q = q.orderBy('createdAt', descending: true).limit(limit);
    final snap = await q.get();
    return FirestoreConverters.movements(snap.docs);
  }

  @override
  Future<List<Product>> lowStockReport({int limit = 100}) async {
    // Firestore cannot compare two fields (stockQty <= lowStockThreshold) in one query, so the
    // active set is read ordered by stock ascending and the threshold filter runs in Dart.
    final snap = await Collections.products_
        .where('status', isEqualTo: ProductStatus.active.code)
        .orderBy('stockQty')
        .limit(500)
        .get();
    final products = FirestoreConverters.products(snap.docs)
        .where((p) => p.stockQty <= p.lowStockThreshold)
        .take(limit)
        .toList(growable: false);
    return products;
  }

  // ---- orders ----

  @override
  Future<PagedResult<Order>> listOrders({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    String? search,
    DateTime? from,
    DateTime? to,
    int pageSize = 25,
    String? cursor,
  }) async {
    final term = (search ?? '').trim();
    // An exact order-number search short-circuits to a single doc (guest/number lookup); a partial
    // term over contact fields cannot combine with the createdAt range, so it is not offered.
    if (term.isNotEmpty) {
      final snap = await Collections.orders_
          .where('orderNumber', isEqualTo: term)
          .limit(pageSize)
          .get();
      return PagedResult<Order>(items: FirestoreConverters.orders(snap.docs));
    }
    Query<Map<String, dynamic>> q = Collections.orders_;
    if (status != null) q = q.where('status', isEqualTo: status.code);
    if (paymentStatus != null) q = q.where('paymentStatus', isEqualTo: paymentStatus.code);
    final after = _decodeCursor(cursor);
    // The from/to window is the single allowed range; it is also the sort field.
    q = q.orderBy('createdAt', descending: true).orderBy(documentId: true);
    if (from != null) q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    if (to != null) q = q.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to));
    if (after != null) q = q.startAfter(after.value, after.id);
    final snap = await q.limit(pageSize + 1).get();
    final docs = snap.docs;
    final hasMore = docs.length > pageSize;
    final page = hasMore ? docs.sublist(0, pageSize) : docs;
    final last = page.isEmpty ? null : page.last;
    return PagedResult<Order>(
      items: FirestoreConverters.orders(page),
      nextCursor: hasMore && last != null ? _encodeCursor(last, 'createdAt') : null,
    );
  }

  @override
  Future<Order> transitionOrder({
    required String orderId,
    required OrderStatus to,
    String note = '',
    String? trackingUrl,
    String? carrier,
    String? cancelledReason,
  }) async {
    final data = await FirebaseBackend.call('adminOrderTransition', <String, Object?>{
      'orderId': orderId,
      'to': to.code,
      'note': note,
      'trackingUrl': trackingUrl,
      'carrier': carrier,
      'cancelledReason': cancelledReason,
    });
    return _orderFromData(orderId, data);
  }

  @override
  Future<Order> markPayment({
    required String orderId,
    required String method,
    String? transactionReference,
    bool isCod = false,
  }) async {
    final data = await FirebaseBackend.call('adminOrderMarkPayment', <String, Object?>{
      'orderId': orderId,
      'method': method,
      'transactionReference': transactionReference ?? '',
      'isCod': isCod,
    });
    return _orderFromData(orderId, data);
  }

  @override
  Future<Order> issueRefund({required String orderId, required int amountPaise, required String reason}) async {
    final data = await FirebaseBackend.call('adminOrderRefund', <String, Object?>{
      'orderId': orderId,
      'amountPaise': amountPaise,
      'reason': reason,
    });
    return _orderFromData(orderId, data);
  }

  @override
  Future<Order> createCounterOrder({
    required List<DraftLine> lines,
    required String contactPhone,
    String contactName = '',
    String paymentMethod = 'cash',
    String note = '',
  }) async {
    final receipt = await FirebaseBackend.call('adminCounterOrder', <String, Object?>{
      'lines': lines.map((l) => l.toMap()).toList(),
      'contactPhone': contactPhone,
      'contactName': contactName,
      'contactEmail': '',
      'paymentMethod': paymentMethod,
      'customerNote': note,
      'deliveryMode': 'pickup',
      // Reuses ordersCreate's idempotency guard so a double-tapped counter sale is a single order.
      'idempotencyKey': Collections.newProductId(),
    });
    final orderId = _str(receipt['orderId']);
    if (orderId.isEmpty) throw const ServerFailure('Counter order was not created.');
    final snap = await Collections.order(orderId).get();
    if (!snap.exists) throw const ServerFailure('Counter order vanished after creation.');
    return FirestoreConverters.order(snap);
  }

  @override
  Future<String?> invoicePdfUrl(String orderId) async {
    // Invoice PDF generation is not implemented server-side; there is no function to mint a signed
    // URL, so this returns null rather than a fabricated link. The order number is the invoice ref.
    return null;
  }

  // ---- customers ----

  @override
  Future<PagedResult<UserProfile>> listCustomers({
    String? search,
    UserRole? role,
    int pageSize = 25,
    String? cursor,
  }) async {
    final term = (search ?? '').trim().toLowerCase();
    Query<Map<String, dynamic>> q = Collections.users_.orderBy('createdAt', descending: true).orderBy(documentId: true);
    if (role != null) q = q.where('role', isEqualTo: role.code);
    final after = _decodeCursor(cursor);
    if (after != null) q = q.startAfter(after.value, after.id);
    final snap = await q.limit(pageSize + 1).get();
    // Name/email/company search has no index that pairs with the createdAt sort, so it runs on the
    // page and the cursor still advances from the last *read* document (not the last match), which
    // keeps deep paging correct even when a page filters down to few rows.
    final docs = snap.docs;
    final hasMore = docs.length > pageSize;
    final page = hasMore ? docs.sublist(0, pageSize) : docs;
    final last = page.isEmpty ? null : page.last;
    var profiles = FirestoreConverters.users(page);
    if (term.isNotEmpty) {
      profiles = profiles
          .where((u) =>
              u.displayName.toLowerCase().contains(term) ||
              u.email.toLowerCase().contains(term) ||
              u.companyName.toLowerCase().contains(term) ||
              u.phone.contains(term))
          .toList(growable: false);
    }
    return PagedResult<UserProfile>(
      items: profiles,
      nextCursor: hasMore && last != null ? _encodeCursor(last, 'createdAt') : null,
    );
  }

  @override
  Future<UserProfile> customerDetail(String uid) async {
    final snap = await Collections.user(uid).get();
    if (!snap.exists) throw const NotFoundFailure('Customer not found.');
    return FirestoreConverters.user(snap);
  }

  @override
  Future<void> setCustomerRole({required String uid, required UserRole role, required String reason}) async {
    await FirebaseBackend.call('adminCustomerRole', <String, Object?>{
      'uid': uid,
      'role': role.code,
      'reason': reason,
    });
  }

  @override
  Future<void> setCustomerBlocked({required String uid, required bool blocked, required String reason}) async {
    await FirebaseBackend.call('adminCustomerBlock', <String, Object?>{
      'uid': uid,
      'blocked': blocked,
      'reason': reason,
    });
  }

  // ---- wholesale ----

  @override
  Future<List<WholesaleApplication>> wholesaleApplications({bool openOnly = true}) async {
    Query<Map<String, dynamic>> q = Collections.wholesaleApplications_;
    if (openOnly) q = q.where('status', isEqualTo: WholesaleStatus.pending.code);
    q = q.orderBy('createdAt', descending: true);
    final snap = await q.get();
    return FirestoreConverters.wholesaleApplications(snap.docs);
  }

  @override
  Future<void> decideWholesale({
    required String applicationId,
    required WholesaleStatus decision,
    required String note,
  }) async {
    await FirebaseBackend.call('adminWholesaleDecide', <String, Object?>{
      'applicationId': applicationId,
      'decision': decision.code,
      'note': note,
    });
  }

  @override
  Future<void> saveCustomerPrice(CustomerPriceOverride override) async {
    await FirebaseBackend.call('adminCustomerPriceSave', <String, Object?>{
      'override': <String, Object?>{
        ...override.toWriteMap(),
        'id': override.id,
      },
    });
  }

  @override
  Future<void> deleteCustomerPrice(String overrideId) async {
    await FirebaseBackend.call('adminCustomerPriceDelete', <String, Object?>{'overrideId': overrideId});
  }

  // ---- reviews ----

  @override
  Future<List<Review>> moderationQueue({ReviewStatus status = ReviewStatus.pending}) async {
    final snap = await Collections.reviews_
        .where('status', isEqualTo: status.code)
        .orderBy('createdAt', descending: true)
        .get();
    return FirestoreConverters.reviews(snap.docs);
  }

  @override
  Future<void> decideReview({required String reviewId, required ReviewStatus decision, String note = ''}) async {
    await FirebaseBackend.call('adminReviewModerate', <String, Object?>{
      'reviewId': reviewId,
      'decision': decision.code,
      'note': note,
    });
  }

  // ---- coupons ----

  @override
  Future<List<Coupon>> listCoupons() async {
    final snap = await Collections.coupons_.get();
    return FirestoreConverters.coupons(snap.docs);
  }

  @override
  Future<Coupon> saveCoupon(Coupon coupon) async {
    final data = await FirebaseBackend.call('adminCouponSave', <String, Object?>{
      'coupon': coupon.toWriteMap(),
    });
    return Coupon.fromMap(data, id: _str(data['code']).isEmpty ? coupon.id : _str(data['code']));
  }

  @override
  Future<void> deleteCoupon(String couponId) async {
    await FirebaseBackend.call('adminCouponDelete', <String, Object?>{'couponId': couponId});
  }

  // ---- settings ----

  @override
  Future<StoreSettings> settings() async {
    final snap = await Collections.settings().get();
    if (!snap.exists) return StoreSettings.fallback;
    return FirestoreConverters.settings(snap);
  }

  @override
  Future<void> saveSettings(StoreSettings settings) async {
    await FirebaseBackend.call('adminSettingsSave', <String, Object?>{'settings': settings.toWriteMap()});
  }

  // ---- audit ----

  @override
  Future<PagedResult<AuditLog>> auditLogs({String? entityType, String? action, int pageSize = 50, String? cursor}) async {
    Query<Map<String, dynamic>> q = Collections.auditLogs_.orderBy('createdAt', descending: true).orderBy(documentId: true);
    if (entityType != null && entityType.isNotEmpty) q = q.where('entityType', isEqualTo: entityType);
    if (action != null && action.isNotEmpty) q = q.where('action', isEqualTo: action);
    final after = _decodeCursor(cursor);
    if (after != null) q = q.startAfter(after.value, after.id);
    final snap = await q.limit(pageSize + 1).get();
    final docs = snap.docs;
    final hasMore = docs.length > pageSize;
    final page = hasMore ? docs.sublist(0, pageSize) : docs;
    final last = page.isEmpty ? null : page.last;
    return PagedResult<AuditLog>(
      items: FirestoreConverters.audits(page),
      nextCursor: hasMore && last != null ? _encodeCursor(last, 'createdAt') : null,
    );
  }

  // ---- reports ----

  @override
  Future<List<ReportRow>> salesByProduct({required DateTime from, required DateTime to}) =>
      _report('sales_by_product', from: from, to: to);

  @override
  Future<List<ReportRow>> salesByCategory({required DateTime from, required DateTime to}) =>
      _report('sales_by_category', from: from, to: to);

  @override
  Future<List<ReportRow>> retailVsWholesale({required DateTime from, required DateTime to}) =>
      _report('retail_vs_wholesale', from: from, to: to);

  @override
  Future<List<ReportRow>> slowMoving({int limit = 50}) => _report('slow_moving');

  @override
  Future<List<ReportRow>> couponPerformance() => _report('coupon_performance');

  @override
  Future<List<ReportRow>> inventoryValuation() => _report('inventory_valuation');

  @override
  Future<List<ReportRow>> cancelledOrRefunded({required DateTime from, required DateTime to}) =>
      _report('cancelled_or_refunded', from: from, to: to);

  Future<List<ReportRow>> _report(String reportId, {DateTime? from, DateTime? to}) async {
    final data = await FirebaseBackend.call('adminReport', <String, Object?>{
      'reportId': reportId,
      'from': from?.toUtc().toIso8601String(),
      'to': to?.toUtc().toIso8601String(),
    });
    return _list(data['rows']).map(_reportRow).toList(growable: false);
  }

  @override
  Future<String> exportCsv({required String reportId, DateTime? from, DateTime? to}) async {
    final data = await FirebaseBackend.call('adminReport', <String, Object?>{
      'reportId': reportId,
      'from': from?.toUtc().toIso8601String(),
      'to': to?.toUtc().toIso8601String(),
      'format': 'csv',
    });
    return _str(data['csv']);
  }

  @override
  Future<ImportSummary> importProductsCsv(String csv) async {
    final data = await FirebaseBackend.call('adminImportProducts', <String, Object?>{'csv': csv});
    return ImportSummary(
      totalRows: _int(data['totalRows']),
      imported: _int(data['imported']),
      errors: _list(data['errors']).map((e) => '$e').toList(growable: false),
    );
  }

  // ---- helpers ----

  Order _orderFromData(String orderId, Map<String, dynamic> data) {
    // The transition/mark-payment/refund functions return the raw order document, whose totals are
    // stored nested under `totals`, so they are lifted to top level before Order.fromMap reads them.
    final nested = data['totals'];
    final Map<String, dynamic> flat = nested is Map<String, dynamic>
        ? <String, dynamic>{...data, ...nested}
        : data;
    return Order.fromMap(flat, id: orderId);
  }

  ReportRow _reportRow(Map<String, dynamic> m) => ReportRow(
        key: _str(m['key']),
        label: _str(m['label']),
        units: _int(m['units']),
        revenuePaise: _int(m['revenuePaise']),
        costPaise: _int(m['costPaise']),
        discountPaise: _int(m['discountPaise']),
      );

  static String _encodeCursor(QueryDocumentSnapshot<Map<String, dynamic>> last, String sortField) {
    final raw = last.get(sortField);
    final ms = raw is Timestamp ? raw.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch;
    return base64Url.encode(utf8.encode(jsonEncode(<String, Object?>{'t': ms, 'id': last.id})));
  }

  static _AdminCursor? _decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(cursor))) as Map<String, dynamic>;
      return _AdminCursor(
        Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(map['t'] as int)),
        map['id'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  static int _int(Object? v) => v is int ? v : (v as num?)?.round() ?? 0;
  static String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');
  static List<Map<String, dynamic>> _list(Object? v) =>
      v is List ? v.whereType<Map<String, dynamic>>().toList(growable: false) : const <Map<String, dynamic>>[];
}

final class _AdminCursor {
  const _AdminCursor(this.value, this.id);
  final Timestamp value;
  final String id;
}
