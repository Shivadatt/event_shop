import 'package:get/get.dart';
import 'package:om_events/features/admin/wholesale/wholesale_controller.dart';

/// Wholesale applications queue.
final class WholesaleBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<WholesaleController>(WholesaleController.new, fenix: true);
  }
}
