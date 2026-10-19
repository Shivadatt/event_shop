import 'dart:async';

import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/line_price.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';

/// One displayable cart line: the buyer's intent plus whatever the catalogue could tell us about
/// it. A missing or delisted product still produces a row — with a reason and a remove action —
/// because dropping it silently would change what the buyer thinks they are buying.
final class CartRow {
  const CartRow({
    required this.line,
    required this.price,
    this.product,
    this.variant,
    this.notice,
    this.missing = false,
  });

  final CartLine line;
  final LinePrice price;
  final Product? product;
  final ProductVariant? variant;

  /// Presentable warning that does not stop the buyer ("Only 6 left", "No longer listed").
  final String? notice;
  final bool missing;

  bool get canPrice => !missing && product != null && !price.hasError;
}

/// `/cart` controller.
///
/// The cart holds quantity intent only; every rupee shown here is `PricingEngine`'s answer for the
/// live product, re-derived on each rebuild. The coupon figure is the **server's** answer from
/// `CouponRepository.quote`, not a local percentage. Nothing here can decide the payable total:
/// `OrderRepository.createOrder` does that, and the checkout page renders its receipt.
final class CartController extends GetxController {
  final RxMap<String, Product> products = <String, Product>{}.obs;
  final RxMap<String, ProductVariant> variants = <String, ProductVariant>{}.obs;
  final RxBool loading = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final Rxn<OmFailure> couponFailure = Rxn<OmFailure>();
  final Rxn<CouponQuote> quote = Rxn<CouponQuote>();
  final RxString quoteFor = RxString('');
  final RxBool applyingCoupon = false.obs;

  Worker? _linesWorker;

  CartStore get _cart => Get.find<CartStore>();

  @override
  void onInit() {
    super.onInit();
    _linesWorker = ever<List<CartLine>>(_cart.lines, (_) => _ensureProducts());
    load();
  }

  @override
  void onClose() {
    _linesWorker?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    await _ensureProducts();
    loading.value = false;
  }

  Future<void> retry() => load();

  /// Fetches any line whose product is not in the local map. Called when a line appears too, so a
  /// product added from another tab resolves without leaving the cart.
  Future<void> _ensureProducts() async {
    final missing = _cart.lines
        .map((line) => line.productId)
        .toSet()
        .where((id) => !products.containsKey(id))
        .toList(growable: false);
    if (missing.isEmpty) return;

    final loaded = await safeCall<List<Product>>(
      () => Get.find<ProductRepository>().byIds(missing),
      onFailure: (f) => failure.value = f,
    );
    if (loaded != null) {
      for (final product in loaded) {
        products[product.id] = product;
      }
    }

    final variantIds = _cart.lines
        .map((line) => line.variantId)
        .whereType<String>()
        .toSet()
        .where((id) => !variants.containsKey(id));
    for (final id in variantIds) {
      final variant = await safeCall<ProductVariant>(
        () => Get.find<VariantRepository>().byId(id),
      );
      if (variant != null) variants[id] = variant;
    }
  }

  /// Rows in cart order. Reads `CartStore.lines` inside the getter so an enclosing `Obx` rebuilds
  /// when a quantity changes.
  List<CartRow> get rows {
    final result = <CartRow>[];
    for (final line in _cart.lines) {
      final product = products[line.productId];
      if (product == null) {
        result.add(
          CartRow(
            line: line,
            price: LinePrice.unavailable(),
            missing: true,
            notice: failure.value != null
                ? failure.value!.message
                : 'This item could not be loaded. It stays in your cart until you remove it.',
          ),
        );
        continue;
      }
      final variant = line.variantId == null ? null : variants[line.variantId];
      if (variant == null && line.variantId != null) {
        result.add(
          CartRow(
            line: line,
            price: priceLine(product: product, qty: line.qty),
            product: product,
            notice: 'The selected option could not be verified, so this line is priced at the '
                'base product rate and re-checked at checkout.',
          ),
        );
        continue;
      }
      final price = priceLine(product: product, qty: line.qty, variant: variant);
      final delisted = product.status != ProductStatus.active;
      final stock = variant?.stockQty ?? product.stockQty;
      result.add(
        CartRow(
          line: line,
          price: price,
          product: product,
          variant: variant,
          notice: delisted
              ? 'This product is no longer on sale; it will be rejected at checkout.'
              : (line.qty > stock && stock >= 0
                  ? 'Only $stock ${product.unit} available right now.'
                  : null),
        ),
      );
    }
    return result;
  }

  /// Engine-owned display totals. `shippingPaise` is deliberately zero here: shipping depends on
  /// the pincode and delivery mode chosen at checkout.
  CartTotals get totals {
    final priced = <PriceResolution>[];
    for (final row in rows) {
      if (row.canPrice) priced.add(row.price.resolution);
    }
    final settings = Get.find<SettingsStore>().value;
    return CartTotals.from(
      priced,
      couponDiscountPaise: quote.value?.discountPaise ?? 0,
      taxRateBps: settings.taxRateBps,
      taxInclusive: settings.taxInclusive,
    );
  }

