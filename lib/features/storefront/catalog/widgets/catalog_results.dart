import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/features/storefront/catalog/catalog_controller.dart';
import 'package:om_events/features/storefront/common/store_product_card.dart';

/// Shared results grid used by both the category page and the search page: same loading,
/// error, empty, count and pagination behaviour everywhere a `CatalogQuery` is executed.
class CatalogResults extends StatelessWidget {
  const CatalogResults({super.key, required this.controller});

  final CatalogController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.items.toList(growable: false);
      final loading = controller.loadingFirst.value;
      final failure = controller.failure.value;

      if (loading && items.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CatalogControls(controller: controller),
            const SizedBox(height: OmSpacing.md),
            OmProductGrid(
              itemCount: context.omColumnCount * 2,
              itemBuilder: (_, _) => const OmProductCardSkeleton(),
            ),
          ],
        );
      }

      if (items.isEmpty) {
        if (failure != null) {
          return Column(
            children: <Widget>[
              CatalogControls(controller: controller),
              const SizedBox(height: OmSpacing.md),
              OmErrorState(failure: failure, onRetry: controller.refresh),
            ],
          );
        }
        return _ZeroResults(controller: controller);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CatalogControls(controller: controller),
          const SizedBox(height: OmSpacing.sm),
          _ResultCount(controller: controller, loaded: items.length),
          const SizedBox(height: OmSpacing.md),
          OmProductGrid(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final product = items[index];
              return StoreProductCard(
                product: product,
                inWishlist: controller.wished(product.id),
                onWishlistToggle: () => controller.toggleWishlist(product),
              );
            },
          ),
          if (controller.hasMore) ...<Widget>[
            const SizedBox(height: OmSpacing.lg),
            Center(
              child: _LoadMoreButton(controller: controller),
            ),
          ],
        ],
      );
    });
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.controller});

  final CatalogController controller;

  @override
  Widget build(BuildContext context) => OmButton(
        label: 'Load more products',
        variant: OmButtonVariant.outline,
        loading: controller.loadingMore.value,
        busyLabel: 'Loading…',
        onPressed: controller.loadMore,
      );
}

class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.controller, required this.loaded});

  final CatalogController controller;
  final int loaded;

  @override
  Widget build(BuildContext context) {
    final total = controller.totalEstimate.value;
    final label = total == null
        ? '$loaded products shown'
        : 'Showing $loaded of about $total products';
    return OmText(label, variant: OmTextVariant.caption);
  }
}

/// Sort + chip row shared by every catalog surface.
class CatalogControls extends StatelessWidget {
  const CatalogControls({super.key, this.controller});

  final CatalogController? controller;

  @override
  Widget build(BuildContext context) {
    final catalog = controller ?? Get.find<CatalogController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: OmText(
                catalog.query.hasFilters ? 'Filtered results' : 'All results',
                variant: OmTextVariant.muted,
              ),
            ),
            SizedBox(
              height: 44,
              child: _SortMenu(catalog: catalog),
            ),
          ],
        ),
        const SizedBox(height: OmSpacing.sm),
        _FilterChips(controller: catalog),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.controller});

  final CatalogController controller;

  static const List<(String, int?, int?)> _bands = <(String, int?, int?)>[
    ('Under ₹250', null, 250),
    ('₹250 – ₹999', 250, 999),
    ('₹1,000+', 1000, null),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tags = controller.facetTags;
      final query = controller.query;
      final chips = <Widget>[
        OmFilterChip(
          label: 'In stock',
          selected: query.inStockOnly,
          onTap: () => controller.setInStockOnly(!query.inStockOnly),
        ),
        for (final band in _bands)
          OmFilterChip(
            label: band.$1,
            selected: query.minPricePaise == (band.$2 == null ? null : band.$2! * 100) &&
                query.maxPricePaise == (band.$3 == null ? null : band.$3! * 100),
            onTap: () => controller.setPriceBand(minRupees: band.$2, maxRupees: band.$3),
          ),
        for (final tag in tags)
          OmFilterChip(
            label: tag,
            selected: controller.activeTags.contains(tag),
            onTap: () => controller.toggleTag(tag),
          ),
        if (query.hasFilters)
          OmFilterChip(
            label: 'Clear all',
            selected: false,
            onTap: controller.clearFilters,
          ),
      ];
      return SizedBox(
        height: 44,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final chip in chips)
                Padding(
                  padding: const EdgeInsets.only(right: OmSpacing.sm),
                  child: chip,
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.catalog});

  final CatalogController catalog;

  @override
  Widget build(BuildContext context) => PopupMenuButton<SortMode>(
        tooltip: 'Sort results',
        initialValue: catalog.query.sort,
        onSelected: catalog.setSort,
        itemBuilder: (context) => <PopupMenuEntry<SortMode>>[
          for (final mode in SortMode.values)
            PopupMenuItem<SortMode>(
              value: mode,
              child: OmText(mode.label),
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.swap_vert, size: 18),
            const SizedBox(width: OmSpacing.xs),
            OmText('Sort: ${catalog.query.sort.label}', variant: OmTextVariant.bodyStrong),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      );
}

/// Zero-result state: the shared empty copy plus real, tappable category suggestions.
class _ZeroResults extends StatelessWidget {
  const _ZeroResults({required this.controller});

  final CatalogController controller;

  @override
  Widget build(BuildContext context) {
    final List<Category> suggestions = controller.suggestionCategories();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CatalogControls(controller: controller),
        const SizedBox(height: OmSpacing.md),
        OmEmptyState.noProducts(onReset: controller.clearFilters),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: OmSpacing.lg),
            child: Column(
              children: <Widget>[
                const OmText('Or browse a category:', variant: OmTextVariant.bodyStrong),
                const SizedBox(height: OmSpacing.sm),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    for (final category in suggestions)
                      OmFilterChip(
                        label: category.name,
                        selected: false,
                        onTap: () => Get.toNamed<void>(
                          OmRoutes.forCategory(category.pathSlug),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
