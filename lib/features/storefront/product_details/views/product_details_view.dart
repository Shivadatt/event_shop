import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/product_details/product_details_controller.dart';
import 'package:om_events/features/storefront/product_details/widgets/product_buy_box.dart';
import 'package:om_events/features/storefront/product_details/widgets/product_gallery.dart';
import 'package:om_events/features/storefront/product_details/widgets/product_reviews_section.dart';
import 'package:om_events/features/storefront/product_details/widgets/related_products_rail.dart';

/// Product detail page: gallery + buy box (side-by-side wide, stacked compact), full description,
/// slab table, reviews and a related-products rail. Loading, error and unknown-slug states are all
/// handled here; the controller never touches Firestore/Supabase directly.
final class ProductDetailsView extends GetView<ProductDetailsController> {
  const ProductDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Product',
      body: Obx(() {
        if (controller.loading.value && controller.product.value == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: OmSpacing.xl),
            child: OmLoading(message: 'Loading product…'),
          );
        }
        final failure = controller.failure.value;
        final product = controller.product.value;
        if (product == null) {
          return OmErrorState(
            failure: failure ?? const NotFoundFailure(),
            onRetry: controller.retry,
          );
        }
        final settings = Get.find<SettingsStore>();
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: OmSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Breadcrumb(controller: controller),
                const SizedBox(height: OmSpacing.md),
                if (context.isCompactLayout)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ProductGallery(
                        images: product.images,
                        productName: product.name,
                      ),
                      const SizedBox(height: OmSpacing.lg),
                      ProductBuyBox(controller: controller),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: ProductGallery(
                          images: product.images,
                          productName: product.name,
                        ),
                      ),
                      const SizedBox(width: OmSpacing.xl),
                      Expanded(
                        flex: 6,
                        child: ProductBuyBox(controller: controller),
                      ),
                    ],
                  ),
                const SizedBox(height: OmSpacing.xl),
                _Description(product: product),
                if (product.slabs.length >= 2) ...<Widget>[
                  const SizedBox(height: OmSpacing.lg),
                  OmSlabTable(
                    slabs: controller.displaySlabs,
                    basePricePaise: product.basePricePaise,
                    currentQty: controller.quantity.value,
                  ),
                ],
                const OmDivider(space: OmSpacing.xl),
                Obx(
                  () => ProductReviewsSection(
                    reviews: controller.reviews.toList(growable: false),
                    breakdown: controller.breakdown.value,
                    autoPublish: settings.value.autoPublishReviews,
                    canWrite: true,
                    onWriteReview: controller.writeReview,
                  ),
                ),
                const OmDivider(space: OmSpacing.xl),
                RelatedProductsRail(controller: controller),
                const SizedBox(height: OmSpacing.xl),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Category → product trail; hidden until the controller has resolved the category.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.controller});

  final ProductDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final category = controller.category.value;
      if (category == null) return const SizedBox.shrink();
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: OmSpacing.xs,
        children: <Widget>[
          InkWell(
            onTap: () => controller.openCategory(category),
            child: OmText(category.name, variant: OmTextVariant.caption),
          ),
          Icon(Icons.chevron_right, size: 14, color: context.omText.muted.color),
          OmText(
            controller.product.value?.name ?? '',
            variant: OmTextVariant.caption,
            maxLines: 1,
          ),
        ],
      );
    });
  }
}

class _Description extends StatelessWidget {
  const _Description({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OmText('About this product', variant: OmTextVariant.h3),
        const SizedBox(height: OmSpacing.sm),
        if (product.description.isEmpty)
          OmText(
            'The store has not written a description for this product yet.',
            variant: OmTextVariant.muted,
          )
        else
          OmText(
            product.description,
            variant: OmTextVariant.body,
            maxLines: 40,
            overflow: TextOverflow.visible,
            selectable: true,
          ),
        if (product.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: OmSpacing.md),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              for (final tag in product.tags)
                OmBadge(label: tag, tone: OmTone.neutral, dense: true),
            ],
          ),
        ],
      ],
    );
  }
}
