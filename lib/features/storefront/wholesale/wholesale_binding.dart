import 'package:get/get.dart';
import 'package:om_events/features/storefront/common/storefront_binding.dart';
import 'package:om_events/features/storefront/wholesale/wholesale_controller.dart';

/// Wholesale tool bindings. [BulkOrderBinding] is fenix so a buyer can jump from the grid to the
/// quotation form and back without losing the pasted list.
final class WholesaleApplyBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<WholesaleApplyController>(WholesaleApplyController.new, fenix: true);
  }
}

final class BulkOrderBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<BulkOrderController>(BulkOrderController.new, fenix: true);
  }
}

final class WholesaleQuotationBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<WholesaleQuotationController>(WholesaleQuotationController.new, fenix: true);
  }
}
