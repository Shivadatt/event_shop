import 'package:get/get.dart';
import 'package:om_events/features/storefront/cart/cart_controller.dart';
import 'package:om_events/features/storefront/checkout/checkout_controller.dart';

/// `/checkout` needs the cart's priced rows and coupon quote, so it registers the cart controller
/// too when the buyer deep-linked straight here instead of coming through `/cart`.
final class CheckoutBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<CartController>()) {
      Get.lazyPut<CartController>(CartController.new, fenix: true);
    }
    Get.lazyPut<CheckoutController>(CheckoutController.new, fenix: true);
  }
}
