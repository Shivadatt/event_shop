import 'package:get/get.dart';
import 'package:om_events/features/admin/pricing/pricing_controller.dart';

/// Pricing admin screen (guarded by PricingAdminGuard at the route).
final class PricingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PricingController>(PricingController.new, fenix: true);
  }
}
