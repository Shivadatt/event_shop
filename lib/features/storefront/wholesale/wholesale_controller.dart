import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/line_price.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';

/// `/wholesale/apply`. Approval is the store's decision — recorded by `AuthRepository` and
/// mirrored back through the session profile, never by this form.
final class WholesaleApplyController extends GetxController {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController companyName = TextEditingController();
  final TextEditingController contactName = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController gstNumber = TextEditingController();
  final TextEditingController address = TextEditingController();
  final TextEditingController reason = TextEditingController();
  final TextEditingController expectedMonthlyVolume = TextEditingController();

  final RxBool busy = false.obs;
  final RxBool done = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  UserProfile? get profile => Get.find<SessionStore>().profile;
  WholesaleStatus get status => profile?.wholesaleStatus ?? WholesaleStatus.none;
  bool get isApproved => status == WholesaleStatus.approved;

  @override
  void onInit() {
    super.onInit();
    final p = profile;
    companyName.text = p?.companyName ?? '';
    contactName.text = p?.displayName ?? '';
    phone.text = p?.phone ?? '';
    gstNumber.text = p?.gstNumber ?? '';
  }

  @override
  void onClose() {
    for (final controller in <TextEditingController>[
      companyName,
      contactName,
      phone,
      gstNumber,
      address,
      reason,
      expectedMonthlyVolume,
    ]) {
      controller.dispose();
    }
    super.onClose();
  }

  Future<void> submit() async {
    if (busy.value) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    busy.value = true;
    failure.value = null;
    final gst = gstNumber.text.trim();
    final ok = await tryCall(
      () => Get.find<AuthRepository>().applyForWholesale(
        companyName: companyName.text.trim(),
        contactName: contactName.text.trim(),
        phone: phone.text.trim(),
        gstNumber: gst.isEmpty ? null : gst.toUpperCase(),
        address: address.text.trim().isEmpty ? null : address.text.trim(),
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
        expectedMonthlyVolume: expectedMonthlyVolume.text.trim().isEmpty
            ? null
            : expectedMonthlyVolume.text.trim(),
      ),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    done.value = ok;
  }

  String? validateCompany(String? value) =>
      OmValidators.required(value, label: 'Company name');

  String? validateContact(String? value) =>
      OmValidators.required(value, label: 'Contact person');

  String? validatePhone(String? value) => OmValidators.phone(value);
}

/// One resolved row of the bulk grid. `price` is display math from `PricingEngine`; what the buyer
/// pays is only ever what `OrderRepository.createOrder` returns.
final class BulkRow {
  const BulkRow({
    required this.input,
    required this.qty,
    this.product,
    this.price,
    this.warning,
    this.error,
  });

  final String input;
  final int qty;
  final Product? product;
  final LinePrice? price;

  /// Non-blocking note (e.g. "order in multiples of 24") on an otherwise usable row.
  final String? warning;
  final String? error;

  bool get isValid => error == null && product != null && qty > 0;
}

/// `/wholesale/bulk-order`. Paste SKU + quantity rows, resolve each against the live catalogue,
/// show the slab price per line and keep rejects visible instead of quietly dropping them.
final class BulkOrderController extends GetxController {
  final TextEditingController paste = TextEditingController();
  final RxList<BulkRow> rows = <BulkRow>[].obs;
  final RxBool resolving = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxInt addedCount = 0.obs;

  @override
  void onClose() {
    paste.dispose();
    super.onClose();
  }

  List<String> get inputLines => paste.text
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);

  bool get hasInput => inputLines.isNotEmpty;

