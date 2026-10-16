import 'package:get/get.dart';
import 'package:om_events/features/admin/orders/orders_controller.dart';

/// Routes for the orders area bind exactly one controller each; repositories come from
/// `AppRootBinding`, so they are not re-bound here.
final class OrdersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OrdersController>(OrdersController.new, fenix: true);
  }
}

/// `id` is read inside the lazy builder: bindings can run before GetX has parsed the path
/// parameters, so reading `Get.parameters` in `dependencies()` would capture null.
final class OrderDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OrderDetailController>(
      () => OrderDetailController(orderId: Get.parameters['id'] ?? ''),
      fenix: true,
    );
  }
}
