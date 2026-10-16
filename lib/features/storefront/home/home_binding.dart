import 'package:get/get.dart';
import 'package:om_events/features/storefront/home/home_controller.dart';

final class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HomeController>(HomeController.new, fenix: true);
  }
}
