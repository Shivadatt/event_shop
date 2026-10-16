import 'package:get/get.dart';
import 'package:om_events/features/admin/settings/settings_controller.dart';

/// Store settings screen.
final class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SettingsController>(SettingsController.new, fenix: true);
  }
}
