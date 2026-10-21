import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/categories_store.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';

/// Registered on every storefront `GetPage`. Keeps the cart and the public settings alive across
/// navigation without touching global bindings owned by other agents.
final class StorefrontBinding extends Bindings {
  @override
  void dependencies() {
    final get = GetInstance();
    if (!get.isRegistered<SessionStore>()) {
      get.lazyPut<SessionStore>(SessionStore.new, fenix: true);
    }
    if (!get.isRegistered<CartStore>()) {
      get.put<CartStore>(CartStore(), permanent: true);
    }
    // `BackendBinding` registers the Firestore-backed reader whenever Firebase is configured. If
    // nothing is registered, this store runs against a backend that does not exist, so bind the
    // placeholder whose `load()` throws and `SettingsStore` reports that instead of quietly
    // serving `StoreSettings.fallback` as if it were the live document.
    if (!get.isRegistered<StoreSettingsRepository>()) {
      get.lazyPut<StoreSettingsRepository>(
        UnboundStoreSettingsRepository.new,
        fenix: true,
      );
    }
    if (!get.isRegistered<SettingsStore>()) {
      get.put<SettingsStore>(SettingsStore(), permanent: true);
    }
    if (!get.isRegistered<CategoriesStore>()) {
      get.lazyPut<CategoriesStore>(CategoriesStore.new, fenix: true);
    }
  }
}
