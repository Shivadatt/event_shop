import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/address.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/data/repositories/order_repository.dart';
import 'package:om_events/features/storefront/cart/cart_controller.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';

/// Where the buyer is in the checkout flow.
enum CheckoutStep {
  contact('Contact', 'How do we reach you?'),
  delivery('Delivery', 'Where should it go?'),
  review('Review', 'Check it, then place the order.');

  const CheckoutStep(this.label, this.subtitle);
  final String label;
  final String subtitle;

  static List<CheckoutStep> get ordered => CheckoutStep.values;
}

/// One difference between this page's estimate and the server's confirmed bill.
final class CheckoutChange {
  const CheckoutChange({
    required this.label,
    required this.estimatePaise,
    required this.serverPaise,
  });

  final String label;
  final int estimatePaise;
  final int serverPaise;

  int get deltaPaise => serverPaise - estimatePaise;
  bool get isMoved => deltaPaise != 0;
}

/// `/checkout`.
///
/// Authority: this controller builds an `OrderDraft` of **intent only** (ids, quantities,
/// contact, delivery mode, coupon code, payment choice) and hands it to
/// `OrderRepository.createOrder` — the trusted `orders.createOrder` function. The payable figure
/// the buyer is finally shown comes from that receipt, never from the local `CartTotals` estimate,
/// which exists only so a disagreement can be displayed and explicitly accepted.
final class CheckoutController extends GetxController {
  final GlobalKey<FormState> contactForm = GlobalKey<FormState>();
  final GlobalKey<FormState> deliveryForm = GlobalKey<FormState>();

  final TextEditingController name = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController line1 = TextEditingController();
  final TextEditingController line2 = TextEditingController();
  final TextEditingController city = TextEditingController();
  final TextEditingController state = TextEditingController();
  final TextEditingController pincode = TextEditingController();
  final TextEditingController gstNumber = TextEditingController();
  final TextEditingController customerNote = TextEditingController();
  final TextEditingController declineReason = TextEditingController();

  final Rx<CheckoutStep> step = CheckoutStep.contact.obs;
  final RxBool saveAddressToBook = false.obs;
  final RxBool placing = false.obs;
  final RxBool changesAccepted = false.obs;
  final RxBool loadingAddresses = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final Rxn<OmFailure> addressFailure = Rxn<OmFailure>();
  final Rxn<OmFailure> placeFailure = Rxn<OmFailure>();
  final RxList<AddressBookEntry> addresses = <AddressBookEntry>[].obs;
  final Rxn<AddressBookEntry> selectedAddress = Rxn<AddressBookEntry>();
  final Rx<DeliveryMode> deliveryMode = DeliveryMode.courier.obs;

  /// Mirrors the pincode field so zone lookup is reactive; a `TextEditingController` on its own
  /// is not observable.
  final RxString activePincode = RxString('');
  final RxString paymentCode = RxString('');

  void _syncPincode() => activePincode.value = pincode.text.trim();

  /// Non-null while the server's receipt disagrees with the estimate and the buyer has not yet
  /// accepted it. At that point the order already exists — see [declineChanges].
  final Rxn<OrderReceipt> awaitingConfirmation = Rxn<OrderReceipt>();
  final Rxn<Order> serverOrder = Rxn<Order>();

  @override
  void onInit() {
    super.onInit();
    final profile = Get.find<SessionStore>().profile;
    if (profile != null) {
      name.text = profile.displayName;
      email.text = profile.email;
      phone.text = profile.phone;
      gstNumber.text = profile.gstNumber;
    }
    pincode.addListener(_syncPincode);
    loadAddresses();
  }

  @override
  void onClose() {
    pincode.removeListener(_syncPincode);
    for (final controller in <TextEditingController>[
      name,
      email,
      phone,
      line1,
      line2,
      city,
      state,
      pincode,
      gstNumber,
      customerNote,
      declineReason,
    ]) {
      controller.dispose();
    }
    super.onClose();
  }

  /// Public so the shared [CouponField] can be reused here instead of duplicating the coupon UI.
  CartController get cartController => Get.find<CartController>();
  CartController get _cart => cartController;
  CartStore get _cartStore => Get.find<CartStore>();
  StoreSettings get _settings => Get.find<SettingsStore>().value;
  bool get isSignedIn => Get.find<SessionStore>().isSignedIn;

  List<CartRow> get rows => _cart.rows;
  Rxn<CouponQuote> get couponQuote => _cart.quote;
  bool get applyingCoupon => _cart.applyingCoupon.value;
  OmFailure? get couponFailure => _cart.couponFailure.value;
  String get appliedCouponCode => _cart.quoteFor.value;