  int get lineCount => _cart.lineCount;
  int get unitCount => _cart.unitCount;
  bool get isEmpty => _cart.lines.isEmpty;

  /// The store's minimum cart value, advisory: it never blocks the button, because only the
  /// server can reject an order.
  bool get belowMinimumOrderValue =>
      !isEmpty &&
      Get.find<SettingsStore>().value.minOrderValuePaise > 0 &&
      totals.subtotalPaise < Get.find<SettingsStore>().value.minOrderValuePaise;

  void setQuantity(CartRow row, int requested) {
    final product = row.product;
    if (product == null) {
      _cart.setQty(row.line.key, requested);
      return;
    }
    final clamped = row.price.granularity.clampQty(requested);
    if (clamped != requested) {
      final violation = row.price.granularity.violationFor(requested);
      if (violation != null) {
        Get.snackbar('Quantity adjusted', violation);
      }
    }
    _cart.setQty(row.line.key, clamped);
  }

  void remove(CartRow row) => _cart.remove(row.line.key);

  /// Keeps the line in the wishlist and drops it from the cart. The wishlist write is the
  /// repository's answer, so a permission denial does not quietly lose the cart line too.
  Future<void> moveToWishlist(CartRow row) async {
    final product = row.product;
    if (product == null) {
      _cart.remove(row.line.key);
      return;
    }
    final session = Get.find<SessionStore>();
    if (!session.isSignedIn) {
      unawaited(Get.toNamed<dynamic>(
        OmRoutes.login,
        parameters: <String, String>{
          OmRouteArgs.returnUrl: Uri.encodeComponent(OmRoutes.cart),
        },
      ));
      return;
    }
    final saved = await safeCall<bool>(
      () => Get.find<WishlistRepository>().toggle(product.id, add: true),
      onFailure: (f) => failure.value = f,
    );
    if (saved == true) _cart.remove(row.line.key);
  }

  /// Coupon validation is a server read: the code, its scope and its cap are decided by the
  /// repository's quote, never by local arithmetic on this cart.
  Future<void> applyCoupon(String rawCode) async {
    final code = Coupon.normaliseCode(rawCode);
    if (code.isEmpty) {
      couponFailure.value = const ValidationFailure('Enter a coupon code.');
      return;
    }
    applyingCoupon.value = true;
    couponFailure.value = null;
    final lines = <QuoteLine>[];
    for (final row in rows) {
      final product = row.product;
      if (!row.canPrice || product == null) continue;
      lines.add(
        QuoteLine(
          productId: row.line.productId,
          variantId: row.line.variantId,
          qty: row.line.qty,
          lineTotalPaise: row.price.resolution.lineTotalPaise,
          categoryId: product.categoryId,
        ),
      );
    }
    final result = await safeCall<CouponQuote>(
      () => Get.find<CouponRepository>().quote(
        code: code,
        lines: lines,
        uid: Get.find<SessionStore>().uid,
      ),
      onFailure: (f) => couponFailure.value = f,
    );
    applyingCoupon.value = false;
    if (result == null) {
      quote.value = null;
      quoteFor.value = '';
      _cart.clearCoupon();
      return;
    }
    quote.value = result;
    quoteFor.value = code;
    if (result.discountPaise <= 0 && !result.freeShipping) {
      couponFailure.value = ValidationFailure(
        result.reason.isEmpty
            ? '“$code” does not reduce this cart’s total.'
            : result.reason,
      );
    } else {
      _cart.applyCoupon(code);
    }
  }

  void clearCoupon() {
    quote.value = null;
    quoteFor.value = '';
    couponFailure.value = null;
    _cart.clearCoupon();
  }

  void clearCart() {
    _cart.clearCart();
    quote.value = null;
    quoteFor.value = '';
    couponFailure.value = null;
  }

  void openCheckout() {
    if (isEmpty) {
      Get.snackbar('Cart is empty', 'Add something before checking out.',
          duration: const Duration(seconds: 2));
      return;
    }
    Get.toNamed<dynamic>(OmRoutes.checkout);
  }

  void openProduct(CartRow row) {
    final product = row.product;
    if (product == null) return;
    Get.toNamed<dynamic>(OmRoutes.forProduct(product.pathSlug));
  }

  /// Payment methods the store has switched on, used by checkout for COD eligibility. The cart
  /// only reads them to explain what will be offered next.
  List<PaymentMethodOption> get enabledPaymentMethods =>
      Get.find<SettingsStore>().value.paymentMethods
          .where((method) => method.isEnabled)
          .toList(growable: false);
}
