import 'package:get/get.dart';
import 'package:om_events/features/storefront/cart/cart_controller.dart';

/// Registers the cart page's controller. `CartStore`, `SettingsStore` and the repositories come
/// from `StorefrontBinding` / `BackendBinding`; this binding owns nothing but the controller.
final class CartBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CartController>(CartController.new, fenix: true);
  }
}
