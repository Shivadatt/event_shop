import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';

/// Store settings editor.
///
/// The singleton document is edited as one immutable draft and saved through `saveSettings`, whose
/// Cloud Function re-checks the role. A percentage is never stored as a double: `taxRateBps` is
/// basis points, and the live ₹ example is derived from it purely for display.
final class SettingsController extends AdminController {
  SettingsController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final Rxn<StoreSettings> draft = Rxn<StoreSettings>();
  final RxnString savedAt = RxnString();

  /// Sections are collapsed by default; the identity block opens on load.
  final RxSet<String> openSections = <String>{}.obs;

  bool get canSeeCost => session.canSeeCostPrice;
  bool get hasDraft => draft.value != null;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final settings = await guard<StoreSettings>(_admin.settings);
    if (settings != null) draft.value = settings;
  }

  void toggleSection(String id) {
    if (openSections.contains(id)) {
      openSections.remove(id);
    } else {
      openSections.add(id);
    }
  }

  void set(void Function(SettingsWriter w) body) {
    final writer = SettingsWriter(draft.value!, _commit);
    body(writer);
  }

  void _commit(StoreSettings next) => draft.value = next;

  /// Tax example: what GST adds to a ₹100 line at the current rate. Display arithmetic only — the
  /// payable total in a real order always comes from `orders.createOrder`.
  String taxExample() {
    final settings = draft.value;
    if (settings == null) return '—';
    const linePaise = 10000; // ₹100
    final taxPaise = (linePaise * settings.taxRateBps / 10000).round();
    return '${OmMoney.format(linePaise)} + ${AdminFormat.bps(settings.taxRateBps)} GST '
        '= ${OmMoney.format(taxPaise)} tax → ${OmMoney.format(linePaise + taxPaise)}';
  }

  /// Rupee text for the store-wide free-shipping threshold. A null threshold is *unset*, which is
  /// not the same as zero, so it renders as blank rather than as "free above ₹0".
  String get freeShippingText {
    final paise = draft.value?.freeShippingAbovePaise;
    return paise == null ? '' : AdminFormat.rupeeText(paise);
  }

  Future<bool> save() async {
    final settings = draft.value;
    if (settings == null) return false;
    if (settings.taxRateBps < 0 || settings.taxRateBps > 10000) {
      announce('A tax rate must be between 0% and 100% (0-10000 basis points).', error: true);
      return false;
    }
    final ok = await mutateVoid(() => _admin.saveSettings(settings));
    if (!ok) {
      final error = failure.value;
      announce(error?.message ?? 'Settings could not be saved.', error: true);
      return false;
    }
    savedAt.value = DateTime.now().toString();
    announce(
      'Store settings saved. Your role was re-checked by the write and the change is in the audit '
      'log — this page is not the permission.',
    );
    await load();
    return true;
  }
}

/// Field-setter surface handed to `SettingsController.set`, so the view stays declarative.
final class SettingsWriter {
  SettingsWriter(this._base, this._commit);

  final StoreSettings _base;
  final void Function(StoreSettings) _commit;

  set shopName(String v) => _commit(_copy(shopName: v));
  set tagline(String v) => _commit(_copy(tagline: v));
  set description(String v) => _commit(_copy(description: v));
  set addressLine1(String v) => _commit(_copy(addressLine1: v));
  set addressLine2(String v) => _commit(_copy(addressLine2: v));
  set city(String v) => _commit(_copy(city: v));
  set state(String v) => _commit(_copy(state: v));
  set pincode(String v) => _commit(_copy(pincode: v));
  set phone(String v) => _commit(_copy(phone: v));
  set whatsapp(String v) => _commit(_copy(whatsapp: v));
  set email(String v) => _commit(_copy(email: v));
  set openingHours(String v) => _commit(_copy(openingHours: v));
  set googleMapsUrl(String v) => _commit(_copy(googleMapsUrl: v));
  set gstNumber(String v) => _commit(_copy(gstNumber: v));
  set invoicePrefix(String v) => _commit(_copy(invoicePrefix: v));
  set seoTitle(String v) => _commit(_copy(seoTitle: v));
  set seoDescription(String v) => _commit(_copy(seoDescription: v));
  set taxInclusive(bool v) => _commit(_copy(taxInclusive: v));
  set isPickupEnabled(bool v) => _commit(_copy(isPickupEnabled: v));
  set pickupNotes(String v) => _commit(_copy(pickupNotes: v));
  set cancellationPolicy(String v) => _commit(_copy(cancellationPolicy: v));
  set refundPolicy(String v) => _commit(_copy(refundPolicy: v));
  set shippingPolicy(String v) => _commit(_copy(shippingPolicy: v));
  set privacyPolicy(String v) => _commit(_copy(privacyPolicy: v));
  set termsPolicy(String v) => _commit(_copy(termsPolicy: v));
  set autoPublishReviews(bool v) => _commit(_copy(autoPublishReviews: v));
  set allowGuestCheckout(bool v) => _commit(_copy(allowGuestCheckout: v));

