import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/user_profile.dart';
/// Route guards are a UX convenience and a defence-in-depth layer. They are **not** the
/// permission system: Firestore rules and Cloud Functions re-check the role on every privileged
/// read and write, because nothing in this bundle is trustworthy.
abstract final class _GuardAccess {
  static SessionStore get session {
    if (!Get.isRegistered<SessionStore>()) return SessionStore();
    return Get.find<SessionStore>();
  }
}

/// Blocks a page for signed-out visitors and suspended accounts, remembering where they were
/// headed so login can return them.
final class AuthGuard extends GetMiddleware {
  AuthGuard({super.priority = 5});

  String _withReturn(String? route) {
    final target = route ?? OmRoutes.home;
    return '${OmRoutes.login}?${OmRouteArgs.returnUrl}=${Uri.encodeComponent(target)}';
  }

  @override
  RouteSettings? redirect(String? route) {
    final session = _GuardAccess.session;
    if (session.isBlocked) {
      return const RouteSettings(name: '${OmRoutes.account}?reason=blocked');
    }
    if (!session.isSignedIn) return RouteSettings(name: _withReturn(route));
    return null;
  }
}

/// Staff-area guard. `staff`, `admin` and `owner` pass; a signed-in customer does not, and is
/// sent back to the storefront instead of a login wall they would only loop through.
final class AdminGuard extends GetMiddleware {
  AdminGuard({super.priority = 10});

  @override
  RouteSettings? redirect(String? route) {
    final session = _GuardAccess.session;
    if (session.isBlocked) return const RouteSettings(name: OmRoutes.home);
    if (!session.isSignedIn) {
      return RouteSettings(
        name: '${OmRoutes.login}?${OmRouteArgs.returnUrl}='
            '${Uri.encodeComponent(route ?? OmRoutes.admin)}'
            '&${OmRouteArgs.source}=admin',
      );
    }
    if (!session.role.canManageStore) return const RouteSettings(name: OmRoutes.notFound);
    return null;
  }
}

/// Narrower than [AdminGuard]: pricing, cost price and refunds are owner/admin-only, so a staff
/// account with catalog duties still cannot reprice the store.
final class PricingAdminGuard extends GetMiddleware {
  PricingAdminGuard({super.priority = 12});

  @override
  RouteSettings? redirect(String? route) {
    final session = _GuardAccess.session;
    if (session.isBlocked || !session.role.canEditPricing) {
      return const RouteSettings(name: OmRoutes.notFound);
    }
    return null;
  }
}

/// Keeps a signed-in customer out of the login/register screens, sending them to wherever they
/// were headed, or home.
final class SignedOutOnlyGuard extends GetMiddleware {
  SignedOutOnlyGuard({super.priority = 3});

  @override
  RouteSettings? redirect(String? route) {
    final session = _GuardAccess.session;
    if (!session.isSignedIn) return null;
    if (session.role.canManageStore) return const RouteSettings(name: OmRoutes.admin);
    return const RouteSettings(name: OmRoutes.account);
  }
}

/// Wholesale pricing and bulk-order tools unlock only for an approved account.
final class WholesaleGuard extends GetMiddleware {
  WholesaleGuard({super.priority = 8});

  @override
  RouteSettings? redirect(String? route) {
    final session = _GuardAccess.session;
    if (!session.isSignedIn) {
      return RouteSettings(
        name: '${OmRoutes.login}?${OmRouteArgs.returnUrl}='
            '${Uri.encodeComponent(route ?? OmRoutes.wholesaleApply)}',
      );
    }
    final status = session.profile?.wholesaleStatus ?? WholesaleStatus.none;
    if (status == WholesaleStatus.approved || session.role.canManageStore) return null;
    // Pending, rejected and never-applied all land on the form: only an approval unlocks pricing,
    // and a pending applicant needs to see their own queue position.
    return const RouteSettings(name: OmRoutes.wholesaleApply);
  }
}
