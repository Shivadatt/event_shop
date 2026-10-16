import 'package:get/get.dart';
import 'package:om_events/features/admin/coupons/coupons_controller.dart';

/// Coupons list plus the inline create/edit form. The editor is a separate controller so the list
/// never accumulates draft state.
final class CouponsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CouponsController>(CouponsController.new, fenix: true);
    Get.lazyPut<CouponEditController>(CouponEditController.new, fenix: true);
  }
}