  /// Guest checkout is a store setting, so the page — not the route guard, which cannot await —
  /// bounces to login when it is switched off.
  bool get guestAllowed => _settings.allowGuestCheckout;
  bool get isGuestCheckout => !isSignedIn;

  String? get guestGate {
    if (guestAllowed) return null;
    return isSignedIn
        ? null
        : 'This store requires an account before ordering. Sign in and your cart will be here.';
  }

  // ── Display maths (PricingEngine only) ─────────────────────────────────────────────────────

  int get merchandisePaise => rows
      .where((row) => row.canPrice)
      .fold(0, (sum, row) => sum + row.price.resolution.lineTotalPaise);

  ShippingZone? get zone {
    final code = activePincode.value;
    if (code.length != 6) return null;
    return _settings.zoneFor(code);
  }

  bool get pickupEnabled => _settings.isPickupEnabled;
  bool get isPickup => deliveryMode.value == DeliveryMode.pickup;

  /// Estimate only; `createOrder` may answer differently. That is what [changes] reports.
  int get shippingPaise {
    if (isPickup) return 0;
    final free = _settings.freeShippingAbovePaise;
    if (free != null && free > 0 && merchandisePaise >= free) return 0;
    final candidate = zone;
    if (candidate == null) return 0;
    return candidate.rateFor(merchandisePaise);
  }

  String get etaLabel {
    if (isPickup) {
      return _settings.pickupNotes.isEmpty
          ? 'Collect from the shop address shown on the review step.'
          : _settings.pickupNotes;
    }
    final candidate = zone;
    if (candidate == null) {
      return activePincode.value.length == 6
          ? 'No published delivery band covers this pincode yet.'
          : 'Enter a pincode to see the delivery estimate.';
    }
    return '${candidate.name}: usually ${candidate.etaLabel}.';
  }

  /// The shop counter address a pickup order is collected from, straight from store settings.
  String get pickupAddress => _settings.fullAddress;

  String? pincodeError(String? value) {    final basic = OmValidators.pincode(value);
    if (basic != null) return basic;
    if (isPickup) return null;
    if (zone == null) {
      return 'We do not ship to this pincode yet — contact us to arrange delivery.';
    }
    return null;
  }

  CartTotals get totals => CartTotals.from(
        rows
            .where((row) => row.canPrice)
            .map((row) => row.price.resolution)
            .toList(growable: false),
        couponDiscountPaise: _cart.quote.value?.discountPaise ?? 0,
        shippingPaise: shippingPaise,
        taxRateBps: _settings.taxRateBps,
        taxInclusive: _settings.taxInclusive,
      );

  /// Lines the local data already knows are unorderable. The server still has the final say;
  /// this only stops an obviously doomed submit.
  List<String> get blockingNotices {
    final notices = <String>[];
    for (final row in rows) {
      final product = row.product;
      if (row.missing || product == null) {
        notices.add('One cart line has not finished loading yet.');
        continue;
      }
      if (product.status != ProductStatus.active) {
        notices.add('${product.name} is no longer on sale — remove it before ordering.');
      }
      final variant = row.variant;
      if (variant != null && !variant.isActive) {
        notices.add('${product.name} (${variant.name}) is not available any more.');
      }
      final violation = row.price.granularity.violationFor(row.line.qty);
      if (violation != null) notices.add('${product.name}: $violation');
    }
    if (notices.isEmpty && _cart.failure.value != null) {
      notices.add(_cart.failure.value!.message);
    }
    return notices;
  }

  // ── Addresses ──────────────────────────────────────────────────────────────────────────────

  Future<void> loadAddresses() async {
    if (!isSignedIn) return;
    loadingAddresses.value = true;
    addressFailure.value = null;
    final loaded = await safeCall<List<AddressBookEntry>>(
      () => Get.find<AddressRepository>().forCurrentUser(),
      onFailure: (f) => addressFailure.value = f,
    );
    loadingAddresses.value = false;
    if (loaded == null) return;
    addresses.assignAll(loaded);
    if (selectedAddress.value != null || pincode.text.isNotEmpty) return;
    for (final entry in loaded) {
      if (entry.isDefaultShipping) {
        selectAddress(entry);
        break;
      }
    }
  }

  void selectAddress(AddressBookEntry entry) {
    selectedAddress.value = entry;
    if (entry.name.isNotEmpty) name.text = entry.name;
    if (entry.phone.isNotEmpty) phone.text = entry.phone;
    line1.text = entry.line1;
    line2.text = entry.line2;
    city.text = entry.city;
    state.text = entry.state;
    pincode.text = entry.pincode;
    activePincode.value = entry.pincode.trim();
    if (entry.gstNumber.isNotEmpty) gstNumber.text = entry.gstNumber;
  }

