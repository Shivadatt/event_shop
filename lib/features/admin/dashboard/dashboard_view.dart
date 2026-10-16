import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/dashboard/dashboard_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// Admin home: revenue, the forward order pipeline, low stock and the moderation queues.
final class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<DashboardController>();
    return AdminScaffold(
      title: 'Dashboard',
      child: Obx(() => OmAdminPanel<void>(
            isLoading: controller.isLoading.value,
            hasLoaded: controller.hasLoaded.value,
            failure: controller.failure.value,
            isEmpty: controller.headline == null,
            onRetry: controller.loadAll,
            empty: OmEmptyState(
              title: 'No store figures returned',
              message: 'The stats read completed but returned nothing. If the backend is not '
                  'configured that is expected; otherwise reload.',
              icon: Icons.insights_outlined,
              actionLabel: 'Reload',
              onAction: controller.loadAll,
            ),
            builder: (context) => _Body(controller: controller),
          )),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final stats = controller.headline;
    if (stats == null) return const SizedBox.shrink();
    return OmAdminPage(
      title: 'Store overview',
      eyebrow: 'Admin',
      subtitle: 'Every figure here is a server read. Nothing on this page writes, so an empty '
          'queue and a failed read are shown differently.',
      actions: <Widget>[
        OmButton(
          label: 'Reload',
          variant: OmButtonVariant.secondary,
          size: OmButtonSize.small,
          icon: Icons.refresh,
          loading: controller.isLoading.value,
          onPressed: controller.isLoading.value ? null : controller.loadAll,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _RevenueRow(controller: controller, stats: stats),
          OmAdminSection(
            title: 'Action queues',
            subtitle: 'A count of "Unknown" means that read failed, not that the queue is empty.',
            child: _QueueGrid(controller: controller),
          ),
          OmAdminSection(
            title: 'Orders by status',
            subtitle: 'Forward pipeline only: a shipped order cannot be moved back to "placed". '
                'The allowed transitions are the model\'s own nextSteps and the server enforces '
                'them again on write.',
            child: _StatusBreakdown(controller: controller),
          ),
          OmAdminSection(
            title: 'Low stock',
            subtitle: 'Balance is a mirror of the append-only movement ledger. It is never '
                'edited here — corrections go through Inventory, which writes a movement.',
            child: _LowStockList(controller: controller),
          ),
          OmAdminSection(
            title: 'Fulfilment queue',
            subtitle: 'Placed, confirmed, processing and packed orders.',
            child: _FulfilmentList(controller: controller),
          ),
          if (stats.bestSellers.isNotEmpty)
            OmAdminSection(
              title: 'Best sellers this period',
              child: _BestSellers(rows: stats.bestSellers),
            ),
        ],
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({required this.controller, required this.stats});

  final DashboardController controller;
  final DashboardStats stats;

  @override
  Widget build(BuildContext context) => OmAdminFormGrid(
        children: <Widget>[
          _KpiCard(
            label: 'Revenue today',
            moneyPaise: controller.revenueTodayPaise,
            caption: '${stats.ordersToday} orders placed today',
          ),
          _KpiCard(
            label: 'Revenue this month',
            moneyPaise: controller.revenueMonthPaise,
            caption: '${stats.newCustomers} new customers',
          ),
          _KpiCard(
            label: 'Orders to action',
            value: '${stats.pendingOrders}',
            caption: 'not yet confirmed by staff',
          ),
          _KpiCard(
            label: 'Unpaid',
            value: '${stats.pendingPayments}',
            caption: 'payment not settled',
            accent: stats.pendingPayments > 0 ? OmColors.warning : null,
          ),
          _KpiCard(
            label: 'Low stock',
            value: '${stats.lowStockCount}',
            caption: 'at or under threshold',
            accent: stats.lowStockCount > 0 ? OmColors.warning : null,
          ),
          _KpiCard(
            label: 'Out of stock',
            value: '${stats.outOfStockCount}',
            caption: 'zero balance',
            accent: stats.outOfStockCount > 0 ? OmColors.danger : null,
          ),
          _SparklineCard(points: stats.salesSparkline),
        ],
      );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.caption,
    this.moneyPaise,
    this.value,
    this.accent,
  });

  final String label;
  final String caption;
  final int? moneyPaise;
  final String? value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final money = moneyPaise;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          OmText(label.toUpperCase(), variant: OmTextVariant.label),
          const SizedBox(height: OmSpacing.sm),
          if (money != null)
            OmMoneyText(money, style: context.omText.priceLarge, decimals: false)
          else
            OmText(value ?? 'Not loaded', variant: OmTextVariant.priceLarge, color: accent),
          const SizedBox(height: OmSpacing.xs),
          OmText(caption, variant: OmTextVariant.caption),
        ],
      ),
    );
  }
}

