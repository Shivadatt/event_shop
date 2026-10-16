import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/data/models/address.dart';
import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/models/wholesale.dart';

/// Snapshot -> typed model converters. Reads funnel through the models' defensive `fromMap`
/// (which tolerates `Timestamp`/epoch/ISO and number-width drift), so a function-written doc and a
/// client-written doc parse identically. `id`/`uid` is always the document id, never a field.
abstract final class FirestoreConverters {
  const FirestoreConverters._();

  static Map<String, dynamic> _data(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
  }

  static Product product(DocumentSnapshot<Object?> doc) =>
      Product.fromMap(_data(doc), id: doc.id);

  static List<Product> products(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(product).toList(growable: false);

  static Category category(DocumentSnapshot<Object?> doc) =>
      Category.fromMap(_data(doc), id: doc.id);

  static List<Category> categories(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(category).toList(growable: false);

  static ProductVariant variant(DocumentSnapshot<Object?> doc) =>
      ProductVariant.fromMap(_data(doc), id: doc.id);

  static List<ProductVariant> variants(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(variant).toList(growable: false);

  static Order order(DocumentSnapshot<Object?> doc) => Order.fromMap(_data(doc), id: doc.id);

  static List<Order> orders(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(order).toList(growable: false);

  static OrderEvent orderEvent(DocumentSnapshot<Object?> doc) =>
      OrderEvent.fromMap(_data(doc));

  static PaymentRecord payment(DocumentSnapshot<Object?> doc) =>
      PaymentRecord.fromMap(_data(doc), id: doc.id);

  static UserProfile user(DocumentSnapshot<Object?> doc) =>
      UserProfile.fromMap(_data(doc), uid: doc.id);

  static List<UserProfile> users(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(user).toList(growable: false);

  static AddressBookEntry address(DocumentSnapshot<Object?> doc) =>
      AddressBookEntry.fromMap(_data(doc), id: doc.id);

  static List<AddressBookEntry> addresses(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(address).toList(growable: false);

  static Review review(DocumentSnapshot<Object?> doc) => Review.fromMap(_data(doc), id: doc.id);

  static List<Review> reviews(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(review).toList(growable: false);

  static Coupon coupon(DocumentSnapshot<Object?> doc) => Coupon.fromMap(_data(doc), id: doc.id);

  static List<Coupon> coupons(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(coupon).toList(growable: false);

  static InventoryMovement movement(DocumentSnapshot<Object?> doc) =>
      InventoryMovement.fromMap(_data(doc), id: doc.id);

  static List<InventoryMovement> movements(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(movement).toList(growable: false);

  static AuditLog audit(DocumentSnapshot<Object?> doc) =>
      AuditLog.fromMap(_data(doc), id: doc.id);

  static List<AuditLog> audits(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(audit).toList(growable: false);

  static AppNotification notification(DocumentSnapshot<Object?> doc) =>
      AppNotification.fromMap(_data(doc), id: doc.id);

  static List<AppNotification> notifications(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(notification).toList(growable: false);

  static SupportRequest support(DocumentSnapshot<Object?> doc) =>
      SupportRequest.fromMap(_data(doc), id: doc.id);

  static List<SupportRequest> supports(List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(support).toList(growable: false);

  static WholesaleApplication wholesaleApplication(DocumentSnapshot<Object?> doc) =>
      WholesaleApplication.fromMap(_data(doc), id: doc.id);

  static List<WholesaleApplication> wholesaleApplications(
          List<QueryDocumentSnapshot<Object?>> docs) =>
      docs.map(wholesaleApplication).toList(growable: false);

  static CustomerPriceOverride priceOverride(DocumentSnapshot<Object?> doc) =>
      CustomerPriceOverride.fromMap(_data(doc), id: doc.id);

  static StoreSettings settings(DocumentSnapshot<Object?> doc) =>
      StoreSettings.fromMap(_data(doc));
}
