import 'package:flutter/widgets.dart' show RouteSettings;
import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';

/// `/checkout` only. Guest checkout is a *store setting* (`StoreSettings.allowGuestCheckout`),
/// not a property of the route, so the blanket [AuthGuard] used to kill the flow before the
/// controller's `guestAllowed` / `guestGate` logic could ever run.
///
/// Decisions, in order:
///  * a blocked account lands where `AuthGuard` sent it (`/account?reason=blocked`);
///  * a signed-in buyer passes untouched;
///  * a signed-out visitor passes **unless** the settings cache is already live and says guest
///    checkout is off — then they go to login with the same `return=/checkout` argument
///    `AuthGuard` emitted, so nothing visible changes for that store;
///  * when the first load of `store_settings` has not landed yet, the guard cannot await it
///    (GetMiddleware redirects are synchronous), so the visitor reaches the page and
///    `CheckoutController` — which watches `SettingsStore` from `onInit` and keeps the
///    `guestGate` check in its validators — bounces them to login the moment the setting
///    arrives saying "off".
///
/// The authoritative guest-order validation still happens in `ordersCreate` server-side;
/// this guard is UX and defence-in-depth, exactly like the others.
final class CheckoutGuard extends GetMiddleware {
  CheckoutGuard({super.priority = 5});

  @override
  RouteSettings? redirect(String? route) {
    final session = Get.isRegistered<SessionStore>()
        ? Get.find<SessionStore>()
        : SessionStore();
    if (session.isBlocked) {
      return const RouteSettings(name: '${OmRoutes.account}?reason=blocked');
    }
    if (session.isSignedIn) return null;
    if (Get.isRegistered<SettingsStore>()) {
      final settings = Get.find<SettingsStore>();
      if (settings.isLive && !settings.value.allowGuestCheckout) {
        final target = route ?? OmRoutes.checkout;
        return RouteSettings(
          name: '${OmRoutes.login}?${OmRouteArgs.returnUrl}='
              '${Uri.encodeComponent(target)}',
        );
      }
    }
    return null;
  }
}