/// Sales trend from `DashboardStats.salesSparkline`, drawn as bars.
///
/// A charting dependency is the wrong trade for a seven-day orientation shape: a bar row cannot
/// fail to lay out, and the exact figure is in the tooltip and on the Reports screen.
class _SparklineCard extends StatelessWidget {
  const _SparklineCard({required this.points});

  final List<SalesPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const OmCard(
        child: OmAdminMeta(
          label: 'SALES TREND',
          value: 'No sales points returned for this period',
        ),
      );
    }
    final maxRevenue = points.map((p) => p.revenuePaise).fold<int>(0, (a, b) => a > b ? a : b);
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          OmText('SALES TREND', variant: OmTextVariant.label),
          const SizedBox(height: OmSpacing.md),
          SizedBox(
            height: 76,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message: '${AdminFormat.date(point.day)} · '
                            '${OmMoney.format(point.revenuePaise)} · ${point.orders} orders',
                        child: Container(
                          height: maxRevenue == 0
                              ? 4
                              : (76 * (point.revenuePaise / maxRevenue)).clamp(4.0, 76.0),
                          decoration: const BoxDecoration(
                            color: OmColors.gold,
                            borderRadius: BorderRadius.all(Radius.circular(OmRadius.sm)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: OmSpacing.sm),
          OmText(
            '${AdminFormat.date(points.first.day)} – ${AdminFormat.date(points.last.day)}',
            variant: OmTextVariant.caption,
          ),
        ],
      ),
    );
  }
}

