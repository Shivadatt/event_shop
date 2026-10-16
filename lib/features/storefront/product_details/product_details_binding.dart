import 'package:get/get.dart';
import 'package:om_events/features/storefront/common/storefront_binding.dart';
import 'package:om_events/features/storefront/product_details/product_details_controller.dart';

/// Binding for `/product/:idOrSlug`. The controller resolves the slug first and falls back to the
/// document id, so a pasted `product/<id>` deep link still opens.
final class ProductDetailsBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<ProductDetailsController>(ProductDetailsController.new, fenix: true);
  }
}