  void taxRateBps(int v) => _commit(_copy(taxRateBps: v));
  void minOrderPaise(int v) => _commit(_copy(minOrderValuePaise: v));
  void freeShippingPaise(int? v) => _commit(_copy(freeShippingAbovePaise: v));
  void reviewThreshold(int v) => _commit(_copy(reviewReportThreshold: v));
  void social(String key, String value) {
    final links = Map<String, String>.from(_base.socialLinks);
    if (value.trim().isEmpty) {
      links.remove(key);
    } else {
      links[key] = value.trim();
    }
    _commit(_copy(socialLinks: links));
  }

  void paymentEnabled(String code, bool enabled) {
    _commit(
      _copy(
        paymentMethods: _base.paymentMethods
            .map((m) => m.code == code
                ? PaymentMethodOption(
                    code: m.code,
                    label: m.label,
                    isEnabled: enabled,
                    description: m.description,
                    extraFeePaise: m.extraFeePaise,
                    minAmountPaise: m.minAmountPaise,
                    maxAmountPaise: m.maxAmountPaise,
                  )
                : m)
            .toList(growable: false),
      ),
    );
  }

  void zone(ShippingZone zone, {
    String? name,
    List<String>? prefixes,
    int? flatRatePaise,
    int? freeAbovePaise,
    int? etaDaysMin,
    int? etaDaysMax,
    bool? isActive,
  }) {
    final updated = ShippingZone(
      id: zone.id,
      name: name ?? zone.name,
      pincodePrefixes: prefixes ?? zone.pincodePrefixes,
      flatRatePaise: flatRatePaise ?? zone.flatRatePaise,
      freeAbovePaise: freeAbovePaise ?? zone.freeAbovePaise,
      etaDaysMin: etaDaysMin ?? zone.etaDaysMin,
      etaDaysMax: etaDaysMax ?? zone.etaDaysMax,
      isActive: isActive ?? zone.isActive,
    );
    _commit(_copy(shippingZones: [
      for (final z in _base.shippingZones)
        if (z.id == zone.id) updated else z,
    ]));
  }

  StoreSettings _copy({
    String? shopName,
    String? tagline,
    String? description,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? pincode,
    String? phone,
    String? whatsapp,
    String? email,
    String? openingHours,
    String? googleMapsUrl,
    String? gstNumber,
    String? invoicePrefix,
    Map<String, String>? socialLinks,
    String? seoTitle,
    String? seoDescription,
    bool? taxInclusive,
    int? taxRateBps,
    int? minOrderValuePaise,
    int? freeShippingAbovePaise,
    bool? isPickupEnabled,
    String? pickupNotes,
    List<ShippingZone>? shippingZones,
    List<PaymentMethodOption>? paymentMethods,
    String? cancellationPolicy,
    String? refundPolicy,
    String? shippingPolicy,
    String? privacyPolicy,
    String? termsPolicy,
    bool? autoPublishReviews,
    int? reviewReportThreshold,
    bool? allowGuestCheckout,
  }) {
    final base = _base;
    return StoreSettings(
      id: base.id,
      shopName: shopName ?? base.shopName,
      tagline: tagline ?? base.tagline,
      description: description ?? base.description,
      addressLine1: addressLine1 ?? base.addressLine1,
      addressLine2: addressLine2 ?? base.addressLine2,
      city: city ?? base.city,
      state: state ?? base.state,
      pincode: pincode ?? base.pincode,
      phone: phone ?? base.phone,
      whatsapp: whatsapp ?? base.whatsapp,
      email: email ?? base.email,
      openingHours: openingHours ?? base.openingHours,
      googleMapsUrl: googleMapsUrl ?? base.googleMapsUrl,
      gstNumber: gstNumber ?? base.gstNumber,
      invoicePrefix: invoicePrefix ?? base.invoicePrefix,
      socialLinks: socialLinks ?? base.socialLinks,
      seoTitle: seoTitle ?? base.seoTitle,
      seoDescription: seoDescription ?? base.seoDescription,
      taxInclusive: taxInclusive ?? base.taxInclusive,
      taxRateBps: taxRateBps ?? base.taxRateBps,
      minOrderValuePaise: minOrderValuePaise ?? base.minOrderValuePaise,
      freeShippingAbovePaise: freeShippingAbovePaise ?? base.freeShippingAbovePaise,
      isPickupEnabled: isPickupEnabled ?? base.isPickupEnabled,
      pickupNotes: pickupNotes ?? base.pickupNotes,
      shippingZones: shippingZones ?? base.shippingZones,
      paymentMethods: paymentMethods ?? base.paymentMethods,
      cancellationPolicy: cancellationPolicy ?? base.cancellationPolicy,
      refundPolicy: refundPolicy ?? base.refundPolicy,
      shippingPolicy: shippingPolicy ?? base.shippingPolicy,
      privacyPolicy: privacyPolicy ?? base.privacyPolicy,
      termsPolicy: termsPolicy ?? base.termsPolicy,
      faq: base.faq,
      banners: base.banners,
      featuredProductIds: base.featuredProductIds,
      autoPublishReviews: autoPublishReviews ?? base.autoPublishReviews,
      reviewReportThreshold: reviewReportThreshold ?? base.reviewReportThreshold,
      allowGuestCheckout: allowGuestCheckout ?? base.allowGuestCheckout,
      updatedAt: base.updatedAt,
    );
  }
}
