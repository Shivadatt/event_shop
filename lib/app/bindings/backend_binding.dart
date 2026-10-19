import 'package:get/get.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/data/repositories/firestore/firestore_account_repository.dart';
import 'package:om_events/data/repositories/firestore/firestore_admin_repository.dart';
import 'package:om_events/data/repositories/firestore/firestore_auth_repository.dart';
import 'package:om_events/data/repositories/firestore/firestore_catalog_repository.dart';
import 'package:om_events/data/repositories/firestore/firestore_order_repository.dart';
import 'package:om_events/data/repositories/firestore/unconfigured_backend.dart';
import 'package:om_events/data/repositories/order_repository.dart';

/// Agent 3 owns this file: the single place repository *implementations* are bound. Everything else
/// depends on the abstract types and never imports a Firestore class.
///
/// When Firebase is not configured the unconfigured implementations are bound instead — real types
/// whose every call throws an [OmFailure] — so the app never renders invented merchandise. `fenix:
/// true` lets GetX recreate a repository after disposal; each reads the [SessionStore] singleton,
/// so recreation is cheap and stateless.
final class BackendBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SessionStore>()) {
      Get.put<SessionStore>(SessionStore(), permanent: true);
    }
    // Recently-viewed is session-local browsing history, not Firebase data, so it works either way.
    if (!Get.isRegistered<RecentlyViewedRepository>()) {
      Get.lazyPut<RecentlyViewedRepository>(LocalRecentlyViewedRepository.new, fenix: true);
    }
    if (Env.hasFirebase) {
      _bindLive();
    } else {
      _bindUnconfigured();
    }
  }

  void _bindLive() {
    final session = Get.find<SessionStore>();
    _lazyPut<AuthRepository>(() => FirestoreAuthRepository(session));
    _lazyPut<ProductRepository>(FirestoreProductRepository.new);
    _lazyPut<CategoryRepository>(FirestoreCategoryRepository.new);
    _lazyPut<VariantRepository>(() => FirestoreVariantRepository(session));
    _lazyPut<CouponRepository>(FirestoreCouponRepository.new);
    _lazyPut<OrderRepository>(() => FirestoreOrderRepository(session));
    // One account class satisfies four interfaces; bind each type to its own fenix instance.
    _lazyPut<AddressRepository>(() => FirestoreAccountRepository(session));
    _lazyPut<WishlistRepository>(() => FirestoreAccountRepository(session));
    _lazyPut<ReviewRepository>(() => FirestoreAccountRepository(session));
    _lazyPut<AccountRepository>(() => FirestoreAccountRepository(session));
    _lazyPut<AdminRepository>(FirestoreAdminRepository.new);
  }

  void _bindUnconfigured() {
    _lazyPut<AuthRepository>(UnconfiguredAuthRepository.new);
    _lazyPut<ProductRepository>(UnconfiguredProductRepository.new);
    _lazyPut<CategoryRepository>(UnconfiguredCategoryRepository.new);
    _lazyPut<VariantRepository>(UnconfiguredVariantRepository.new);
    _lazyPut<CouponRepository>(UnconfiguredCouponRepository.new);
    _lazyPut<OrderRepository>(UnconfiguredOrderRepository.new);
    _lazyPut<AddressRepository>(UnconfiguredAccountRepository.new);
    _lazyPut<WishlistRepository>(UnconfiguredAccountRepository.new);
    _lazyPut<ReviewRepository>(UnconfiguredAccountRepository.new);
    _lazyPut<AccountRepository>(UnconfiguredAccountRepository.new);
    _lazyPut<AdminRepository>(UnconfiguredAdminRepository.new);
  }

  void _lazyPut<T>(T Function() builder) {
    if (!Get.isRegistered<T>()) {
      Get.lazyPut<T>(builder, fenix: true);
    }
  }
}
