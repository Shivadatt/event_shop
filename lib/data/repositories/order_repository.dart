import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/query.dart';

/// What the storefront is asking the backend to buy. Deliberately contains **no** totals: the
/// client sends intent, the server decides money.
final class OrderDraft {
  const OrderDraft({
    required this.lines,
    required this.deliveryMode,
    this.shipping,
    this.customerNote = '',
    this.contactEmail = '',
    this.contactPhone = '',
    this.couponCode = '',
    this.paymentMethod = '',
    required this.idempotencyKey,
    this.grandTotalPaiseForComparison = 0,
  });

  final List<DraftLine> lines;
  final DeliveryMode deliveryMode;
  final ShippingSnapshot? shipping;
  final String customerNote;
  final String contactEmail;
  final String contactPhone;
  final String couponCode;
  final String paymentMethod;

  /// Generated once per checkout attempt and reused across retries; the function replays
  /// instead of double-charging.
  final String idempotencyKey;

  /// Sent only so the server can report a disagreement; never used as the charged amount.
  final int grandTotalPaiseForComparison;

  Map<String, Object?> toMap() => <String, Object?>{
        'lines': lines.map((l) => l.toMap()).toList(),
        'deliveryMode': deliveryMode.code,
        'shipping': shipping?.toMap(),
        'customerNote': customerNote,
        'contactEmail': contactEmail,
        'contactPhone': contactPhone,
        'couponCode': couponCode,
        'paymentMethod': paymentMethod,
        'idempotencyKey': idempotencyKey,
        'clientTotalPaise': grandTotalPaiseForComparison,
      };
}

final class DraftLine {
  const DraftLine({
    required this.productId,
    required this.qty,
    this.variantId,
  });

  final String productId;
  final String? variantId;
  final int qty;

  Map<String, Object?> toMap() => <String, Object?>{
        'productId': productId,
        'variantId': variantId,
        'qty': qty,
      };
}

abstract interface class OrderRepository {
  /// Trusted creation: re-prices every line from authoritative products, checks stock, applies
  /// the coupon, reserves inventory atomically, and returns the receipt. Throws
  /// [ConflictFailure] when price or availability moved.
  Future<OrderReceipt> createOrder(OrderDraft draft);

  Future<PagedResult<Order>> listMine({int pageSize = 20, String? cursor});

  Future<Order> byId(String orderId);

  /// Guest orders are readable with the order number as proof-of-purchase.
  Future<Order> byOrderNumber(String orderNumber, {String? contactEmail});

  Future<void> requestCancellation(String orderId, {required String reason});

  Future<void> requestReturn(String orderId, {required String reason});

  /// Reorder re-prices from current products; it never replays the old snapshot.
  Future<List<DraftLine>> expandReorder(String orderId);

  Future<PaymentRecord> confirmPayment({
    required String orderId,
    required String paymentId,
    String? clientSecret,
  });

  Stream<Order> watchOrder(String orderId);
}
