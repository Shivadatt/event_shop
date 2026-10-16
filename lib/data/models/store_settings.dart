import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/om_doc.dart';

/// A serviceable delivery band. Pincode prefixes rather than full pincodes keep the document
/// small and let rules stay readable.
final class ShippingZone {
  const ShippingZone({
    required this.id,
    required this.name,
    required this.pincodePrefixes,
    required this.flatRatePaise,
    this.freeAbovePaise,
    this.etaDaysMin = 2,
    this.etaDaysMax = 5,
    this.isActive = true,
  });

  final String id;
  final String name;
  final List<String> pincodePrefixes;
  final int flatRatePaise;
  final int? freeAbovePaise;
  final int etaDaysMin;
  final int etaDaysMax;
  final bool isActive;

  bool covers(String pincode) =>
      isActive && pincodePrefixes.any((prefix) => pincode.startsWith(prefix));

  int rateFor(int orderValuePaise) {
    final free = freeAbovePaise;
    if (free != null && orderValuePaise >= free) return 0;
    return flatRatePaise;
  }

  String get etaLabel => etaDaysMin == etaDaysMax ? '$etaDaysMin days' : '$etaDaysMin-$etaDaysMax days';

  factory ShippingZone.fromMap(Map<String, dynamic> m) => ShippingZone(
        id: readStringOrEmpty(m, 'id'),
        name: readStringOrEmpty(m, 'name'),
        pincodePrefixes: readStringList(m, 'pincodePrefixes'),
        flatRatePaise: readIntOrZero(m, 'flatRatePaise'),
        freeAbovePaise: readInt(m, 'freeAbovePaise'),
        etaDaysMin: readInt(m, 'etaDaysMin') ?? 2,
        etaDaysMax: readInt(m, 'etaDaysMax') ?? 5,
        isActive: readBool(m, 'isActive', fallback: true),
      );

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'id': id,
        'name': name,
        'pincodePrefixes': pincodePrefixes,
        'flatRatePaise': flatRatePaise,
        'freeAbovePaise': freeAbovePaise,
        'etaDaysMin': etaDaysMin,
        'etaDaysMax': etaDaysMax,
        'isActive': isActive,
      });
}

/// Singleton document `store_settings/{store}`. One authoritative copy: storefront and admin
/// both read it, only privileged staff write it.
final class StoreSettings {
  const StoreSettings({
    this.id = 'store',
    this.shopName = 'OM Events And Decorators',
    this.tagline = 'Wholesale & Party Supplies',
    this.description = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.phone = '',
    this.whatsapp = '',
    this.email = '',
    this.openingHours = '',
    this.googleMapsUrl = '',
    this.gstNumber = '',
    this.invoicePrefix = 'OME',
    this.socialLinks = const <String, String>{},
    this.seoTitle = '',
    this.seoDescription = '',
    this.taxInclusive = false,
    this.taxRateBps = 0,
    this.minOrderValuePaise = 0,
    this.freeShippingAbovePaise,
    this.isPickupEnabled = true,
    this.pickupNotes = '',
    this.shippingZones = const <ShippingZone>[],
    this.paymentMethods = const <PaymentMethodOption>[],
    this.cancellationPolicy = '',
    this.refundPolicy = '',
    this.shippingPolicy = '',
    this.privacyPolicy = '',
    this.termsPolicy = '',
    this.faq = const <FaqEntry>[],
    this.banners = const <MediaRef>[],
    this.featuredProductIds = const <String>[],
    this.autoPublishReviews = false,
    this.reviewReportThreshold = 3,
    this.allowGuestCheckout = true,
    this.updatedAt,
  });

  final String id;
  final String shopName;
  final String tagline;
  final String description;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String pincode;
  final String phone;
  final String whatsapp;
  final String email;
  final String openingHours;
  final String googleMapsUrl;
  final String gstNumber;
  final String invoicePrefix;

  /// key -> url, e.g. `instagram`, `facebook`, `youtube`. Empty values hide the icon.
  final Map<String, String> socialLinks;
  final String seoTitle;
  final String seoDescription;

  /// Price display mode. GST-exclusive adds `taxRateBps` on top of the line totals.
  final bool taxInclusive;

  /// Basis points (18% = 1800). Percent-as-double never touches a rupee figure.
  final int taxRateBps;
  final int minOrderValuePaise;
  final int? freeShippingAbovePaise;
  final bool isPickupEnabled;
  final String pickupNotes;
  final List<ShippingZone> shippingZones;
  final List<PaymentMethodOption> paymentMethods;
  final String cancellationPolicy;
  final String refundPolicy;
  final String shippingPolicy;
  final String privacyPolicy;
  final String termsPolicy;
  final List<FaqEntry> faq;
  final List<MediaRef> banners;
  final List<String> featuredProductIds;
  final bool autoPublishReviews;
  final int reviewReportThreshold;
  final bool allowGuestCheckout;
  final DateTime? updatedAt;

  static const StoreSettings fallback = StoreSettings();

  String get fullAddress => <String>[
        addressLine1,
        addressLine2,
        '$city, $state $pincode',
      ].where((s) => s.trim().isNotEmpty).join(', ');

  bool hasServiceablePincode(String pincode) =>
      shippingZones.any((zone) => zone.covers(pincode));

  ShippingZone? zoneFor(String pincode) {
    for (final zone in shippingZones) {
      if (zone.covers(pincode)) return zone;
    }
    return null;
  }

