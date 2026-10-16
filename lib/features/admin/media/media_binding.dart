import 'package:get/get.dart';
import 'package:om_events/features/admin/media/media_controller.dart';

/// Media library screen.
final class MediaBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MediaController>(MediaController.new, fenix: true);
  }
}
