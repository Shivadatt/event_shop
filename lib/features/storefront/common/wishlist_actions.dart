import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';

/// One place for the heart button behaviour so a signed-out tap lands on login with a `return`
/// target instead of silently failing on a permission-denied write.
mixin WishlistToggleMixin on GetxController {
  bool wished(String productId) =>
      Get.find<SessionStore>().profile?.wishlistProductIds.contains(productId) ?? false;

  /// Returns the new saved state, or null when the call failed or the buyer was bounced to
  /// login. Callers use the boolean only for optimistic icon flicker; the session profile is the
  /// source of truth.
  Future<bool?> toggleWishlist(Product product) async {
    final session = Get.find<SessionStore>();
    if (!session.isSignedIn) {
      Get.toNamed<dynamic>(
        OmRoutes.login,
        parameters: <String, String>{
          OmRouteArgs.returnUrl: Uri.encodeComponent(Get.currentRoute),
        },
      );
      return null;
    }
    final add = !(session.profile?.wishlistProductIds.contains(product.id) ?? false);
    bool? result;
    await safeCall<void>(
      () async => result = await Get.find<WishlistRepository>().toggle(product.id, add: add),
      onFailure: (_) => result = null,
    );
    return result;
  }
}
