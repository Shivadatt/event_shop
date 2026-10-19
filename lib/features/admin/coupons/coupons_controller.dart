import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';

/// Coupon list.
///
/// `listCoupons` is a full read (the collection is bounded, so no cursor), and `usedCount` shown
/// per row is the server counter incremented inside the order transaction — the screen never
/// recomputes it.
final class CouponsController extends AdminController {
  CouponsController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final RxList<Coupon> coupons = <Coupon>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final rows = await guard<List<Coupon>>(_admin.listCoupons);
    if (rows != null) coupons.assignAll(rows);
  }

  void openEditor([Coupon? coupon]) =>
      Get.find<CouponEditController>().start(coupon);

  Future<void> delete(Coupon coupon) async {
    final ok = await mutateVoid(() => _admin.deleteCoupon(coupon.id));
    if (!ok) {
      announce(failure.value?.message ?? 'Could not delete the coupon.', error: true);
      return;
    }
    announce('${coupon.code} deleted. The write re-checked your role server-side.');
    await load();
  }
}

/// Create / edit form for one coupon.
///
/// Money is entered as rupees and parsed to integer paise on save; a percentage is stored as an
/// integer percent (never a double). The repository `saveCoupon` still re-validates the value.
final class CouponEditController extends AdminController {
  CouponEditController();

  final AdminRepository _admin = Get.find<AdminRepository>();
  final CouponsController _list = Get.find<CouponsController>();

  final Rxn<Coupon> original = Rxn<Coupon>();
  final Rx<Coupon> draft = const Coupon(id: '', code: '', kind: CouponKind.percentage).obs;

  bool get isNew => original.value == null;
  bool get isOpen => original.value != null || draft.value.code.isNotEmpty;

  /// Local immutable copy builder.
  ///
  /// `Coupon` has no `copyWith` and lives in `lib/data/**`, which this screen may not edit, so the
  /// editor keeps one place that rebuilds a draft from the current one plus the single field the
  /// form is changing.
  Coupon _copy(Coupon base, {
    String? code,
    CouponKind? kind,
    int? percentOff,
    int? valuePaise,
    int? maxDiscountPaise,
    int? minCartValuePaise,
    int? perUserLimit,
    int? usageLimit,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isActive,
    bool? excludesWholesale,
    String? description,
  }) =>
      Coupon(
        id: base.id,
        code: code ?? base.code,
        kind: kind ?? base.kind,
        valuePaise: valuePaise ?? base.valuePaise,
        percentOff: percentOff ?? base.percentOff,
        maxDiscountPaise: maxDiscountPaise ?? base.maxDiscountPaise,
        minCartValuePaise: minCartValuePaise ?? base.minCartValuePaise,
        minQty: base.minQty,
        usageLimit: usageLimit ?? base.usageLimit,
        perUserLimit: perUserLimit ?? base.perUserLimit,
        usedCount: base.usedCount,
        startsAt: startsAt ?? base.startsAt,
        endsAt: endsAt ?? base.endsAt,
        isActive: isActive ?? base.isActive,
        appliesToCategoryIds: base.appliesToCategoryIds,
        appliesToProductIds: base.appliesToProductIds,
        excludesWholesale: excludesWholesale ?? base.excludesWholesale,
        description: description ?? base.description,
        createdAt: base.createdAt,
        updatedAt: base.updatedAt,
      );

  void start([Coupon? coupon]) {
    original.value = coupon;
    draft.value = coupon ??
        const Coupon(
          id: '',
          code: '',
          kind: CouponKind.percentage,
          percentOff: 10,
        );
  }

  void close() {
    original.value = null;
    draft.value = const Coupon(id: '', code: '', kind: CouponKind.percentage);
  }

  void setCode(String value) => _update(_copy(draft.value, code: Coupon.normaliseCode(value)));
  void setKind(CouponKind value) => _update(_copy(draft.value, kind: value));
  void setDescription(String value) => _update(_copy(draft.value, description: value));
  void setActive(bool value) => _update(_copy(draft.value, isActive: value));
  void setExcludesWholesale(bool value) => _update(_copy(draft.value, excludesWholesale: value));

  void setPercent(String text) =>
      _update(_copy(draft.value, percentOff: int.tryParse(text.trim()) ?? 0));
  void setValueRupees(String text) =>
      _update(_copy(draft.value, valuePaise: OmMoney.parseRupeeString(text)));
  void setMaxDiscountRupees(String text) {
    final trimmed = text.trim();
    _update(_copy(
      draft.value,
      maxDiscountPaise: trimmed.isEmpty ? null : OmMoney.parseRupeeString(trimmed),
    ));
  }

  void setMinOrderRupees(String text) =>
      _update(_copy(draft.value, minCartValuePaise: OmMoney.parseRupeeString(text)));
  void setPerUserLimit(String text) =>
      _update(_copy(draft.value, perUserLimit: int.tryParse(text.trim()) ?? 0));
  void setUsageLimit(String text) {
    final trimmed = text.trim();
    _update(_copy(draft.value, usageLimit: trimmed.isEmpty ? null : int.tryParse(trimmed)));
  }

  void setStartsAt(DateTime? value) => _update(_copy(draft.value, startsAt: value));
  void setEndsAt(DateTime? value) => _update(_copy(draft.value, endsAt: value));

  void _update(Coupon next) {
    draft.value = next;
  }

  List<String> blockingIssues() {
    final coupon = draft.value;
    final found = <String>[];
    if (coupon.code.isEmpty) found.add('A coupon needs a code.');
    switch (coupon.kind) {
      case CouponKind.percentage:
        if (coupon.percentOff <= 0 || coupon.percentOff > 99) {
          found.add('A percentage must be between 1 and 99.');
        }
      case CouponKind.flatPaise:
        if (coupon.valuePaise <= 0) found.add('A flat amount must be above zero.');
      case CouponKind.freeShipping:
        break;
    }
    if (coupon.perUserLimit <= 0) found.add('The per-customer cap must be at least 1.');
    return found;
  }

  Future<bool> save() async {
    final issues = blockingIssues();
    if (issues.isNotEmpty) {
      announce(issues.first, error: true);
      return false;
    }
    final coupon = draft.value;
    // Reuse the existing id on an edit; a brand-new coupon gets an empty id, which the repository
    // (or its Cloud Function) treats as "create".
    final saved = await mutate<Coupon>(
      () => _admin.saveCoupon(coupon),
    );
    if (saved == null) {
      announce(failure.value?.message ?? 'The coupon could not be saved.', error: true);
      return false;
    }
    announce(
      '${saved.code} saved. The server re-checked your role and re-validated the value — this '
      'form is not the permission.',
    );
    close();
    await _list.load();
    return true;
  }
}
