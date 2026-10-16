import 'package:om_events/data/om_doc.dart';

enum CouponKind {
  percentage('percentage'),
  flatPaise('flat'),
  freeShipping('freeShipping');

  const CouponKind(this.code);
  final String code;
}

CouponKind couponKindFromCode(String code) => CouponKind.values
    .firstWhere((k) => k.code == code, orElse: () => CouponKind.percentage);

final class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.kind,
    this.valuePaise = 0,
    this.percentOff = 0,
    this.maxDiscountPaise,
    this.minCartValuePaise = 0,
    this.minQty = 1,
    this.usageLimit,
    this.perUserLimit = 1,
    this.usedCount = 0,
    this.startsAt,
    this.endsAt,
    this.isActive = true,
    this.appliesToCategoryIds = const <String>[],
    this.appliesToProductIds = const <String>[],
    this.excludesWholesale = false,
    this.description = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Uppercase, no spaces; rules force `code == id.toUpperCase()` so lookups stay O(1).
  final String code;
  final CouponKind kind;
  final int valuePaise;

  /// 1..99 — validated server-side, never trusted from the client.
  final int percentOff;
  final int? maxDiscountPaise;
  final int minCartValuePaise;
  final int minQty;
  final int? usageLimit;
  final int perUserLimit;

  /// Incremented inside the order transaction, so concurrent checkouts cannot both spend the
  /// last use.
  final int usedCount;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final List<String> appliesToCategoryIds;
  final List<String> appliesToProductIds;
  final bool excludesWholesale;
  final String description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String normaliseCode(String input) =>
      input.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_-]'), '');

  bool get isExhausted => usageLimit != null && usedCount >= usageLimit!;

  bool isWithinWindow([DateTime? now]) {
    final at = now ?? DateTime.now();
    final start = startsAt;
    final end = endsAt;
    if (start != null && at.isBefore(start)) return false;
    if (end != null && at.isAfter(end)) return false;
    return true;
  }

  bool get isRedeemable => isActive && !isExhausted && isWithinWindow();

  /// Pure discount arithmetic, shared by the client preview and the server so the two can
  /// disagree visibly rather than silently.
  int discountFor(int eligibleSubtotalPaise) {
    if (!isRedeemable || eligibleSubtotalPaise < minCartValuePaise) return 0;
    final raw = switch (kind) {
      CouponKind.percentage => (eligibleSubtotalPaise * percentOff / 100).round(),
      CouponKind.flatPaise => valuePaise.clamp(0, eligibleSubtotalPaise),
      CouponKind.freeShipping => 0,
    };
    final cap = maxDiscountPaise;
    return cap == null ? raw : raw.clamp(0, cap);
  }

  factory Coupon.fromMap(Map<String, dynamic> m, {String? id}) => Coupon(
        id: id ?? readStringOrEmpty(m, 'id'),
        code: readStringOrEmpty(m, 'code'),
        kind: couponKindFromCode(readStringOrEmpty(m, 'kind')),
        valuePaise: readIntOrZero(m, 'valuePaise'),
        percentOff: readIntOrZero(m, 'percentOff'),
        maxDiscountPaise: readInt(m, 'maxDiscountPaise'),
        minCartValuePaise: readIntOrZero(m, 'minCartValuePaise'),
        minQty: readInt(m, 'minQty') ?? 1,
        usageLimit: readInt(m, 'usageLimit'),
        perUserLimit: readInt(m, 'perUserLimit') ?? 1,
        usedCount: readIntOrZero(m, 'usedCount'),
        startsAt: readDate(m, 'startsAt'),
        endsAt: readDate(m, 'endsAt'),
        isActive: readBool(m, 'isActive', fallback: true),
        appliesToCategoryIds: readStringList(m, 'appliesToCategoryIds'),
        appliesToProductIds: readStringList(m, 'appliesToProductIds'),
        excludesWholesale: readBool(m, 'excludesWholesale'),
        description: readStringOrEmpty(m, 'description'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'code': code,
        'kind': kind.code,
        'valuePaise': valuePaise,
        'percentOff': percentOff,
        'maxDiscountPaise': maxDiscountPaise,
        'minCartValuePaise': minCartValuePaise,
        'minQty': minQty,
        'usageLimit': usageLimit,
        'perUserLimit': perUserLimit,
        'startsAt': startsAt,
        'endsAt': endsAt,
        'isActive': isActive,
        'appliesToCategoryIds': appliesToCategoryIds,
        'appliesToProductIds': appliesToProductIds,
        'excludesWholesale': excludesWholesale,
        'description': description,
      });
}
