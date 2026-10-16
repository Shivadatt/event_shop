import 'package:get/get.dart';
import 'package:om_events/features/admin/reviews/reviews_controller.dart';

/// Review moderation screen.
final class ReviewsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ReviewsController>(ReviewsController.new, fenix: true);
  }
}
