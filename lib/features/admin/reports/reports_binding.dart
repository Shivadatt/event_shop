import 'package:get/get.dart';
import 'package:om_events/features/admin/reports/reports_controller.dart';

/// Reports screen.
final class ReportsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ReportsController>(ReportsController.new, fenix: true);
  }
}
