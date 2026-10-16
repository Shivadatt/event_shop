import 'package:get/get.dart';
import 'package:om_events/features/admin/dashboard/dashboard_controller.dart';

/// Repositories come from `AppRootBinding`, which runs before the first route resolves; a feature
/// binding only owns the controllers for its own page.
final class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DashboardController>(DashboardController.new, fenix: true);
  }
}