  /// Accepts `SKU,50`, `SKU 50`, `SKU:50`, `SKU;50`, `SKU\t50`. A row without a trailing number is
  /// rejected rather than guessed at — a wrong quantity in a bulk order is a real-money mistake.
  static (String, int?) _parse(String line) {
    final parts = line
        .trim()
        .split(RegExp(r'[,;\t]| +|:(?=[0-9])'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return (parts.isEmpty ? '' : parts.first, null);
    final qty = int.tryParse(parts.last);
    if (qty == null) return (parts.first, null);
    return (parts.take(parts.length - 1).join(' '), qty);
  }

  Future<void> resolve() async {
    if (resolving.value) return;
    resolving.value = true;
    failure.value = null;
    addedCount.value = 0;
    final results = <BulkRow>[];
    final repository = Get.find<ProductRepository>();

    for (final line in inputLines) {
      final (input, qty) = _parse(line);
      if (input.isEmpty) continue;
      if (qty == null) {
        results.add(BulkRow(input: input, qty: 0, error: 'No quantity on this row'));
        continue;
      }
      if (qty <= 0) {
        results.add(BulkRow(input: input, qty: qty, error: 'Quantity must be at least 1'));
        continue;
      }

      Product? product;
      String notFoundNote = 'No product matches this SKU or id';
      final bySku = await safeCall<Product>(
        () => repository.bySku(input),
        onFailure: (f) {
          if (f is! NotFoundFailure) notFoundNote = f.message;
        },
      );
      product = bySku ??
          await safeCall<Product>(
            () => repository.byId(input),
            onFailure: (f) {
              if (f is! NotFoundFailure) notFoundNote = f.message;
            },
          );
      if (product == null) {
        results.add(BulkRow(input: input, qty: qty, error: notFoundNote));
        continue;
      }

      final price = priceLine(product: product, qty: qty);
      if (price.hasError) {
        results.add(BulkRow(
          input: input,
          qty: qty,
          product: product,
          price: price,
          error: price.error?.message,
        ));
        continue;
      }
      if (product.status != ProductStatus.active) {
        results.add(BulkRow(
          input: input,
          qty: qty,
          product: product,
          price: price,
          error: 'This product is ${product.status.name} and cannot be ordered',
        ));
        continue;
      }
      final granularity = price.granularity;
      if (qty < granularity.minQty) {
        results.add(BulkRow(
          input: input,
          qty: qty,
          product: product,
          price: price,
          error: 'Minimum order is ${granularity.minQty} ${product.unit}',
        ));
        continue;
      }
      final warning = granularity.multiple > 1 && qty % granularity.multiple != 0
          ? 'Ordered in multiples of ${granularity.multiple} — quantity will be checked at '
              'checkout'
          : null;
      results.add(BulkRow(input: input, qty: qty, product: product, price: price, warning: warning));
    }

    rows.assignAll(results);
    resolving.value = false;
  }

  List<BulkRow> get validRows => rows.where((row) => row.isValid).toList(growable: false);

  List<BulkRow> get rejectedRows =>
      rows.where((row) => !row.isValid).toList(growable: false);

  int get warnCountValue => rows.where((row) => row.isValid && row.warning != null).length;

  /// Only intent goes to the cart. Stock and the payable total are re-checked by the server at
  /// `createOrder`, so nothing here claims a quantity is guaranteed.
  Future<void> addValidLinesToCart() async {
    final cart = Get.find<CartStore>();
    var count = 0;
    for (final row in validRows) {
      final product = row.product;
      if (product == null) continue;
      cart.add(CartLine(productId: product.id, variantId: null, qty: row.qty));
      count++;
    }
    addedCount.value = count;
    if (count == 0) {
      failure.value = const ValidationFailure('Nothing valid to add yet — resolve your lines first.');
      return;
    }
    await Get.toNamed<dynamic>(OmRoutes.cart);
  }

  void clear() {
    paste.clear();
    rows.clear();
    addedCount.value = 0;
    failure.value = null;
  }
}

/// `/wholesale/quotation`.
///
/// NEEDS OWNER: no quotation document or repository method exists yet, so a request is filed as a
/// `wholesaleQuery` support ticket through `AccountRepository` — a real, staff-visible record with
/// a ticket id, not an invented quote number.
final class WholesaleQuotationController extends GetxController {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController heading = TextEditingController();
  final TextEditingController neededBy = TextEditingController();
  final TextEditingController pincode = TextEditingController();
  final TextEditingController items = TextEditingController();
  final Rxn<SupportRequest> ticket = Rxn<SupportRequest>();
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxList<SupportRequest> history = <SupportRequest>[].obs;

  UserProfile? get profile => Get.find<SessionStore>().profile;
  bool get isApproved => profile?.wholesaleStatus == WholesaleStatus.approved;

  @override
  void onInit() {
    super.onInit();
    loadHistory();
  }

  @override
  void onClose() {
    heading.dispose();
    neededBy.dispose();
    pincode.dispose();
    items.dispose();
    super.onClose();
  }

  Future<void> loadHistory() async {
    loading.value = true;
    final mine = await safeCall<List<SupportRequest>>(
      () => Get.find<AccountRepository>().mySupportTickets(),
      onFailure: (f) => failure.value = f,
    );
    loading.value = false;
    if (mine == null) return;
    history.assignAll(
      mine.where((request) => request.topic == SupportTopic.wholesaleQuery).toList(),
    );
  }

  String buildMessage() {
    final company = profile?.companyName ?? '';
    return <String>[
      'Quotation request: ${heading.text.trim()}',
      if (company.isNotEmpty) 'Company: $company',
      if (neededBy.text.trim().isNotEmpty) 'Needed by: ${neededBy.text.trim()}',
      if (pincode.text.trim().isNotEmpty) 'Deliver to pincode: ${pincode.text.trim()}',
      if (items.text.trim().isNotEmpty) 'Items (${items.text.trim().split(RegExp(r'\r?\n')).length} lines):',
      items.text.trim(),
      'Prices, stock and freight are for the store to confirm — this request reserves nothing.',
    ].join('\n');
  }

  Future<void> submit() async {
    if (busy.value) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    busy.value = true;
    failure.value = null;
    final request = await safeCall<SupportRequest>(
      () => Get.find<AccountRepository>().openSupportTicket(
        subject: 'Quotation: ${heading.text.trim()}',
        topic: SupportTopic.wholesaleQuery,
        message: buildMessage(),
      ),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    if (request == null) return;
    ticket.value = request;
    history.insert(0, request);
  }

  /// A quotation often starts from the bulk grid; carrying the pasted text across avoids
  /// retyping 40 SKUs.
  String prefillItems() {
    if (Get.isRegistered<BulkOrderController>()) {
      return Get.find<BulkOrderController>().paste.text;
    }
    return '';
  }

  String? validateHeading(String? value) =>
      OmValidators.required(value, label: 'What you need quoted');

  String? validateItems(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'List at least one item or SKU';
    if (text.split(RegExp(r'\r?\n')).length > 60) {
      return 'Keep a request to 60 lines — send larger lists as a bulk-order session';
    }
    return null;
  }
}
