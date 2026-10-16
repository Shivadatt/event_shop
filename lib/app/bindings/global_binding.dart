import 'package:get/get.dart';
import 'package:om_events/app/bindings/backend_binding.dart';
import 'package:om_events/app/bindings/media_binding.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/session_store.dart';

/// Registers the singletons every feature depends on, before the first route resolves. GetX
/// middleware reads [SessionStore] synchronously, so it cannot be lazily created by a binding on
/// the first page.
final class GlobalBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SessionStore>(SessionStore.new, fenix: true);
  }
}

/// `GetMaterialApp` in this version takes one root binding, so the three owners' bindings are
/// composed here rather than each trying to attach to a different page — a repository that is
/// only bound on `/admin` is not available to a guard that runs on `/`.
final class AppRootBinding extends Bindings {
  @override
  void dependencies() {
    GlobalBinding().dependencies();
    BackendBinding().dependencies();
    MediaBinding().dependencies();
  }
}

/// Feature bindings (Agent 1, 2, 3, 4) attach to their own `GetPage`s. This list is only for
/// things that must exist app-wide.
abstract final class AppServices {
  static bool get backendLive => AppBootstrap.report.isComplete;
}