  void useNewAddress() {
    selectedAddress.value = null;
    line1.clear();
    line2.clear();
    city.clear();
    state.clear();
    pincode.clear();
    activePincode.value = '';
  }

  /// Saving to the address book is a signed-in write; a guest simply proceeds and the typed
  /// address is snapshotted into the order by the server.
  Future<void> persistAddress() async {
    final uid = Get.find<SessionStore>().uid;
    if (!saveAddressToBook.value || uid == null) return;
    await safeCall<AddressBookEntry>(
      () => Get.find<AddressRepository>().save(
        AddressBookEntry(
          id: '',
          uid: uid,
          name: name.text.trim(),
          phone: phone.text.trim(),
          line1: line1.text.trim(),
          line2: line2.text.trim(),
          city: city.text.trim(),
          state: state.text.trim(),
          pincode: pincode.text.trim(),
          gstNumber: gstNumber.text.trim(),
        ),
      ),
      onFailure: (f) => addressFailure.value = f,
    );
  }

  // ── Coupon ─────────────────────────────────────────────────────────────────────────────────
  // The quote itself lives on CartController (one server read per code, shared by cart and
  // checkout) so the code cannot be applied in one place and stale in the other.

  // ── Payment methods ────────────────────────────────────────────────────────────────────────

  List<PaymentMethodOption> get offeredMethods =>
      _settings.paymentMethods.where((m) => m.isEnabled).toList(growable: false);

  /// Eligibility is the store's own predicate applied to the *estimate*. The server re-checks it;
  /// nothing here can enable a method.
  bool isMethodAllowedFor(PaymentMethodOption option) =>
      option.isAllowedFor(totals.payableRoundedPaise);

  String? methodBlockReason(PaymentMethodOption option) {
    if (!option.isEnabled) return 'The store has switched this method off.';
    if (totals.payableRoundedPaise < option.minAmountPaise) {
      return 'Needs an order of at least ${OmMoney.format(option.minAmountPaise)}.';
    }
    final max = option.maxAmountPaise;
    if (max != null && totals.payableRoundedPaise > max) {
      return 'Not available above ${OmMoney.format(max)}.';
    }
    return null;
  }

  PaymentMethodOption? get selectedMethod =>
      paymentCode.value.isEmpty ? null : _settings.paymentMethod(paymentCode.value);

  void selectPayment(String code) {
    final option = _settings.paymentMethod(code);
    if (option == null || !isMethodAllowedFor(option)) return;
    paymentCode.value = code;
  }

  bool get isCodSelected => paymentCode.value.toLowerCase().contains('cod');

  // ── Step navigation ────────────────────────────────────────────────────────────────────────

  void next() {
    if (!validateCurrentStep()) return;
    final index = step.value.index;
    if (index < CheckoutStep.ordered.length - 1) step.value = CheckoutStep.ordered[index + 1];
  }

  void back() {
    final index = step.value.index;
    if (index > 0) step.value = CheckoutStep.ordered[index - 1];
  }

  void jumpTo(CheckoutStep target) {
    failure.value = null;
    step.value = target;
  }

  bool validateCurrentStep() {
    if (step.value == CheckoutStep.contact) {
      final gate = guestGate;
      if (gate != null) {
        failure.value = ValidationFailure(gate);
        return false;
      }
      return contactForm.currentState?.validate() ?? false;
    }
    if (step.value == CheckoutStep.delivery) {
      if (isPickup && !pickupEnabled) {
        failure.value = const ValidationFailure('This store is not accepting pickup right now.');
        return false;
      }
      if (!(deliveryForm.currentState?.validate() ?? false)) return false;
      final notices = blockingNotices;
      if (notices.isNotEmpty) {
        failure.value = ValidationFailure(notices.first);
        return false;
      }
      return true;
    }
    return true;
  }

