import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/reports/reports_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Sales, valuation and movement reports.
///
/// Every figure is paise; margin is only rendered for staff who may see cost, because a zero-cost
/// row means "unknown", not "100% margin".
final class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ReportsController>();
    return AdminScaffold(
      title: 'Reports',
      child: OmAdminPage(
        title: 'Business reports',
        eyebrow: 'Insight',
        subtitle: 'Numbers come from the same Cloud Function the CSV export uses, so the screen and '
            'the file can never disagree.',
        actions: <Widget>[
          OmButton(
            label: 'Export CSV',
            variant: OmButtonVariant.secondary,
            size: OmButtonSize.small,
            icon: Icons.download_outlined,
            loading: controller.isSubmitting.value,
            onPressed: () => _export(context, controller),
          ),
          OmButton(
            label: 'Reload',
            variant: OmButtonVariant.ghost,
            size: OmButtonSize.small,
            icon: Icons.refresh,
            onPressed: controller.load,
          ),
        ],
        child: Obx(() {
          final kind = controller.selected.value;
          final isDay = controller.isDayReport;
          final rowCount = isDay ? controller.daily.length : controller.rows.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: OmSpacing.xs,
                runSpacing: OmSpacing.xs,
                children: <Widget>[
                  for (final option in OmReportKind.values)
                    OmFilterChip(
                      label: option.label,
                      selected: kind == option,
                      onTap: () => controller.select(option),
                    ),
                ],
              ),
              if (controller.needsRange) ...<Widget>[
                const SizedBox(height: OmSpacing.md),
                OmAdminFilterBar(
                  children: <Widget>[
                    OmAdminDateField(
                      label: 'From',
                      value: controller.from.value,
                      onChanged: (v) => controller.setRange(start: v),
                    ),
                    OmAdminDateField(
                      label: 'To',
                      value: controller.to.value,
                      onChanged: (v) => controller.setRange(end: v),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: OmSpacing.lg),
              if (!controller.canSeeCost && kind.showsCost)
                const Padding(
                  padding: EdgeInsets.only(bottom: OmSpacing.md),
                  child: OmAdminNotice(
                    tone: OmTone.warning,
                    icon: Icons.lock_outline,
                    title: 'Margin hidden',
                    message: 'Cost and margin columns need the cost-price role. Revenue is still shown.',
                  ),
                ),
              OmAdminPanel<ReportRow>(
                isLoading: controller.isLoading.value,
                hasLoaded: controller.hasLoaded.value,
                failure: controller.failure.value,
                isEmpty: rowCount == 0,
                onRetry: controller.load,
                empty: OmEmptyState(
                  icon: Icons.bar_chart_outlined,
                  title: 'No ${kind.label.toLowerCase()} data',
                  message: 'Widen the date range or pick another report.',
                ),
                builder: (context) => _table(controller, kind, isDay, rowCount),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _table(ReportsController controller, OmReportKind kind, bool isDay, int rowCount) {
    final canCost = controller.canSeeCost && kind.showsCost;
    Widget money(int paise) => Text(OmMoney.format(paise));
    if (isDay) {
      return OmAdminResponsiveList(
        itemCount: rowCount,
        columns: <OmAdminColumn>[
          OmAdminColumn(heading: 'Day', cell: (c, i) => Text(AdminFormat.date(controller.daily[i].day))),
          OmAdminColumn(heading: 'Orders', numeric: true, cell: (c, i) => Text('${controller.daily[i].orders}')),
          OmAdminColumn(heading: 'Revenue', numeric: true, cell: (c, i) => money(controller.daily[i].revenuePaise)),
        ],
        cardBuilder: (c, i) {
          final p = controller.daily[i];
          return OmAdminRowCard(
            title: AdminFormat.date(p.day),
            lines: <String>['${p.orders} orders · ${OmMoney.format(p.revenuePaise)}'],
          );
        },
      );
    }
    final columns = <OmAdminColumn>[
      OmAdminColumn(heading: 'Item', cell: (c, i) => Text(controller.rows[i].label)),
      OmAdminColumn(heading: 'Units', numeric: true, cell: (c, i) => Text('${controller.rows[i].units}')),
      OmAdminColumn(heading: 'Revenue', numeric: true, cell: (c, i) => money(controller.rows[i].revenuePaise)),
      OmAdminColumn(heading: 'Discount', numeric: true, cell: (c, i) => money(controller.rows[i].discountPaise)),
    ];
    if (canCost) {
      columns.add(OmAdminColumn(
        heading: 'Cost',
        numeric: true,
        cell: (c, i) => Text(controller.rows[i].hasCostData ? OmMoney.format(controller.rows[i].costPaise) : '—'),
      ));
      columns.add(OmAdminColumn(
        heading: 'Margin',
        numeric: true,
        cell: (c, i) => Text(controller.rows[i].hasCostData ? OmMoney.format(controller.rows[i].grossMarginPaise) : 'unknown'),
      ));
    }
    return OmAdminResponsiveList(
      itemCount: rowCount,
      columns: columns,
      cardBuilder: (c, i) {
        final r = controller.rows[i];
        final lines = <String>[
          '${r.units} units · ${OmMoney.format(r.revenuePaise)}',
          if (r.discountPaise > 0) 'Discount ${OmMoney.format(r.discountPaise)}',
          if (canCost) 'Cost ${r.hasCostData ? OmMoney.format(r.costPaise) : '—'} · Margin ${r.hasCostData ? OmMoney.format(r.grossMarginPaise) : 'unknown'}',
        ];
        return OmAdminRowCard(title: r.label, lines: lines);
      },
    );
  }

  Future<void> _export(BuildContext context, ReportsController controller) async {
    final csv = await controller.exportCsv();
    if (csv == null || csv.isEmpty) {
      // A null here means the guarded repository call failed; the panel already shows the failure
      // and a retry, so the view does not fabricate a second message.
      return;
    }
    final total = controller.isDayReport ? controller.daily.length : controller.rows.length;
    // The CSV read is a network round trip: on web the operator can navigate away during it, so the
    // dialog must not be opened against a defunct context.
    if (!context.mounted) return;
    await omShowAdminCsv(
      context,
      title: '${controller.selected.value.label} export',
      csv: csv,
      totalRows: total,
    );
  }
}