  PaymentMethodOption? paymentMethod(String code) {
    for (final method in paymentMethods) {
      if (method.code == code) return method;
    }
    return null;
  }

  /// Click-to-chat deep link built from the stored number, digits only.
  String get whatsappLink {
    final digits = whatsapp.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? '' : 'https://wa.me/$digits';
  }

  factory StoreSettings.fromMap(Map<String, dynamic> m) => StoreSettings(
        id: readStringOrEmpty(m, 'id').isEmpty ? 'store' : readStringOrEmpty(m, 'id'),
        shopName: readStringOrEmpty(m, 'shopName'),
        tagline: readStringOrEmpty(m, 'tagline'),
        description: readStringOrEmpty(m, 'description'),
        addressLine1: readStringOrEmpty(m, 'addressLine1'),
        addressLine2: readStringOrEmpty(m, 'addressLine2'),
        city: readStringOrEmpty(m, 'city'),
        state: readStringOrEmpty(m, 'state'),
        pincode: readStringOrEmpty(m, 'pincode'),
        phone: readStringOrEmpty(m, 'phone'),
        whatsapp: readStringOrEmpty(m, 'whatsapp'),
        email: readStringOrEmpty(m, 'email'),
        openingHours: readStringOrEmpty(m, 'openingHours'),
        googleMapsUrl: readStringOrEmpty(m, 'googleMapsUrl'),
        gstNumber: readStringOrEmpty(m, 'gstNumber'),
        invoicePrefix: readStringOrEmpty(m, 'invoicePrefix'),
        socialLinks: Map<String, String>.fromEntries(
          readMap(m, 'socialLinks').entries.map((e) => MapEntry(e.key, '${e.value}')),
        ),
        seoTitle: readStringOrEmpty(m, 'seoTitle'),
        seoDescription: readStringOrEmpty(m, 'seoDescription'),
        taxInclusive: readBool(m, 'taxInclusive'),
        taxRateBps: readIntOrZero(m, 'taxRateBps'),
        minOrderValuePaise: readIntOrZero(m, 'minOrderValuePaise'),
        freeShippingAbovePaise: readInt(m, 'freeShippingAbovePaise'),
        isPickupEnabled: readBool(m, 'isPickupEnabled', fallback: true),
        pickupNotes: readStringOrEmpty(m, 'pickupNotes'),
        shippingZones:
            readMapList(m, 'shippingZones').map(ShippingZone.fromMap).toList(growable: false),
        paymentMethods: readMapList(m, 'paymentMethods')
            .map(PaymentMethodOption.fromMap)
            .toList(growable: false),
        cancellationPolicy: readStringOrEmpty(m, 'cancellationPolicy'),
        refundPolicy: readStringOrEmpty(m, 'refundPolicy'),
        shippingPolicy: readStringOrEmpty(m, 'shippingPolicy'),
        privacyPolicy: readStringOrEmpty(m, 'privacyPolicy'),
        termsPolicy: readStringOrEmpty(m, 'termsPolicy'),
        faq: readMapList(m, 'faq').map(FaqEntry.fromMap).toList(growable: false),
        banners: readMapList(m, 'banners').map(MediaRef.fromMap).toList(growable: false),
        featuredProductIds: readStringList(m, 'featuredProductIds'),
        autoPublishReviews: readBool(m, 'autoPublishReviews'),
        reviewReportThreshold: readInt(m, 'reviewReportThreshold') ?? 3,
        allowGuestCheckout: readBool(m, 'allowGuestCheckout', fallback: true),
        updatedAt: readDate(m, 'updatedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'shopName': shopName,
        'tagline': tagline,
        'description': description,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'phone': phone,
        'whatsapp': whatsapp,
        'email': email,
        'openingHours': openingHours,
        'googleMapsUrl': googleMapsUrl,
        'gstNumber': gstNumber,
        'invoicePrefix': invoicePrefix,
        'socialLinks': socialLinks,
        'seoTitle': seoTitle,
        'seoDescription': seoDescription,
        'taxInclusive': taxInclusive,
        'taxRateBps': taxRateBps,
        'minOrderValuePaise': minOrderValuePaise,
        'freeShippingAbovePaise': freeShippingAbovePaise,
        'isPickupEnabled': isPickupEnabled,
        'pickupNotes': pickupNotes,
        'shippingZones': shippingZones.map((z) => z.toMap()).toList(),
        'paymentMethods': paymentMethods.map((p) => p.toMap()).toList(),
        'cancellationPolicy': cancellationPolicy,
        'refundPolicy': refundPolicy,
        'shippingPolicy': shippingPolicy,
        'privacyPolicy': privacyPolicy,
        'termsPolicy': termsPolicy,
        'faq': faq.map((f) => f.toMap()).toList(),
        'banners': banners.map((b) => b.toMap()).toList(),
        'featuredProductIds': featuredProductIds,
        'autoPublishReviews': autoPublishReviews,
        'reviewReportThreshold': reviewReportThreshold,
        'allowGuestCheckout': allowGuestCheckout,
      });
}

final class FaqEntry {
  const FaqEntry({required this.question, required this.answer, this.order = 0});

  final String question;
  final String answer;
  final int order;

  factory FaqEntry.fromMap(Map<String, dynamic> m) => FaqEntry(
        question: readStringOrEmpty(m, 'question'),
        answer: readStringOrEmpty(m, 'answer'),
        order: readIntOrZero(m, 'order'),
      );

  Map<String, Object?> toMap() =>
      <String, Object?>{'question': question, 'answer': answer, 'order': order};
}
