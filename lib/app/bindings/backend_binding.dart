import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';

/// Agent 3 owns this file. It is the only place repository implementations are bound, so the
/// rest of the app depends on the abstract types in `lib/data/repositories/` and never on a
/// Firestore class.
///
/// Replace the body with `Get.lazyPut<AuthRepository>(...)`, `<ProductRepository>`, etc. Keep the
/// class name: `main.dart` registers it before the first route resolves.
final class BackendBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SessionStore>()) {
      Get.put<SessionStore>(SessionStore(), permanent: true);
    }
  }
}