  /// Which step owns the first problem with the draft, checked against the field values rather
  /// than the mounted form (the earlier steps are unmounted by the time the buyer confirms).
  ({String message, CheckoutStep step})? submitIssueFor(CheckoutStep target) {
    final gate = guestGate;
    if (gate != null) return (message: gate, step: CheckoutStep.contact);

    final nameError = OmValidators.required(name.text, label: 'Full name');
    if (nameError != null) {
      return (message: 'Add the name this order is for.', step: CheckoutStep.contact);
    }
    final emailError = OmValidators.email(email.text);
    if (emailError != null) return (message: emailError, step: CheckoutStep.contact);
    final phoneError = OmValidators.phone(phone.text);
    if (phoneError != null) return (message: phoneError, step: CheckoutStep.contact);

    if (!isPickup) {
      final addressError = OmValidators.required(line1.text, label: 'Address');
      if (addressError != null) {
        return (message: 'Add a delivery address.', step: CheckoutStep.delivery);
      }
      final cityError = OmValidators.required(city.text, label: 'City');
      if (cityError != null) return (message: 'Add your city.', step: CheckoutStep.delivery);
      final stateError = OmValidators.required(state.text, label: 'State');
      if (stateError != null) return (message: 'Add your state.', step: CheckoutStep.delivery);
      final pincodeProblem = pincodeError(pincode.text);
      if (pincodeProblem != null) return (message: pincodeProblem, step: CheckoutStep.delivery);
    }

    if (target == CheckoutStep.review) {
      final notices = blockingNotices;
      if (notices.isNotEmpty) {
        return (message: notices.first, step: CheckoutStep.review);
      }
      if (paymentCode.value.isEmpty) {
        return (message: 'Choose how you want to pay.', step: CheckoutStep.review);
      }
    }
    return null;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────────────────────

  ShippingSnapshot buildShippingSnapshot() {
    if (isPickup) {
      return ShippingSnapshot(
        name: name.text.trim(),
        phone: phone.text.trim(),
        line1: _settings.fullAddress,
        city: _settings.city,
        state: _settings.state,
        pincode: _settings.pincode,
        gstNumber: gstNumber.text.trim(),
        addressId: selectedAddress.value?.id,
      );
    }
    return ShippingSnapshot(
      name: name.text.trim(),
      phone: phone.text.trim(),
      line1: line1.text.trim(),
      line2: line2.text.trim(),
      city: city.text.trim(),
      state: state.text.trim(),
      pincode: pincode.text.trim(),
      gstNumber: gstNumber.text.trim(),
      addressId: selectedAddress.value?.id,
    );
  }

  OrderDraft buildDraft() => OrderDraft(
        lines: <DraftLine>[
          for (final row in rows)
            if (row.product != null)
              DraftLine(
                productId: row.line.productId,
                variantId: row.line.variantId,
                qty: row.line.qty,
              ),
        ],
        deliveryMode: deliveryMode.value,
        shipping: buildShippingSnapshot(),
        customerNote: customerNote.text.trim(),
        contactEmail: email.text.trim(),
        contactPhone: phone.text.trim(),
        couponCode: _cartStore.couponCode.value ?? '',
        paymentMethod: paymentCode.value,
        idempotencyKey: _cartStore.idempotencyKey,
        grandTotalPaiseForComparison: totals.payableRoundedPaise,
      );

  /// The one place an order is created. Retrying with the same `idempotencyKey` cannot produce a
  /// second charge: the function replays the existing receipt instead.
  Future<void> placeOrder() async {
    if (placing.value) return;
    final issue = submitIssueFor(CheckoutStep.review);
    if (issue != null) {
      failure.value = ValidationFailure(issue.message);
      step.value = issue.step;
      return;
    }
    placing.value = true;
    placeFailure.value = null;
    changesAccepted.value = false;
    final estimate = totals;
    final receipt = await safeCall<OrderReceipt>(
      () => Get.find<OrderRepository>().createOrder(buildDraft()),
      onFailure: (f) => placeFailure.value = f,
    );
    placing.value = false;
    if (receipt == null) return;

    _cartStore.lastReceipt.value = receipt;
    await _loadServerOrder(receipt);

    if (receipt.priceChanged || receipt.wasReplay) {
      // The order already exists on the server. The buyer must see exactly what moved and say
      // yes before we hand over the success page — never a silent accept.
      failure.value = null;
      step.value = CheckoutStep.review;
      awaitingConfirmation.value = receipt;
      return;
    }
    completeCheckout(receipt);
  }

  Future<void> _loadServerOrder(OrderReceipt receipt) async {
    final repository = Get.find<OrderRepository>();
    serverOrder.value = isSignedIn
        ? await safeCall<Order>(() => repository.byId(receipt.orderId))
        : await safeCall<Order>(
            () => repository.byOrderNumber(
              receipt.orderNumber,
              contactEmail: email.text.trim(),
            ),
          );
  }

  /// Estimate-vs-server differences, aggregated first and then per line when the order document
  /// was readable.
  List<CheckoutChange> get changes {
    final receipt = awaitingConfirmation.value;
    if (receipt == null) return const <CheckoutChange>[];
    final estimate = totals;
    final confirmed = receipt.totals;
    final list = <CheckoutChange>[
      CheckoutChange(
        label: 'Merchandise total',
        estimatePaise: estimate.subtotalPaise,
        serverPaise: confirmed.subtotalPaise,
      ),
      CheckoutChange(
        label: 'Quantity (slab) savings',
        estimatePaise: estimate.slabSavingsPaise,
        serverPaise: confirmed.slabDiscountPaise,
      ),
      CheckoutChange(
        label: 'Coupon discount',
        estimatePaise: estimate.couponDiscountPaise,
        serverPaise: confirmed.couponDiscountPaise,
      ),
      CheckoutChange(
        label: 'Shipping',
        estimatePaise: estimate.shippingPaise,
        serverPaise: confirmed.shippingPaise,
      ),
      CheckoutChange(
        label: 'GST',
        estimatePaise: estimate.taxPaise,
        serverPaise: confirmed.taxPaise,
      ),
      CheckoutChange(
        label: 'Round off',
        estimatePaise: 0,
        serverPaise: confirmed.roundingPaise,
      ),
      CheckoutChange(
        label: 'Payable',
        estimatePaise: estimate.payableRoundedPaise,
        serverPaise: confirmed.grandTotalPaise,
      ),
    ];

    final order = serverOrder.value;
    if (order != null) {
      for (final item in order.items) {
        CartRow? match;
        for (final row in rows) {
          if (row.line.productId == item.productId && row.line.variantId == item.variantId) {
            match = row;
            break;
          }
        }
        final moved = match == null ||
            !match.canPrice ||
            match.line.qty != item.qty ||
            match.price.resolution.lineTotalPaise != item.lineTotalPaise;
        if (moved) {
          list.add(
            CheckoutChange(
              label: '${item.name} — ${item.qty} ${item.unit}',
              estimatePaise: match == null ? 0 : match.price.resolution.lineTotalPaise,
              serverPaise: item.lineTotalPaise,
            ),
          );
        }
      }
    }

    final visible =
        list.where((change) => change.isMoved || change.label == 'Payable').toList(growable: false);
    return visible.isEmpty
        ? <CheckoutChange>[
            CheckoutChange(
              label: 'Nothing in the bill changed',
              estimatePaise: estimate.payableRoundedPaise,
              serverPaise: confirmed.grandTotalPaise,
            ),
          ]
        : visible;
  }

  String get confirmationHeadline {
    final receipt = awaitingConfirmation.value;
    if (receipt == null) return '';
    if (receipt.wasReplay && receipt.priceChanged) {
      return 'This order already existed, and its total has moved';
    }
    if (receipt.wasReplay) {
      return 'This order was already created — no second charge was made';
    }
    return 'Our price for this order changed when we checked it';
  }

  /// Explicit acceptance of a changed total. Without the tick the continue action does not exist.
  void acceptChangesAndContinue() {
    final receipt = awaitingConfirmation.value;
    if (receipt == null || !changesAccepted.value) return;
    completeCheckout(receipt);
  }

  /// The buyer refuses the new total: the order the server already created is sent back for
  /// cancellation through the repository, so nothing is quietly left open.
  Future<void> declineChanges() async {
    final receipt = awaitingConfirmation.value;
    if (receipt == null || placing.value) return;
    placing.value = true;
    placeFailure.value = null;
    final reason = declineReason.text.trim().isEmpty
        ? 'Total changed after review; buyer declined the updated amount.'
        : declineReason.text.trim();
    final ok = await tryCall(
      () => Get.find<OrderRepository>().requestCancellation(receipt.orderId, reason: reason),
      onFailure: (f) => placeFailure.value = f,
    );
    placing.value = false;
    if (!ok) return;
    awaitingConfirmation.value = null;
    serverOrder.value = null;
    Get.snackbar(
      'Cancellation requested',
      'We asked the store to release ${receipt.orderNumber}. Your cart is untouched.',
      snackDuration: const Duration(seconds: 5),
    );
  }

  void completeCheckout(OrderReceipt receipt) {
    awaitingConfirmation.value = null;
    _cartStore.clearCart();
    Get.offNamed<dynamic>(OmRoutes.forOrderSuccess(receipt.orderId));
  }

  void goToLogin() {
    Get.toNamed<dynamic>(
      OmRoutes.login,
      parameters: <String, String>{
        OmRouteArgs.returnUrl: Uri.encodeComponent(OmRoutes.checkout),
      },
    );
  }

  void openCart() => Get.toNamed<dynamic>(OmRoutes.cart);

  void retrySettings() => Get.find<SettingsStore>().load();
}
