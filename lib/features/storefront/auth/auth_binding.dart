import 'package:get/get.dart';
import 'package:om_events/features/storefront/auth/auth_controller.dart';
import 'package:om_events/features/storefront/common/storefront_binding.dart';

/// Page bindings for the four auth screens. Each page also carries [StorefrontBinding] so the
/// shared cart/settings stores exist even when a visitor opens `/login` as their first URL.
final class LoginBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<LoginController>(LoginController.new, fenix: true);
  }
}

final class RegisterBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<RegisterController>(RegisterController.new, fenix: true);
  }
}

final class ForgotPasswordBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<ForgotPasswordController>(ForgotPasswordController.new, fenix: true);
  }
}

final class ResetPasswordBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<ResetPasswordController>(ResetPasswordController.new, fenix: true);
  }
}
