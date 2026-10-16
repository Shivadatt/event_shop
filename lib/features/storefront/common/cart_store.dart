import 'dart:math';

import 'package:get/get.dart';
import 'package:om_events/data/models/payment.dart';

/// One buyer-intent line. The cart deliberately stores **no** prices: quantities are intent, and
/// `PricingEngine` re-derives the price of every line from the live product each time it is
/// displayed, so a slab edit between "add" and "open cart" cannot show a stale promise.
final class CartLine {
  const CartLine({
    required this.productId,
    required this.variantId,
    required this.qty,
  });

  final String productId;
  final String? variantId;
  final int qty;

  /// Product + variant is the identity of a line; two rows for the same pair must merge so slab
  /// bands see the true combined quantity.
  String get key => variantId == null ? productId : '$productId#$variantId';

  CartLine copyWith({int? qty, String? variantId}) => CartLine(
        productId: productId,
        variantId: variantId ?? this.variantId,
        qty: qty ?? this.qty,
      );
}

/// Device-side cart service. It is presentation state only: stock and payable amounts are the
/// server's answer at `OrderRepository.createOrder`, never anything computed here.
final class CartStore extends GetxService {
  CartStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final RxList<CartLine> lines = <CartLine>[].obs;
  final Rxn<String> couponCode = Rxn<String>();

  /// The receipt of the last successfully placed order, so the success page can render the
  /// authoritative totals for a guest who cannot re-read the order document afterwards.
  final Rxn<OrderReceipt> lastReceipt = Rxn<OrderReceipt>();

  final Random _random = Random();
  final DateTime Function() _clock;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
  int get lineCount => lines.length;
  int get unitCount => lines.fold(0, (sum, line) => sum + line.qty);
  int qtyFor(String productId, {String? variantId}) =>
      lines.where((line) => line.key == (variantId == null ? productId : '$productId#$variantId'))
          .fold(0, (sum, line) => sum + line.qty);

  bool contains(String productId) => lines.any((line) => line.productId == productId);

  /// Idempotency key for the current checkout attempt. Generated once, reused across every
  /// retry, and replaced when the cart is emptied — a reload of the checkout page with the same
  /// key makes a double charge impossible on the server.
  late String _idempotencyKey = _newKey();
  String get idempotencyKey => _idempotencyKey;
  void rotateIdempotencyKey() => _idempotencyKey = _newKey();

  String _newKey() =>
      'web-${_clock().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';

  /// Merge-or-append semantics; `qty` is already clamped to the product's granularity by the
  /// calling controller.
  void add(CartLine line) {
    if (line.qty <= 0) return;
    final index = lines.indexWhere((existing) => existing.key == line.key);
    if (index >= 0) {
      final merged = lines[index].copyWith(qty: lines[index].qty + line.qty);
      lines[index] = merged;
      lines.refresh();
    } else {
      lines.add(line);
    }
  }

  void setQty(String key, int qty) {
    final index = lines.indexWhere((line) => line.key == key);
    if (index < 0) return;
    if (qty <= 0) {
      lines.removeAt(index);
    } else {
      lines[index] = lines[index].copyWith(qty: qty);
      lines.refresh();
    }
  }

  void remove(String key) => lines.removeWhere((line) => line.key == key);

  void applyCoupon(String code) => couponCode.value = code;

  void clearCoupon() => couponCode.value = null;

  void clearCart() {
    lines.clear();
    couponCode.value = null;
    rotateIdempotencyKey();
  }
}
