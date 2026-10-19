import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/features/admin/audit/audit_controller.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Append-only audit trail.
///
/// There is no edit or delete affordance anywhere on this screen — the log's value is that it is
/// immutable, and the read path (`auditLogs`) is the only thing it offers.
final class AuditView extends StatelessWidget {
  const AuditView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuditController>();
    return AdminScaffold(
      title: 'Audit log',
      child: OmAdminPage(
        title: 'Audit log',
        eyebrow: 'Accountability',
        subtitle: 'Every price, stock, role, order-status, refund and settings write lands here. '
            'Entries are written by the server and cannot be changed from the admin UI.',
        actions: <Widget>[
          OmButton(
            label: 'Export page',
            variant: OmButtonVariant.secondary,
            size: OmButtonSize.small,
            icon: Icons.download_outlined,
            onPressed: controller.rows.isEmpty
                ? null
                : () => omShowAdminCsv(
                      context,
                      title: 'Audit log (this page)',
                      csv: controller.exportLoaded(),
                      totalRows: controller.rows.length,
                    ),
          ),
          OmButton(
            label: 'Reload',
            variant: OmButtonVariant.ghost,
            size: OmButtonSize.small,
            icon: Icons.refresh,
            onPressed: controller.refresh,
          ),
        ],
        child: Obx(() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmAdminFilterBar(
                  children: <Widget>[
                    OmDropdown<String>(
                      label: 'Entity',
                      value: controller.entityFilter.value ?? '',
                      items: const <String>['', ...AuditController.knownEntities],
                      itemLabel: (v) => v.isEmpty ? 'All entities' : v,
                      onChanged: controller.applyEntity,
                    ),
                    OmDropdown<String>(
                      label: 'Action',
                      value: controller.actionFilter.value ?? '',
                      items: const <String>['', ...AuditController.knownActions],
                      itemLabel: (v) => v.isEmpty ? 'All actions' : v,
                      onChanged: controller.applyAction,
                    ),
                    if (controller.hasFilters)
                      OmButton(
                        label: 'Clear filters',
                        variant: OmButtonVariant.ghost,
                        size: OmButtonSize.small,
                        onPressed: controller.clearFilters,
                      ),
                  ],
                ),
                const SizedBox(height: OmSpacing.sm),
                const OmAdminNotice(
                  message: 'Actor and date-range filters are not offered: the read path only '
                      'accepts entity and action. See the NEEDS OWNER note in AuditController.',
                ),
                const SizedBox(height: OmSpacing.lg),
                OmAdminPanel<AuditLog>(
                  isLoading: controller.isLoading.value,
                  hasLoaded: controller.hasLoaded.value,
                  failure: controller.failure.value,
                  isEmpty: controller.rows.isEmpty,
                  onRetry: controller.refresh,
                  empty: const OmEmptyState(
                    icon: Icons.history,
                    title: 'No matching audit entries',
                    message: 'Clear a filter or reload to see the newest writes.',
                  ),
                  builder: (context) => OmAdminResponsiveList(
                    itemCount: controller.rows.length,
                    columns: <OmAdminColumn>[
                      OmAdminColumn(heading: 'When', cell: (c, i) => Text(AdminFormat.dateTime(controller.rows[i].createdAt))),
                      OmAdminColumn(heading: 'Action', cell: (c, i) => Text(controller.rows[i].action)),
                      OmAdminColumn(heading: 'Entity', cell: (c, i) => Text('${controller.rows[i].entityType} · ${controller.rows[i].entityId}')),
                      OmAdminColumn(heading: 'Actor', cell: (c, i) {
                        final e = controller.rows[i];
                        return Text(e.actorRole.isEmpty ? AdminFormat.missing(e.actorUid) : '${e.actorRole} · ${e.actorUid}');
                      }),
                      OmAdminColumn(heading: 'Summary', cell: (c, i) => Text(AdminFormat.missing(controller.rows[i].summary))),
                    ],
                    cardBuilder: (c, i) => _AuditCard(entry: controller.rows[i]),
                    footer: OmAdminPager(
                      loadedCount: controller.rows.length,
                      hasMore: controller.hasMore,
                      isLoading: controller.isLoading.value,
                      onLoadMore: controller.loadMore,
                    ),
                  ),
                ),
              ],
            )),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entry});

  final AuditLog entry;

  @override
  Widget build(BuildContext context) => OmAdminRowCard(
        title: entry.action,
        badges: <Widget>[
          OmBadge(label: entry.entityType, tone: OmTone.info, dense: true),
          if (entry.actorRole.isNotEmpty)
            OmBadge(label: entry.actorRole, dense: true),
        ],
        lines: <String>[
          AdminFormat.dateTime(entry.createdAt),
          'Entity ${AdminFormat.missing(entry.entityId)}',
          if (entry.summary.isNotEmpty) entry.summary,
          if (entry.actorUid.isNotEmpty) 'Actor ${entry.actorUid}',
          if (entry.before.isNotEmpty || entry.after.isNotEmpty) _changeSummary(),
        ],
      );

  String _changeSummary() {
    final keys = <String>{...entry.before.keys, ...entry.after.keys}.take(6).join(', ');
    return 'Changed fields: ${keys.isEmpty ? '—' : keys}';
  }
}
