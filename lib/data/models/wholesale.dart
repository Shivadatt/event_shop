import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/om_doc.dart';

final class WholesaleApplication {
  const WholesaleApplication({
    required this.id,
    required this.uid,
    required this.companyName,
    required this.contactName,
    required this.phone,
    this.email = '',
    this.gstNumber = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.reason = '',
    this.expectedMonthlyVolume = '',
    this.status = WholesaleStatus.pending,
    this.reviewNote = '',
    this.reviewedBy = '',
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String uid;
  final String companyName;
  final String contactName;
  final String phone;
  final String email;
  final String gstNumber;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String reason;
  final String expectedMonthlyVolume;
  final WholesaleStatus status;
  final String reviewNote;
  final String reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOpen => status == WholesaleStatus.pending;

  factory WholesaleApplication.fromMap(Map<String, dynamic> m, {String? id}) =>
      WholesaleApplication(
        id: id ?? readStringOrEmpty(m, 'id'),
        uid: readStringOrEmpty(m, 'uid'),
        companyName: readStringOrEmpty(m, 'companyName'),
        contactName: readStringOrEmpty(m, 'contactName'),
        phone: readStringOrEmpty(m, 'phone'),
        email: readStringOrEmpty(m, 'email'),
        gstNumber: readStringOrEmpty(m, 'gstNumber'),
        address: readStringOrEmpty(m, 'address'),
        city: readStringOrEmpty(m, 'city'),
        state: readStringOrEmpty(m, 'state'),
        pincode: readStringOrEmpty(m, 'pincode'),
        reason: readStringOrEmpty(m, 'reason'),
        expectedMonthlyVolume: readStringOrEmpty(m, 'expectedMonthlyVolume'),
        status: wholesaleStatusFromCode(readStringOrEmpty(m, 'status')),
        reviewNote: readStringOrEmpty(m, 'reviewNote'),
        reviewedBy: readStringOrEmpty(m, 'reviewedBy'),
        reviewedAt: readDate(m, 'reviewedAt'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'uid': uid,
        'companyName': companyName,
        'contactName': contactName,
        'phone': phone,
        'email': email,
        'gstNumber': gstNumber,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'reason': reason,
        'expectedMonthlyVolume': expectedMonthlyVolume,
        'status': status.code,
      });
}

/// One row of the quick bulk-order grid: SKU + quantity, resolved server-side.
final class BulkOrderLine {
  const BulkOrderLine({
    required this.sku,
    required this.qty,
    this.variantId,
    this.resolvedProductId,
    this.error,
  });

  final String sku;
  final int qty;
  final String? variantId;
  final String? resolvedProductId;
  final String? error;

  bool get isValid => error == null && resolvedProductId != null && qty > 0;

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'sku': sku,
        'qty': qty,
        'variantId': variantId,
      });

  factory BulkOrderLine.fromMap(Map<String, dynamic> m) => BulkOrderLine(
        sku: readStringOrEmpty(m, 'sku'),
        qty: readIntOrZero(m, 'qty'),
        variantId: readString(m, 'variantId'),
        resolvedProductId: readString(m, 'productId'),
        error: readString(m, 'error'),
      );
}

/// A negotiated price an admin granted to one customer for one product. Beats public slabs and
/// is applied only by the backend.
final class CustomerPriceOverride {
  const CustomerPriceOverride({
    required this.id,
    required this.uid,
    required this.productId,
    required this.unitPricePaise,
    this.variantId,
    this.note = '',
    this.createdBy = '',
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String uid;
  final String productId;
  final String? variantId;
  final int unitPricePaise;
  final String note;
  final String createdBy;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool isAlive([DateTime? now]) {
    final at = now ?? DateTime.now();
    final expiry = expiresAt;
    return expiry == null || !at.isAfter(expiry);
  }

  factory CustomerPriceOverride.fromMap(Map<String, dynamic> m, {String? id}) =>
      CustomerPriceOverride(
        id: id ?? readStringOrEmpty(m, 'id'),
        uid: readStringOrEmpty(m, 'uid'),
        productId: readStringOrEmpty(m, 'productId'),
        variantId: readString(m, 'variantId'),
        unitPricePaise: readIntOrZero(m, 'unitPricePaise'),
        note: readStringOrEmpty(m, 'note'),
        createdBy: readStringOrEmpty(m, 'createdBy'),
        expiresAt: readDate(m, 'expiresAt'),
        createdAt: readDate(m, 'createdAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'uid': uid,
        'productId': productId,
        'variantId': variantId,
        'unitPricePaise': unitPricePaise,
        'note': note,
        'expiresAt': expiresAt,
      });
}
