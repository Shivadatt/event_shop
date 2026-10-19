import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/products/products_controller.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// Products table: server-paged, status-filtered, searchable.
///
/// The row is a link to the editor, but the archive and duplicate actions stop propagation and ask
/// for confirmation, because both are writes that land in the audit log.
final class ProductsView extends StatefulWidget {
  const ProductsView({super.key});

  @override
  State<ProductsView> createState() => _ProductsViewState();
}

class _ProductsViewState extends State<ProductsView> {
  /// Held by the screen, not the controller: it is a text buffer, not state another widget needs.
  late final TextEditingController _search = TextEditingController(text: controller.search.value);

  ProductsController get controller => Get.find<ProductsController>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
        child: Obx(() => OmAdminPanel<Product>(
            isLoading: controller.isLoading.value,
            hasLoaded: controller.hasLoaded.value,
            failure: controller.failure.value,
            isEmpty: controller.rows.isEmpty,
            onRetry: controller.loadFirstPage,
            empty: OmEmptyState(
              icon: Icons.inventory_2_outlined,
              title: controller.hasFilters ? 'No products match' : 'No products yet',
              message: controller.hasFilters
                  ? 'Nothing matched "${controller.search.value}" with the current filters. '
                      'Clear them to see the whole catalogue.'
                  : 'The catalogue is empty. Create the first product to start selling.',
              actionLabel: controller.hasFilters ? 'Clear filters' : 'New product',
              onAction: controller.hasFilters ? controller.clearFilters : controller.openNew,
            ),
            builder: (context) => OmAdminPage(
              title: 'Products',
              eyebrow: 'Catalogue',
              subtitle: '${controller.rows.length} products on this page',
              actions: <Widget>[
                OmButton(
                  label: 'New product',
                  icon: Icons.add,
                  onPressed: controller.openNew,
                ),
                OmButton(
                  label: 'Reload',
                  variant: OmButtonVariant.ghost,
                  icon: Icons.refresh,
                  onPressed: controller.loadFirstPage,
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Filters(controller: controller, search: _search),
                  const SizedBox(height: OmSpacing.lg),
                  OmAdminResponsiveList(
                    itemCount: controller.rows.length,
                    onTapRow: (index) => controller.openEditor(controller.rows[index].id),
                    columns: <OmAdminColumn>[
                      OmAdminColumn(
                        heading: 'Product',
                        cell: (context, index) => _NameCell(product: controller.rows[index]),
                      ),
                      OmAdminColumn(
                        heading: 'Category',
                        cell: (context, index) => OmText(
                          controller.categoryLabel(controller.rows[index].categoryId),
                          variant: OmTextVariant.caption,
                        ),
                      ),
                      OmAdminColumn(
                        heading: 'Price',
                        numeric: true,
                        cell: (context, index) => _PriceCell(product: controller.rows[index]),
                      ),
                      OmAdminColumn(
                        heading: 'Stock',
                        numeric: true,
                        cell: (context, index) {
                          final product = controller.rows[index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              OmText('${product.stockQty}', variant: OmTextVariant.bodyStrong),
                              const SizedBox(height: OmSpacing.xs),
                              stockBadge(
                                stockQty: product.stockQty,
                                lowStockThreshold: product.lowStockThreshold,
                              ),
                            ],
                          );
                        },
                      ),
                      OmAdminColumn(
                        heading: 'Status',
                        cell: (context, index) => productBadge(controller.rows[index].status),
                      ),
                      OmAdminColumn(
                        heading: 'Actions',
                        cell: (context, index) => _RowActions(
                          controller: controller,
                          product: controller.rows[index],
                        ),
                      ),
                    ],
                    cardBuilder: (context, index) {
                      final product = controller.rows[index];
                      return OmAdminRowCard(
                        title: product.name.isEmpty ? '(untitled)' : product.name,
                        badges: <Widget>[
                          productBadge(product.status),
                          stockBadge(
                            stockQty: product.stockQty,
                            lowStockThreshold: product.lowStockThreshold,
                          ),
                        ],
                        lines: <String>[
                          product.sku.isEmpty ? 'No SKU' : 'SKU ${product.sku}',
                          '${OmMoney.format(product.basePricePaise)} each · '
                              '${controller.categoryLabel(product.categoryId)}',
                          'Min ${product.minOrderQty}, multiples of ${product.orderMultiple}',
                        ],
                        onTap: () => controller.openEditor(product.id),
                        actions: <Widget>[
                          OmButton(
                            label: 'Edit',
                            size: OmButtonSize.small,
                            onPressed: () => controller.openEditor(product.id),
                          ),
                          _ArchiveButton(controller: controller, product: product),
                        ],
                      );
                    },
                    footer: OmAdminPager(
                      loadedCount: controller.rows.length,
                      hasMore: controller.hasMore,
                      isLoading: controller.isLoading.value,
                      onLoadMore: controller.loadMore,
                      onRefresh: controller.refresh,
                    ),
                  ),
                ],
              ),
            ),
          )),
  );
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller, required this.search});

  final ProductsController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) => Obx(() {
        final categories = controller.categories;
        return OmAdminFilterBar(
          searchController: search,
          searchHint: 'Search name, SKU or tag',
          onSearch: controller.applySearch,
          children: <Widget>[
            Wrap(
              spacing: OmSpacing.xs,
              runSpacing: OmSpacing.xs,
              children: <Widget>[
                OmFilterChip(
                  label: 'Any status',
                  selected: controller.statusFilter.value == null,
                  onTap: () => controller.applyStatus(null),
                ),
                for (final status in ProductStatus.values)
                  OmFilterChip(
                    label: switch (status) {
                      ProductStatus.active => 'Active',
                      ProductStatus.draft => 'Draft',
                      ProductStatus.archived => 'Archived',
                    },
                    selected: controller.statusFilter.value == status,
                    onTap: () => controller.applyStatus(status),
                  ),
              ],
            ),
            if (categories.isEmpty && !controller.categoriesFailed.value)
              const SizedBox(width: 200, child: OmSkeleton(height: 44))
            else if (controller.categoriesFailed.value)
              const OmText(
                'Category list unavailable — the product table is unaffected.',
                variant: OmTextVariant.caption,
              )
            else
              SizedBox(
                width: 240,
                child: OmDropdown<String>(
                  label: 'Category',
                  value: controller.categoryIdFilter.value,
                  hint: 'All categories',
                  items: categories.map((c) => c.id).toList(growable: false),
                  itemLabel: controller.categoryLabel,
                  onChanged: controller.applyCategory,
                ),
              ),
            if (controller.hasFilters)
              OmButton(
                label: 'Clear',
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                onPressed: () {
                  search.clear();
                  controller.clearFilters();
                },
              ),
          ],
        );
      });
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          SizedBox(
            height: 38,
            width: 38,
            child: ClipRRect(borderRadius: OmRadius.smAll, child: OmMediaImage(ref: product.primaryImage)),
          ),
          const SizedBox(width: OmSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OmText(
                  product.name.isEmpty ? '(untitled)' : product.name,
                  variant: OmTextVariant.bodyStrong,
                  maxLines: 2,
                ),
                OmText(
                  product.sku.isEmpty ? product.slug : product.sku,
                  variant: OmTextVariant.caption,
                ),
              ],
            ),
          ),
        ],
      );
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(OmMoney.format(product.basePricePaise), style: styles.price),
        if (product.isSaleLive)
          Text(
            'was ${OmMoney.format(product.retailPricePaise)}',
            style: styles.caption.copyWith(
              decoration: TextDecoration.lineThrough,
              decorationColor: OmColors.textMuted,
            ),
          ),
        if (product.slabs.length > 1)
          Text('${product.slabs.length} bands', style: styles.caption),
      ],
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.controller, required this.product});

  final ProductsController controller;
  final Product product;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          OmIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit ${product.name}',
            size: 34,
            onPressed: () => controller.openEditor(product.id),
          ),
          OmIconButton(
            icon: Icons.copy_all_outlined,
            tooltip: 'Duplicate ${product.name}',
            size: 34,
            onPressed: () => controller.duplicate(product.id),
          ),
          _ArchiveButton(controller: controller, product: product, asIcon: true),
        ],
      );
}

