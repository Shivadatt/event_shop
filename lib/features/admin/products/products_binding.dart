import 'package:get/get.dart';
import 'package:om_events/features/admin/products/products_controller.dart';

/// Products list.
final class ProductsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProductsController>(ProductsController.new, fenix: true);
  }
}

/// Product create / edit.
///
/// The `:id` is read inside the lazy builder rather than in `dependencies()`: bindings can run
/// before GetX has parsed the path parameters, and a null there would silently open the editor as
/// "new product" on an existing SKU. `lazyPut` defers the call to the first `Get.find`, which is
/// the view building — always after the route resolved.
final class ProductEditBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProductEditController>(
      () => ProductEditController(productId: Get.parameters['id']),
      fenix: true,
    );
  }
}
