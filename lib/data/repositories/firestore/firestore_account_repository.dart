import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/firebase/firebase_backend.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/data/models/address.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/data/providers/firestore_converters.dart';
import 'package:om_events/data/repositories/account_repository.dart';

/// The customer's personal surface: address book, wishlist, reviews, notifications, support. Each
/// write respects the rules exactly — the client touches only its own rows and only the fields the
/// rules allow, so a denied write maps to a [PermissionFailure] rather than a partial success.
///
/// `WishlistRepository` and `RecentlyViewedRepository` both declare `ids()`, so they cannot share
/// one class; the recently-viewed trail lives in [LocalRecentlyViewedRepository] below.
final class FirestoreAccountRepository
    implements AddressRepository, WishlistRepository, ReviewRepository, AccountRepository {
  FirestoreAccountRepository(this._session);

  final SessionStore _session;

  String get _uid {
    final uid = _session.uid;
    if (uid == null) throw const AuthFailure('Please sign in.');
    return uid;
  }

  // ---- AddressRepository ----

  @override
  Future<List<AddressBookEntry>> forCurrentUser() async {
    final snap = await Collections.addresses_.where('uid', isEqualTo: _uid).get();
    final list = FirestoreConverters.addresses(snap.docs);
    list.sort((a, b) {
      final ac = a.createdAt;
      final bc = b.createdAt;
      if (ac == null || bc == null) return 0;
      return bc.compareTo(ac);
    });
    return list;
  }

  @override
  Future<AddressBookEntry> save(AddressBookEntry entry) async {
    final uid = _uid;
    final toWrite = <String, Object?>{...entry.toWriteMap(), 'uid': uid};
    final DocumentReference<Map<String, dynamic>> ref = entry.id.isEmpty
        ? Collections.addresses_.doc()
        : Collections.address(entry.id);
    try {
      if (entry.id.isEmpty) {
        await ref.set(touchCreate(toWrite));
      } else {
        final existing = await ref.get();
        if (!existing.exists) throw const NotFoundFailure('Address not found.');
        if (existing.data()?['uid'] != uid) throw const PermissionFailure();
        await ref.update(touchUpdate(toWrite));
      }
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
    final snap = await ref.get();
    return FirestoreConverters.address(snap);
  }

  @override
  Future<void> delete(String addressId) async {
    final uid = _uid;
    final ref = Collections.address(addressId);
    final snap = await ref.get();
    if (!snap.exists) return;
    if (snap.data()?['uid'] != uid) throw const PermissionFailure();
    try {
      await ref.delete();
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<void> setDefault(String addressId, {bool billing = false}) async {
    final uid = _uid;
    final field = billing ? 'isDefaultBilling' : 'isDefaultShipping';
    final all = await Collections.addresses_.where('uid', isEqualTo: uid).get();
    final batch = Collections.addresses_.firestore.batch();
    for (final doc in all.docs) {
      if (doc.get(field) == true && doc.id != addressId) {
        batch.update(doc.reference, <String, Object?>{field: false});
      }
    }
    batch.set(Collections.address(addressId), <String, Object?>{
      field: true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  // ---- WishlistRepository ----

  @override
  Future<List<String>> ids() async {
    final snap = await Collections.user(_uid).get();
    if (!snap.exists) return const <String>[];
    return (snap.data()?['wishlistProductIds'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList(growable: false);
  }

  @override
  Future<List<Product>> items() async {
    final ids = await this.ids();
    if (ids.isEmpty) return const <Product>[];
    final out = <Product>[];
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await Collections.products_
          .where(FieldPath.documentId, whereIn: chunk)
          .where('status', isEqualTo: ProductStatus.active.code)
          .get();
      out.addAll(FirestoreConverters.products(snap.docs));
    }
    return out;
  }

  @override
  Future<bool> toggle(String productId, {required bool add}) async {
    final uid = _uid;
    final op = add ? FieldValue.arrayUnion(<String>[productId]) : FieldValue.arrayRemove(<String>[productId]);
    try {
      await Collections.user(uid).update(<String, Object?>{
        'wishlistProductIds': op,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
    return add;
  }

  // ---- ReviewRepository ----

  @override
  Future<List<Review>> forProduct(String productId, {bool publishedOnly = true}) async {
    // The status equality is what makes an unauthenticated listing query pass the rules; a
    // publishedOnly=false read is staff-only (a non-staff caller would be denied server-side).
    Query<Map<String, dynamic>> q = Collections.reviews_.where('productId', isEqualTo: productId);
    if (publishedOnly) q = q.where('status', isEqualTo: ReviewStatus.published.code);
    q = q.orderBy('createdAt', descending: true);
    final snap = await q.get();
    return FirestoreConverters.reviews(snap.docs);
  }

  @override
  Future<RatingBreakdown> breakdownFor(String productId) async {
    final reviews = await forProduct(productId);
    return RatingBreakdown.from(reviews);
  }

  @override
  Future<Review> submit({
    required String productId,
    required int rating,
    String title = '',
    String body = '',
    String? orderId,
    List<MediaRef> images = const <MediaRef>[],
  }) async {
    final data = await FirebaseBackend.call('reviewSubmit', <String, Object?>{
      'productId': productId,
      'rating': rating,
      'title': title,
      'body': body,
      'orderId': orderId,
      'authorName': _session.profile?.displayName ?? '',
      'images': images.map((i) => i.toMap()).toList(),
    });
    final id = data['id'] as String?;
    if (id == null) throw const ServerFailure('Review could not be saved.');
    final snap = await Collections.review(id).get();
    return FirestoreConverters.review(snap);
  }

  @override
  Future<void> report(String reviewId, {required String reason}) async {
    await FirebaseBackend.call('reviewReport', <String, Object?>{'reviewId': reviewId, 'reason': reason});
  }

  @override
  Future<Review?> mineFor(String productId) async {
    final snap = await Collections.reviews_
        .where('productId', isEqualTo: productId)
        .where('uid', isEqualTo: _uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return FirestoreConverters.review(snap.docs.first);
  }

  // ---- AccountRepository ----

  @override
  Stream<List<AppNotification>> notifications({int limit = 30}) {
    final uid = _uid;
    return Collections.notifications_
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => FirestoreConverters.notifications(snap.docs));
  }

  @override
  Future<void> markNotificationRead(String id) async {
    try {
      await Collections.notification(id).update(<String, Object?>{'isRead': true});
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final uid = _uid;
    final snap = await Collections.notifications_
        .where('uid', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = Collections.notifications_.firestore.batch();
    for (final doc in snap.docs.take(400)) {
      batch.update(doc.reference, <String, Object?>{'isRead': true});
    }
    await batch.commit();
  }

  @override
  Future<SupportRequest> openSupportTicket({
    required String subject,
    required SupportTopic topic,
    required String message,
    String? orderId,
    String? productId,
  }) async {
    final uid = _uid;
    final ref = Collections.supportRequests_.doc();
    final first = SupportMessage(from: uid, body: message, at: DateTime.now());
    final payload = <String, Object?>{
      'uid': uid,
      'subject': subject,
      'orderId': orderId ?? '',
      'productId': productId ?? '',
      'topic': topic.code,
      'status': SupportStatus.open.code,
      'messages': <Map<String, Object?>>[first.toMap()],
    };
    try {
      await ref.set(touchCreate(payload));
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
    final snap = await ref.get();
    return FirestoreConverters.support(snap);
  }

  @override
  Future<List<SupportRequest>> mySupportTickets() async {
    final snap = await Collections.supportRequests_
        .where('uid', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .get();
    return FirestoreConverters.supports(snap.docs);
  }

  @override
  Future<void> replyToTicket(String ticketId, {required String message}) async {
    final uid = _uid;
    final reply = SupportMessage(from: uid, body: message, at: DateTime.now());
    try {
      await Collections.supportRequest(ticketId).update(<String, Object?>{
        'messages': FieldValue.arrayUnion(<Map<String, Object?>>[reply.toMap()]),
        'status': SupportStatus.open.code,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }
}

/// Session-local trail, deliberately not a Firestore collection: it is browsing history, not store
/// data, and the contract caps it client-side. No storage dependency exists in the pubspec, so the
/// trail lives for the app session only — the honest degrade rather than inventing a persistence
/// layer outside this domain.
final class LocalRecentlyViewedRepository implements RecentlyViewedRepository {
  final List<String> _ids = <String>[];

  @override
  Future<List<String>> ids() async => _ids.toList(growable: false);

  @override
  Future<void> push(String productId, {int limit = 24}) async {
    _ids.remove(productId);
    _ids.insert(0, productId);
    if (_ids.length > limit) _ids.removeRange(limit, _ids.length);
  }

  @override
  Future<void> clear() async => _ids.clear();
}
