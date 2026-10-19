import 'dart:async';

import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/data/repositories/order_repository.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/orders/order_actions.dart';

/// `/account/settings`. Notification consent, local housekeeping and sign-out. Everything that
/// changes what the store sends goes through `AuthRepository.updateProfile`.
final class AccountSettingsController extends GetxController {
  final RxBool busy = false.obs;
  final RxBool saved = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxBool clearedHistory = false.obs;

  UserProfile? get profile => Get.find<SessionStore>().profile;

  bool get notifyEmail => profile?.notifyEmail ?? true;
  bool get notifyWhatsapp => profile?.notifyWhatsapp ?? false;
  bool get notifySms => profile?.notifySms ?? false;

  int get cartLineCount => Get.find<CartStore>().lineCount;

  Future<void> setNotify({bool? email, bool? whatsapp, bool? sms}) async {
    busy.value = true;
    failure.value = null;
    final ok = await tryCall(
      () => Get.find<AuthRepository>().updateProfile(
        notifyEmail: email,
        notifyWhatsapp: whatsapp,
        notifySms: sms,
      ),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    saved.value = ok;
  }

  Future<void> clearRecentlyViewed() async {
    busy.value = true;
    failure.value = null;
    final ok = await tryCall(
      () => Get.find<RecentlyViewedRepository>().clear(),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    clearedHistory.value = ok;
  }

  Future<void> signOut() async {
    final ok = await tryCall(() => Get.find<AuthRepository>().signOut());
    if (ok) unawaited(Get.offAllNamed<dynamic>(OmRoutes.home));
  }
}

/// `/account/order/:orderId`. Reads the order the server owns and streams its status. Local state
/// is never a substitute: actions here only ask the backend, they do not write `Order.status`.
final class AccountOrderController extends GetxController with OrderActionsMixin {
  final Rxn<Order> order = Rxn<Order>();
  final RxBool loading = true.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  StreamSubscription<Order>? _watch;

  String get orderId => Get.parameters['orderId'] ?? '';

  @override
  void onInit() {
    super.onInit();
    load();
    _startWatch();
  }

  Future<void> load() async {
    if (orderId.isEmpty) {
      loading.value = false;
      failure.value = const NotFoundFailure('No order id in this link.');
      return;
    }
    loading.value = true;
    failure.value = null;
    final result = await safeCall<Order>(
      () => Get.find<OrderRepository>().byId(orderId),
      onFailure: (f) => failure.value = f,
    );
    loading.value = false;
    if (result != null) order.value = result;
  }

  void _startWatch() {
    if (orderId.isEmpty) return;
    try {
      _watch = Get.find<OrderRepository>().watchOrder(orderId).listen(
        (live) => order.value = live,
        onError: (Object _) {
          // A dropped watch is not a dropped page: the manual reload still works.
        },
      );
    } catch (_) {
      // No repository bound yet: `load()` already surfaced that as an error state.
    }
  }

  Future<void> reviewItem(OrderItem item) async {
    await Get.toNamed<dynamic>(OmRoutes.forReview(item.productId));
  }

  @override
  void onClose() {
    _watch?.cancel();
    super.onClose();
  }
}

/// `/order-success/:orderId`.
///
/// The payable figure shown here comes from `OrderReceipt` (the server's answer), never from a
/// client total. For a guest whose receipt is only in memory, that receipt is the record; for a
/// signed-in buyer the order document is re-read so a later status change is visible.
final class OrderSuccessController extends GetxController {
  final Rxn<Order> order = Rxn<Order>();
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxBool loading = true.obs;

  String get orderId => Get.parameters['orderId'] ?? '';

  OrderReceipt? get receipt => Get.find<CartStore>().lastReceipt.value;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    final result = await safeCall<Order>(
      () => Get.find<OrderRepository>().byId(orderId),
      onFailure: (f) => failure.value = f,
    );
    loading.value = false;
    if (result != null) order.value = result;
  }

  /// A replayed receipt means the buyer may see this page twice for one order; say which case the
  /// server reported instead of implying a fresh charge each time.
  String? get receiptNotice {
    final value = receipt;
    if (value == null) return null;
    if (value.wasReplay && value.priceChanged) {
      return 'This order was created earlier and its total had moved; the amounts below are the '
          'ones the store recorded.';
    }
    if (value.wasReplay) {
      return 'This order was already created — reloading this page did not place it twice.';
    }
    if (value.priceChanged) {
      return 'The store re-priced this order when it confirmed it. The amounts below are '
          'authoritative.';
    }
    return null;
  }

  void openAccountOrders() => Get.offAllNamed<dynamic>(OmRoutes.accountOrders);
  void openOrderDetail() => Get.offNamed<dynamic>(OmRoutes.forOrder(orderId));
  void keepShopping() => Get.offAllNamed<dynamic>(OmRoutes.home);
}
