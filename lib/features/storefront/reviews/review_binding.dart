import 'package:get/get.dart';
import 'package:om_events/features/storefront/common/storefront_binding.dart';
import 'package:om_events/features/storefront/reviews/review_controller.dart';

/// `/review/:productId`.
final class ReviewComposeBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<ReviewComposeController>(ReviewComposeController.new, fenix: true);
  }
}
