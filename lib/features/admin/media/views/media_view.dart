import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/media/om_media_orphan_panel.dart';
import 'package:om_events/app/core/widgets/media/om_media_storage_notice.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/media/media_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Media library: what each asset belongs to, which images are missing alt text, and the orphan
/// cleanup report.
///
/// The orphan panel scans without deleting and requires an explicit confirmation over the exact
/// list it produced — a scan is a report, never a mutation. When Supabase is not configured the
/// screen explains the deployment condition instead of failing.
final class MediaView extends StatelessWidget {
  const MediaView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MediaController>();
    return AdminScaffold(
      title: 'Media',
      child: Obx(() {
        final usage = controller.usageRows;
        return OmAdminPage(
          title: 'Media library',
          eyebrow: 'Assets',
          subtitle: 'Assets live in Supabase Storage; the catalogue only holds references. This view '
              'is built from the live product pages, so it reflects exactly what documents point at.',
          actions: <Widget>[
            OmButton(
              label: 'Export list',
              variant: OmButtonVariant.secondary,
              size: OmButtonSize.small,
              icon: Icons.download_outlined,
              onPressed: usage.isEmpty
                  ? null
                  : () => omShowAdminCsv(
                        context,
                        title: 'Media usage (loaded pages)',
                        csv: controller.exportLoaded(),
                        totalRows: usage.length,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!controller.isConfigured)
                const Padding(
                  padding: EdgeInsets.only(bottom: OmSpacing.lg),
                  child: OmMediaStorageNotice(),
                ),
              OmAdminMetaRow(
                entries: <OmAdminMeta>[
                  OmAdminMeta(label: 'Assets on loaded pages', value: '${controller.totalImages}'),
                  OmAdminMeta(label: 'Missing alt text', value: '${controller.missingAltCount}', emphasise: true),
                  OmAdminMeta(label: 'Products paged', value: '${controller.rows.length}'),
                  OmAdminMeta(label: 'Storage', value: controller.isConfigured ? 'Configured' : 'Not configured'),
                ],
              ),
              const SizedBox(height: OmSpacing.lg),
              OmAdminSection(
                title: 'Entity usage & alt coverage',
                subtitle: 'Alt text is required for accessibility and image SEO. Filter to the defects, '
                    'then open the product to fix them.',
                action: controller.altOnly.value ? 'Show all' : 'Only missing alt',
                onActionTap: controller.toggleAltOnly,
                child: OmAdminPanel<MediaUsageRow>(
                  isLoading: controller.isLoading.value,
                  hasLoaded: controller.hasLoaded.value,
                  failure: controller.failure.value,
                  isEmpty: usage.isEmpty,
                  onRetry: controller.refresh,
                  empty: OmEmptyState(
                    icon: Icons.image_not_supported_outlined,
                    title: controller.altOnly.value
                        ? 'No images missing alt text on these pages'
                        : 'No product images yet',
                    message: 'Load more products or turn the alt-only filter off.',
                  ),
                  builder: (context) => OmAdminResponsiveList(
                    itemCount: usage.length,
                    columns: <OmAdminColumn>[
                      OmAdminColumn(
                        heading: 'Used by',
                        cell: (c, i) => Text('${usage[i].entityName}'),
                      ),
                      OmAdminColumn(heading: 'Kind', cell: (c, i) => Text(usage[i].ref.kind.code)),
                      OmAdminColumn(
                        heading: 'Path',
                        cell: (c, i) => Text(AdminFormat.missing(usage[i].ref.storagePath, placeholder: '(url only)')),
                      ),
                      OmAdminColumn(
                        heading: 'Alt',
                        cell: (c, i) => usage[i].missingAlt
                            ? const OmBadge(label: 'Missing alt', tone: OmTone.warning, dense: true)
                            : Text(usage[i].ref.altText),
                      ),
                    ],
                    cardBuilder: (c, i) => OmAdminRowCard(
                      title: usage[i].entityName,
                      badges: <Widget>[
                        OmBadge(label: usage[i].ref.kind.code, tone: OmTone.info, dense: true),
                        if (usage[i].missingAlt)
                          const OmBadge(label: 'Missing alt', tone: OmTone.warning, dense: true),
                      ],
                      lines: <String>[
                        'Entity ${usage[i].entityKind} · ${usage[i].entityId}',
                        AdminFormat.missing(usage[i].ref.storagePath, placeholder: '(stored by url only)'),
                        if (!usage[i].missingAlt) 'Alt: ${usage[i].ref.altText}',
                      ],
                      actions: <Widget>[
                        OmButton(
                          label: 'Open product',
                          size: OmButtonSize.small,
                          variant: OmButtonVariant.ghost,
                          onPressed: () => _openProduct(usage[i].entityId),
                        ),
                      ],
                    ),
                    footer: controller.altOnly.value || usage.isEmpty
                        ? null
                        : OmAdminPager(
                            loadedCount: controller.rows.length,
                            hasMore: controller.hasMore,
                            isLoading: controller.isLoading.value,
                            onLoadMore: controller.loadMore,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: OmSpacing.lg),
              OmAdminSection(
                title: 'Orphan cleanup',
                subtitle: 'Scans the bucket against the reference set and lists unreferenced objects. '
                    'Deleting needs an explicit confirmation and re-checks each path first.',
                child: const OmMediaOrphanPanel(),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _openProduct(String productId) =>
      Get.toNamed<dynamic>(OmRoutes.forAdminProduct(productId), arguments: productId);
}
