import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/om_doc.dart';

enum PaymentRecordStatus {
  created('created'),
  authorized('authorized'),
  captured('captured'),
  failed('failed'),
  refunded('refunded'),
  partiallyRefunded('partiallyRefunded');

  const PaymentRecordStatus(this.code);
  final String code;
}

PaymentRecordStatus paymentRecordStatusFromCode(String code) => PaymentRecordStatus.values
    .firstWhere((s) => s.code == code, orElse: () => PaymentRecordStatus.created);

/// One attempted or settled payment. A retried checkout creates a new attempt id but the same
/// `idempotencyKey`, so the gateway cannot charge twice for one order.
final class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.orderId,
    required this.amountPaise,
    this.uid = '',
    this.gateway = '',
    this.method = '',
    this.status = PaymentRecordStatus.created,
    this.transactionReference = '',
    this.gatewayOrderId = '',
    this.failureReason = '',
    this.refundedPaise = 0,
    this.createdAt,
    this.updatedAt,
    this.capturedAt,
  });

  final String id;
  final String orderId;
  final int amountPaise;
  final String uid;
  final String gateway;
  final String method;
  final PaymentRecordStatus status;
  final String transactionReference;
  final String gatewayOrderId;
  final String failureReason;
  final int refundedPaise;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? capturedAt;

  bool get isCaptured => status == PaymentRecordStatus.captured;
  bool get isSettled => isCaptured || status == PaymentRecordStatus.authorized;

  factory PaymentRecord.fromMap(Map<String, dynamic> m, {String? id}) => PaymentRecord(
        id: id ?? readStringOrEmpty(m, 'id'),
        orderId: readStringOrEmpty(m, 'orderId'),
        amountPaise: readIntOrZero(m, 'amountPaise'),
        uid: readStringOrEmpty(m, 'uid'),
        gateway: readStringOrEmpty(m, 'gateway'),
        method: readStringOrEmpty(m, 'method'),
        status: paymentRecordStatusFromCode(readStringOrEmpty(m, 'status')),
        transactionReference: readStringOrEmpty(m, 'transactionReference'),
        gatewayOrderId: readStringOrEmpty(m, 'gatewayOrderId'),
        failureReason: readStringOrEmpty(m, 'failureReason'),
        refundedPaise: readIntOrZero(m, 'refundedPaise'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
        capturedAt: readDate(m, 'capturedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'orderId': orderId,
        'amountPaise': amountPaise,
        'uid': uid,
        'gateway': gateway,
        'method': method,
        'status': status.code,
        'transactionReference': transactionReference,
        'gatewayOrderId': gatewayOrderId,
        'failureReason': failureReason,
        'refundedPaise': refundedPaise,
      });
}

/// Payment choices as the store settings expose them. COD is a mode, not a gateway callback.
final class PaymentMethodOption {
  const PaymentMethodOption({
    required this.code,
    required this.label,
    this.isEnabled = true,
    this.description = '',
    this.extraFeePaise = 0,
    this.minAmountPaise = 0,
    this.maxAmountPaise,
  });

  final String code;
  final String label;
  final bool isEnabled;
  final String description;
  final int extraFeePaise;
  final int minAmountPaise;
  final int? maxAmountPaise;

  bool isAllowedFor(int grandTotalPaise) {
    if (!isEnabled) return false;
    if (grandTotalPaise < minAmountPaise) return false;
    final max = maxAmountPaise;
    return max == null || grandTotalPaise <= max;
  }

  factory PaymentMethodOption.fromMap(Map<String, dynamic> m) => PaymentMethodOption(
        code: readStringOrEmpty(m, 'code'),
        label: readStringOrEmpty(m, 'label'),
        isEnabled: readBool(m, 'isEnabled', fallback: true),
        description: readStringOrEmpty(m, 'description'),
        extraFeePaise: readIntOrZero(m, 'extraFeePaise'),
        minAmountPaise: readIntOrZero(m, 'minAmountPaise'),
        maxAmountPaise: readInt(m, 'maxAmountPaise'),
      );

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'code': code,
        'label': label,
        'isEnabled': isEnabled,
        'description': description,
        'extraFeePaise': extraFeePaise,
        'minAmountPaise': minAmountPaise,
        'maxAmountPaise': maxAmountPaise,
      });
}

/// Result of the trusted `orders.createOrder` call. The client renders this; it does not build
/// any part of it locally.
final class OrderReceipt {
  const OrderReceipt({
    required this.orderId,
    required this.orderNumber,
    required this.totals,
    required this.paymentStatus,
    required this.status,
    this.paymentClientSecret = '',
    this.paymentUrl = '',
    this.wasReplay = false,
    this.priceChanged = false,
    this.message = '',
  });

  final String orderId;
  final String orderNumber;
  final OrderTotals totals;
  final PaymentStatus paymentStatus;
  final OrderStatus status;

  /// Gateway handle for the online-payment step, when the store has one configured.
  final String paymentClientSecret;
  final String paymentUrl;

  /// True when the idempotency key matched an existing order — no second charge happened.
  final bool wasReplay;

  /// True when server-side revalidation moved the total; checkout must show the new figure
  /// before the buyer confirms.
  final bool priceChanged;
  final String message;

  factory OrderReceipt.fromMap(Map<String, dynamic> m) => OrderReceipt(
        orderId: readStringOrEmpty(m, 'orderId'),
        orderNumber: readStringOrEmpty(m, 'orderNumber'),
        totals: OrderTotals.fromMap(readMap(m, 'totals')),
        paymentStatus: paymentStatusFromCode(readStringOrEmpty(m, 'paymentStatus')),
        status: orderStatusFromCode(readStringOrEmpty(m, 'orderStatus')),
        paymentClientSecret: readStringOrEmpty(m, 'paymentClientSecret'),
        paymentUrl: readStringOrEmpty(m, 'paymentUrl'),
        wasReplay: readBool(m, 'wasReplay'),
        priceChanged: readBool(m, 'priceChanged'),
        message: readStringOrEmpty(m, 'message'),
      );
}