/// Archive is a status write, not a delete: the document and its orders stay.
class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({
    required this.controller,
    required this.product,
    this.asIcon = false,
  });

  final ProductsController controller;
  final Product product;
  final bool asIcon;

  Future<void> _run(BuildContext context, {required bool archived}) async {
    final ok = await omConfirmAdminAction(
      context: context,
      title: archived ? 'Archive ${product.name}?' : 'Restore ${product.name}?',
      message: archived
          ? 'The product stops appearing in the shop but keeps its document, its images and every '
              'order line that references it. Past orders are unaffected.'
          : 'The product returns to whatever status it had. Check its price bands and stock before '
              'customers see it again.',
      confirmLabel: archived ? 'Archive' : 'Restore',
      destructive: archived,
    );
    if (ok) await controller.setArchived(product.id, archived: archived);
  }

  @override
  Widget build(BuildContext context) {
    final archived = product.status == ProductStatus.archived;
    if (asIcon) {
      return OmIconButton(
        icon: archived ? Icons.unarchive_outlined : Icons.archive_outlined,
        tooltip: archived ? 'Restore ${product.name}' : 'Archive ${product.name}',
        size: 34,
        onPressed: () => _run(context, archived: !archived),
      );
    }
    return OmButton(
      label: archived ? 'Restore' : 'Archive',
      size: OmButtonSize.small,
      variant: archived ? OmButtonVariant.secondary : OmButtonVariant.ghost,
      onPressed: () => _run(context, archived: !archived),
    );
  }
}