class _QueueGrid extends StatelessWidget {
  const _QueueGrid({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) => OmAdminFormGrid(
        children: <Widget>[
          for (final tile in controller.queueTiles)
            OmCard(
              onTap: () => Get.toNamed<dynamic>(tile.route),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OmText(tile.label, variant: OmTextVariant.bodyStrong),
                      ),
                      OmBadge(
                        label: tile.count == null ? 'Unknown' : '${tile.count}',
                        tone: (tile.count ?? 1) > 0 ? OmTone.warning : OmTone.success,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: OmSpacing.xs),
                  OmText(tile.caption, variant: OmTextVariant.caption),
                  const SizedBox(height: OmSpacing.sm),
                  OmText('Open ${tile.route}', variant: OmTextVariant.label),
                ],
              ),
            ),
        ],
      );
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) => OmCard(
        child: Wrap(
          spacing: OmSpacing.lg,
          runSpacing: OmSpacing.md,
          children: <Widget>[
            for (final entry in controller.statusCounts.entries)
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    orderBadge(entry.key),
                    const SizedBox(height: OmSpacing.xs),
                    OmText(
                      entry.value == null ? 'Unknown' : '${entry.value}',
                      variant: OmTextVariant.price,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _LowStockList extends StatelessWidget {
  const _LowStockList({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.lowStockSample;
    if (items.isEmpty) {
      return const OmEmptyState(
        title: 'Nothing below its low-stock threshold',
        message: 'Thresholds are set per product on the Inventory screen.',
        icon: Icons.check_circle_outline,
        compact: true,
      );
    }
    return OmAdminResponsiveList(
      itemCount: items.length,
      onTapRow: (index) => Get.toNamed<dynamic>(OmRoutes.forAdminProduct(items[index].id)),
      columns: <OmAdminColumn>[
        OmAdminColumn(
          heading: 'Product',
          cell: (context, index) => OmText(items[index].name, variant: OmTextVariant.bodyStrong),
        ),
        OmAdminColumn(
          heading: 'SKU',
          cell: (context, index) => OmText(
            AdminFormat.missing(items[index].sku, placeholder: 'no SKU'),
            variant: OmTextVariant.caption,
          ),
        ),
        OmAdminColumn(
          heading: 'Balance',
          numeric: true,
          cell: (context, index) =>
              OmText('${items[index].stockQty}', variant: OmTextVariant.price),
        ),
        OmAdminColumn(
          heading: 'Threshold',
          numeric: true,
          cell: (context, index) => OmText('${items[index].lowStockThreshold}'),
        ),
        OmAdminColumn(
          heading: 'State',
          cell: (context, index) => stockBadge(
            stockQty: items[index].stockQty,
            lowStockThreshold: items[index].lowStockThreshold,
          ),
        ),
      ],
      cardBuilder: (context, index) => OmAdminRowCard(
        title: items[index].name,
        lines: <String>[
          'Balance ${items[index].stockQty} · threshold ${items[index].lowStockThreshold}',
        ],
        badges: <Widget>[
          stockBadge(
            stockQty: items[index].stockQty,
            lowStockThreshold: items[index].lowStockThreshold,
          ),
        ],
      ),
    );
  }
}

class _FulfilmentList extends StatelessWidget {
  const _FulfilmentList({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.fulfilment;
    if (items.isEmpty) {
      return const OmEmptyState(
        title: 'Nothing in the fulfilment queue',
        message: 'Orders appear here from the moment they are placed.',
        icon: Icons.local_shipping_outlined,
        compact: true,
      );
    }
    return OmAdminResponsiveList(
      itemCount: items.length,
      onTapRow: (index) => Get.toNamed<dynamic>(OmRoutes.forAdminOrder(items[index].id)),
      columns: <OmAdminColumn>[
        OmAdminColumn(
          heading: 'Order',
          cell: (context, index) => OmText(
            AdminFormat.missing(items[index].orderNumber, placeholder: items[index].id),
            variant: OmTextVariant.bodyStrong,
          ),
        ),
        OmAdminColumn(
          heading: 'Status',
          cell: (context, index) => orderBadge(items[index].status),
        ),
        OmAdminColumn(
          heading: 'Payment',
          cell: (context, index) => paymentBadge(items[index].paymentStatus),
        ),
        OmAdminColumn(
          heading: 'Units',
          numeric: true,
          cell: (context, index) => OmText('${items[index].totalQty}'),
        ),
        OmAdminColumn(
          heading: 'Placed',
          cell: (context, index) => OmText(
            AdminFormat.dateTime(items[index].createdAt),
            variant: OmTextVariant.caption,
          ),
        ),
      ],
      cardBuilder: (context, index) => OmAdminRowCard(
        title: AdminFormat.missing(items[index].orderNumber, placeholder: items[index].id),
        lines: <String>[
          'Units ${items[index].totalQty} · placed ${AdminFormat.dateTime(items[index].createdAt)}',
        ],
        badges: <Widget>[
          orderBadge(items[index].status),
          paymentBadge(items[index].paymentStatus),
        ],
      ),
    );
  }
}

class _BestSellers extends StatelessWidget {
  const _BestSellers({required this.rows});

  final List<BestSellerRow> rows;

  @override
  Widget build(BuildContext context) => OmAdminResponsiveList(
        itemCount: rows.length,
        onTapRow: (index) => Get.toNamed<dynamic>(
          OmRoutes.forAdminProduct(rows[index].productId),
        ),
        columns: <OmAdminColumn>[
          OmAdminColumn(
            heading: 'Product',
            cell: (context, index) => OmText(rows[index].name, variant: OmTextVariant.bodyStrong),
          ),
          OmAdminColumn(
            heading: 'Units',
            numeric: true,
            cell: (context, index) => OmText('${rows[index].unitsSold}'),
          ),
          OmAdminColumn(
            heading: 'Revenue',
            numeric: true,
            cell: (context, index) => OmMoneyText(rows[index].revenuePaise, decimals: false),
          ),
        ],
        cardBuilder: (context, index) => OmAdminRowCard(
          title: rows[index].name,
          lines: <String>['${rows[index].unitsSold} units'],
          trailing: OmMoneyText(rows[index].revenuePaise, decimals: false),
        ),
      );
}
