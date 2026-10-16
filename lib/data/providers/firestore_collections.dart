import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/app/core/services/firebase/firebase_backend.dart';

/// One place that names every Firestore collection and hands out typed references, so no
/// repository hardcodes a path string. Mirrors the CONTRACT collection list exactly.
abstract final class Collections {
  const Collections._();

  static const String users = 'users';
  static const String categories = 'categories';
  static const String products = 'products';
  static const String productVariants = 'product_variants';
  static const String inventoryMovements = 'inventory_movements';
  static const String orders = 'orders';
  static const String orderItems = 'order_items';
  static const String payments = 'payments';
  static const String reviews = 'reviews';
  static const String coupons = 'coupons';
  static const String addresses = 'addresses';
  static const String wholesaleApplications = 'wholesale_applications';
  static const String storeSettings = 'store_settings';
  static const String auditLogs = 'audit_logs';
  static const String notifications = 'notifications';
  static const String supportRequests = 'support_requests';
  static const String mediaObjects = 'media_objects';

  static const String storeSettingsDoc = 'store';

  static FirebaseFirestore get _db => FirebaseBackend.firestore;

  static CollectionReference<Map<String, dynamic>> get users_ => _db.collection(users);
  static CollectionReference<Map<String, dynamic>> get categories_ => _db.collection(categories);
  static CollectionReference<Map<String, dynamic>> get products_ => _db.collection(products);
  static CollectionReference<Map<String, dynamic>> get variants_ =>
      _db.collection(productVariants);
  static CollectionReference<Map<String, dynamic>> get movements_ =>
      _db.collection(inventoryMovements);
  static CollectionReference<Map<String, dynamic>> get orders_ => _db.collection(orders);
  static CollectionReference<Map<String, dynamic>> get payments_ => _db.collection(payments);
  static CollectionReference<Map<String, dynamic>> get reviews_ => _db.collection(reviews);
  static CollectionReference<Map<String, dynamic>> get coupons_ => _db.collection(coupons);
  static CollectionReference<Map<String, dynamic>> get addresses_ => _db.collection(addresses);
  static CollectionReference<Map<String, dynamic>> get wholesaleApplications_ =>
      _db.collection(wholesaleApplications);
  static CollectionReference<Map<String, dynamic>> get auditLogs_ => _db.collection(auditLogs);
  static CollectionReference<Map<String, dynamic>> get notifications_ =>
      _db.collection(notifications);
  static CollectionReference<Map<String, dynamic>> get supportRequests_ =>
      _db.collection(supportRequests);

  static DocumentReference<Map<String, dynamic>> user(String uid) => users_.doc(uid);
  static DocumentReference<Map<String, dynamic>> product(String id) => products_.doc(id);
  static DocumentReference<Map<String, dynamic>> category(String id) => categories_.doc(id);
  static DocumentReference<Map<String, dynamic>> order(String id) => orders_.doc(id);
  static DocumentReference<Map<String, dynamic>> address(String id) => addresses_.doc(id);
  static DocumentReference<Map<String, dynamic>> variant(String id) => variants_.doc(id);
  static DocumentReference<Map<String, dynamic>> review(String id) => reviews_.doc(id);
  static DocumentReference<Map<String, dynamic>> notification(String id) => notifications_.doc(id);
  static DocumentReference<Map<String, dynamic>> supportRequest(String id) =>
      supportRequests_.doc(id);
  static DocumentReference<Map<String, dynamic>> settings() =>
      _db.collection(storeSettings).doc(storeSettingsDoc);

  /// A generated document id without creating the document (used to name an idempotency target
  /// before the function mints the real order id).
  static String newProductId() => products_.doc().id;
}

/// Writes a `Timestamp` for create/update while never clobbering `createdAt` on an update.
Map<String, Object?> touchCreate(Map<String, Object?> base) => <String, Object?>{
      ...base,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

Map<String, Object?> touchUpdate(Map<String, Object?> base) => <String, Object?>{
      ...base,
      'updatedAt': FieldValue.serverTimestamp(),
    };
