import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/firebase/firebase_backend.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/data/providers/firestore_converters.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/order_repository.dart';

/// Order reads go to Firestore; every ORDER *write* (create, cancel, return, payment) goes to a
/// Cloud Function. The draft carries intent only — no totals — and the function returns the
/// authoritative receipt. A price/stock move surfaces as a [ConflictFailure], never a raw error.
final class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository(this._session);

  final SessionStore _session;

  @override
  Future<OrderReceipt> createOrder(OrderDraft draft) async {
    final data = await FirebaseBackend.call('ordersCreate', draft.toMap());
    return OrderReceipt.fromMap(data);
  }

  @override
  Future<PagedResult<Order>> listMine({int pageSize = 20, String? cursor}) async {
    final uid = _session.uid;
    if (uid == null) throw const AuthFailure('Sign in to see your orders.');
    Query<Map<String, dynamic>> q = Collections.orders_
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId);
    final after = _decodeCursor(cursor);
    if (after != null) q = q.startAfter([after.timestamp, after.id]);
    final snap = await q.limit(pageSize + 1).get();
    final docs = snap.docs;
    final hasMore = docs.length > pageSize;
    final page = hasMore ? docs.sublist(0, pageSize) : docs;
    final last = page.isEmpty ? null : page.last;
    return PagedResult<Order>(
      items: FirestoreConverters.orders(page),
      nextCursor: hasMore && last != null ? _encodeCursor(last) : null,
    );
  }

  @override
  Future<Order> byId(String orderId) async {
    final snap = await Collections.order(orderId).get();
    if (!snap.exists) throw const NotFoundFailure('Order not found.');
    return FirestoreConverters.order(snap);
  }

  @override
  Future<Order> byOrderNumber(String orderNumber, {String? contactEmail}) async {
    final snap = await Collections.orders_
        .where('orderNumber', isEqualTo: orderNumber.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) throw const NotFoundFailure('No order with that number.');
    final order = FirestoreConverters.order(snap.docs.first);
    // A guest order is only viewable when the caller proves the purchase with the contact email.
    if (order.isGuest && contactEmail != null && order.contactEmail.isNotEmpty &&
        order.contactEmail.toLowerCase() != contactEmail.trim().toLowerCase()) {
      throw const PermissionFailure('That email does not match the order.');
    }
    return order;
  }

  @override
  Future<void> requestCancellation(String orderId, {required String reason}) async {
    await FirebaseBackend.call('orderRequestCancel', <String, Object?>{
      'orderId': orderId,
      'reason': reason,
    });
  }

  @override
  Future<void> requestReturn(String orderId, {required String reason}) async {
    await FirebaseBackend.call('orderRequestReturn', <String, Object?>{
      'orderId': orderId,
      'reason': reason,
    });
  }

  @override
  Future<List<DraftLine>> expandReorder(String orderId) async {
    final order = await byId(orderId);
    return order.items
        .map((item) => DraftLine(
              productId: item.productId,
              qty: item.qty,
              variantId: item.variantId,
            ))
        .toList(growable: false);
  }

  @override
  Future<PaymentRecord> confirmPayment({
    required String orderId,
    required String paymentId,
    String? clientSecret,
  }) async {
    await FirebaseBackend.call('paymentsConfirm', <String, Object?>{
      'orderId': orderId,
      'paymentId': paymentId,
      'clientSecret': clientSecret,
    });
    final snap = await Collections.payments_.doc(paymentId).get();
    if (!snap.exists) throw const NotFoundFailure('Payment not found.');
    return FirestoreConverters.payment(snap);
  }

  @override
  Stream<Order> watchOrder(String orderId) {
    return Collections.order(orderId).snapshots().asyncMap((snap) {
      if (!snap.exists) throw const NotFoundFailure('Order not found.');
      return FirestoreConverters.order(snap);
    });
  }

  static String _encodeCursor(QueryDocumentSnapshot<Map<String, dynamic>> last) {
    final created = last.get('createdAt');
    final ms = created is Timestamp ? created.millisecondsSinceEpoch : 0;
    return base64Url.encode(utf8.encode(jsonEncode(<String, Object?>{'t': ms, 'id': last.id})));
  }

  static _TimeCursor? _decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(cursor))) as Map<String, dynamic>;
      return _TimeCursor(Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(map['t'] as int)), map['id'] as String);
    } catch (_) {
      return null;
    }
  }
}

final class _TimeCursor {
  const _TimeCursor(this.timestamp, this.id);
  final Timestamp timestamp;
  final String id;
}
