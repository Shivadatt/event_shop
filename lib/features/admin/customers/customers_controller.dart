import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';

/// Customer list, filtered server-side by search text and role.
final class CustomersController extends AdminController with PagedAdminList<UserProfile> {
  CustomersController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final RxString search = ''.obs;
  final Rxn<UserRole> roleFilter = Rxn<UserRole>();

  @override
  void onInit() {
    super.onInit();
    loadFirstPage();
  }

  bool get hasFilters => search.value.isNotEmpty || roleFilter.value != null;

  @override
  Future<PagedResult<UserProfile>> fetch({String? cursor}) => _admin.listCustomers(
        search: search.value.isEmpty ? null : search.value,
        role: roleFilter.value,
        pageSize: pageSize,
        cursor: cursor,
      );

  void applySearch(String value) {
    search.value = value.trim();
    loadFirstPage();
  }

  void applyRole(UserRole? value) {
    roleFilter.value = value;
    loadFirstPage();
  }

  void clearFilters() {
    search.value = '';
    roleFilter.value = null;
    loadFirstPage();
  }

  void openDetail(String uid) => Get.toNamed<dynamic>(OmRoutes.forAdminCustomer(uid));

  String exportLoaded() => OmCsv.build(
        headers: const <String>[
          'uid',
          'name',
          'email',
          'phone',
          'role',
          'wholesaleStatus',
          'company',
          'gst',
          'blocked',
          'joinedAt',
          'lastOrderAt',
        ],
        rows: <List<Object?>>[
          for (final profile in rows)
            <Object?>[
              profile.uid,
              profile.displayName,
              profile.email,
              profile.phone,
              profile.role.code,
              profile.wholesaleStatus.code,
              profile.companyName,
              profile.gstNumber,
              profile.isBlocked ? 'yes' : 'no',
              AdminFormat.date(profile.createdAt),
              AdminFormat.date(profile.lastOrderAt),
            ],
        ],
      );
}

/// One customer: profile, GST/company, wholesale state, their orders and the two privileged
/// writes (role change, block/unblock).
///
/// Lifetime value is **never** summed in the browser. It is asked for as an aggregate, and the
/// order table below shows only the page of orders the server returned, labelled as such.
final class CustomerDetailController extends AdminController {
  CustomerDetailController({required this.uid});

  final String uid;

  final AdminRepository _admin = Get.find<AdminRepository>();

  final Rxn<UserProfile> profile = Rxn<UserProfile>();
  final RxList<Order> orders = <Order>[].obs;

  /// How many orders the account has, from the page's own server total.
  ///
  /// Deliberately *not* the length of the loaded page: a customer with 25 lifetime orders and a
  /// 10-row first page would otherwise be reported to staff as having 10. Stays null when the page
  /// carries no total, and [ordersCountText] then says so out loud instead of guessing.
  final RxnInt orderCountEstimate = RxnInt();
  final Rxn<ReportRow> value = Rxn<ReportRow>();

  /// Rows of `orders` loaded so far — a page, not the whole history, so the UI must not call it a
  /// lifetime figure.
  int get loadedOrderCount => orders.length;
  bool get canManageRoles => session.canEditPricing;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() => guard<bool>(() async {
        profile.value = await _admin.customerDetail(uid);
        orders.assignAll(await _ordersPage());
        await _loadValue();
        return true;
      });

  Future<List<Order>> _ordersPage() async {
    // AGREED with the backend owner (r2 convergence list): `String? customerId` on `listOrders` —
    // see the orders controller. A queue that cannot be scoped server-side must not be approximated
    // here by paging the whole order collection, so this read passes the uid through and lets the
    // function do the filtering.
    final page = await _admin.listOrders(customerId: uid);
    // The page's own total is the only figure allowed to stand in for "how many orders this account
    // has". `page.items.length` is the size of *this* page, so a 25-order account shown as a 10-row
    // page used to be displayed as having 10 orders.
    //
    // `listOrders` now fills `totalEstimate` with a Firestore count aggregate for a customer-scoped
    // query (firestore_admin_repository.dart), which is the only shape this panel asks for. The
    // lifetime money figures still come from the `customerValue` server aggregate.
    orderCountEstimate.value = page.totalEstimate;
    return page.items;
  }

  /// One line of plain English for the orders card. It never presents a page as a lifetime total.
  String get ordersCountText {
    final total = orderCountEstimate.value;
    if (total != null) {
      return '$total order(s) on record for this account, of which $loadedOrderCount row(s) are '
          'loaded here. The lifetime figures above come from the server aggregate, not from these '
          'rows.';
    }
    return '$loadedOrderCount order row(s) loaded for this account, and the server reported no '
        'lifetime total on this page — so this is a page, not a count of orders. The figures above '
        'come from the server aggregate.';
  }

  Future<void> _loadValue() async {
    // AGREED with the backend owner (r2 convergence list): `Future<ReportRow> customerValue(String
    // uid)` — server-summed order count (`units`), paid paise (`revenuePaise`) and refunded paise
    // (`discountPaise`), computed from the orders collection. A client-side sum would disagree with
    // the revenue report the moment a refund lands, so this figure always comes from the function.
    value.value = await _admin.customerValue(uid);
  }

  String get valueSummary {
    final row = value.value;
    if (row == null) return 'Awaiting the server aggregate.';
    return '${row.units} order(s) · paid ${OmMoney.format(row.revenuePaise)} · '
        'refunded ${OmMoney.format(row.discountPaise)}';
  }

  /// Blocking is a privileged write with a mandatory reason; the reason is what makes the audit row
  /// reviewable, so it is required here and re-required by the function.
  Future<bool> setBlocked({required bool blocked, required String reason}) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return false;
    final ok = await mutateVoid(
      () => _admin.setCustomerBlocked(uid: uid, blocked: blocked, reason: trimmed),
    );
    if (ok) {
      await load();
      announce(
        blocked
            ? 'Account blocked. The reason is in the audit log and the sign-out happens on the '
                'next read because the token is checked server-side.'
            : 'Block lifted. The customer can sign in again; nothing about their order history '
                'changed.',
      );
      return true;
    }
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
    return false;
  }

  Future<bool> changeRole(UserRole role, String reason) async {
    if (reason.trim().isEmpty) return false;
    final ok = await mutateVoid(
      () => _admin.setCustomerRole(uid: uid, role: role, reason: reason.trim()),
    );
    if (ok) {
      await load();
      announce(
        'Role set to ${role.code}. Only staff, admin and owner can perform this write, and the '
        'function re-checked that before committing it.',
      );
      return true;
    }
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
    return false;
  }

  String csvForLoadedOrders() => OmCsv.build(
        headers: const <String>['orderNumber', 'placedAt', 'status', 'paymentStatus', 'totalPaise'],
        rows: <List<Object?>>[
          for (final order in orders)
            <Object?>[
              order.orderNumber,
              AdminFormat.dateTime(order.createdAt),
              order.status.code,
              order.paymentStatus.code,
              order.totals.grandTotalPaise,
            ],
        ],
      );
}
