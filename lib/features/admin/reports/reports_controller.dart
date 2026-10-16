import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';

/// The reports the admin repository can actually serve. `salesByDay` is derived from the dashboard
/// sparkline because no day-grain Cloud Function report exists yet.
enum OmReportKind {
  salesByDay('Sales by day', null, false),
  salesByProduct('Sales by product', 'sales_by_product', true),
  salesByCategory('Sales by category', 'sales_by_category', true),
  retailVsWholesale('Retail vs wholesale', 'retail_vs_wholesale', true),
  inventoryValuation('Stock valuation', 'inventory_valuation', false),
  slowMoving('Slow movers', 'slow_moving', false),
  couponPerformance('Coupon performance', 'coupon_performance', false),
  cancelledOrRefunded('Cancelled / refunded', 'cancelled_or_refunded', true);

  const OmReportKind(this.label, this.reportId, this.usesDateRange);

  final String label;

  /// Server report id used by `exportCsv`; null when the screen builds the CSV itself.
  final String? reportId;
  final bool usesDateRange;

  /// Margin columns come from cost price, so they are only meaningful for staff who may see cost.
  bool get showsCost => this != OmReportKind.couponPerformance && this != OmReportKind.cancelledOrRefunded;
}

final class ReportsController extends AdminController {
  ReportsController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final Rx<OmReportKind> selected = OmReportKind.salesByProduct.obs;
  final RxList<ReportRow> rows = <ReportRow>[].obs;
  final RxList<SalesPoint> daily = <SalesPoint>[].obs;

  late final Rxn<DateTime> from = Rxn<DateTime>(_startOfWindow());
  late final Rxn<DateTime> to = Rxn<DateTime>(DateTime.now());

  bool get canSeeCost => session.canSeeCostPrice;
  bool get isDayReport => selected.value == OmReportKind.salesByDay;
  bool get needsRange => selected.value.usesDateRange;

  static DateTime _startOfWindow() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
  }

  DateTime get fromValue => from.value ?? _startOfWindow();
  DateTime get toValue => to.value ?? DateTime.now();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void select(OmReportKind kind) {
    if (selected.value == kind) return;
    selected.value = kind;
    load();
  }

  void setRange({DateTime? start, DateTime? end}) {
    if (start != null) from.value = start;
    if (end != null) to.value = end;
    if (needsRange) load();
  }

  Future<void> load() async {
    final kind = selected.value;
    if (kind == OmReportKind.salesByDay) {
      final stats = await guard<DashboardStats>(_admin.dashboard);
      daily.assignAll(stats?.salesSparkline ?? const <SalesPoint>[]);
      rows.clear();
      return;
    }
    final result = await guard<List<ReportRow>>(() => switch (kind) {
          OmReportKind.salesByProduct => _admin.salesByProduct(from: fromValue, to: toValue),
          OmReportKind.salesByCategory => _admin.salesByCategory(from: fromValue, to: toValue),
          OmReportKind.retailVsWholesale => _admin.retailVsWholesale(from: fromValue, to: toValue),
          OmReportKind.inventoryValuation => _admin.inventoryValuation(),
          OmReportKind.slowMoving => _admin.slowMoving(),
          OmReportKind.couponPerformance => _admin.couponPerformance(),
          OmReportKind.cancelledOrRefunded => _admin.cancelledOrRefunded(from: fromValue, to: toValue),
          OmReportKind.salesByDay => _admin.salesByProduct(from: fromValue, to: toValue),
        });
    rows.assignAll(result ?? const <ReportRow>[]);
    daily.clear();
  }

  double get revenueTotalPaise {
    if (isDayReport) {
      return daily.fold<double>(0, (sum, p) => sum + p.revenuePaise);
    }
    return rows.fold<int>(0, (sum, r) => sum + r.revenuePaise).toDouble();
  }

  /// CSV text for the current view. Server reports export the exact rows the function produced;
  /// the day report is assembled here because there is no server day-report id.
  Future<String?> exportCsv() async {
    final kind = selected.value;
    if (kind == OmReportKind.salesByDay) {
      return OmCsv.build(
        headers: const <String>['Day', 'Orders', 'Revenue paise', 'Revenue'],
        rows: <List<Object?>>[
          for (final point in daily)
            <Object?>[
              AdminFormat.date(point.day),
              point.orders,
              point.revenuePaise,
              OmMoney.format(point.revenuePaise),
            ],
        ],
      );
    }
    final reportId = kind.reportId;
    if (reportId == null) return null;
    return guard<String>(
      () => _admin.exportCsv(
        reportId: reportId,
        from: kind.usesDateRange ? fromValue : null,
        to: kind.usesDateRange ? toValue : null,
      ),
      asSubmitting: true,
    );
  }

  String revenueLabel(int paise) => OmMoney.format(paise);
}
