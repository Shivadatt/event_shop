import 'package:get/get.dart';
import 'package:om_events/features/storefront/account/account_controller.dart';
import 'package:om_events/features/storefront/account/account_data_controller.dart';
import 'package:om_events/features/storefront/account/account_order_controller.dart';
import 'package:om_events/features/storefront/common/storefront_binding.dart';
import 'package:om_events/features/storefront/orders/order_list_controller.dart';

/// Page bindings for the account area. Each composes [StorefrontBinding] so the shared stores
/// exist even when the buyer's first URL of the session is a deep link into `/account/...`.
final class AccountHomeBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<AccountHomeController>(AccountHomeController.new, fenix: true);
  }
}

final class ProfileBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<ProfileController>(ProfileController.new, fenix: true);
  }
}

final class OrderListBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<OrderListController>(OrderListController.new, fenix: true);
  }
}

final class AccountOrderBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<AccountOrderController>(AccountOrderController.new, fenix: true);
  }
}

final class OrderSuccessBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<OrderSuccessController>(OrderSuccessController.new, fenix: true);
  }
}

final class AddressBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<AddressController>(AddressController.new, fenix: true);
  }
}

final class WishlistBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<WishlistController>(WishlistController.new, fenix: true);
  }
}

final class NotificationBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<NotificationController>(NotificationController.new, fenix: true);
  }
}

final class SupportBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<SupportController>(SupportController.new, fenix: true);
  }
}

final class AccountSettingsBinding extends Bindings {
  @override
  void dependencies() {
    StorefrontBinding().dependencies();
    Get.lazyPut<AccountSettingsController>(AccountSettingsController.new, fenix: true);
  }
}
