import 'package:get/get.dart';
import 'package:om_events/features/admin/customers/customers_controller.dart';

/// Customer list.
final class CustomersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CustomersController>(CustomersController.new, fenix: true);
  }
}

/// One customer. The `:id` is the uid and is read inside the lazy builder, after the route has
/// resolved its path parameters.
final class CustomerDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CustomerDetailController>(
      () => CustomerDetailController(uid: Get.parameters['id'] ?? ''),
      fenix: true,
    );
  }
}
