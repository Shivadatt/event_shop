import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/storefront/common/store_product_card.dart';
import 'package:om_events/features/storefront/product_details/product_details_controller.dart';

/// "You may also like" rail. Same card component as the catalogue grids so nothing new is invented
/// here; empty / loading are handled by the caller so this stays a pure list.
final class RelatedProductsRail extends StatelessWidget {
  const RelatedProductsRail({super.key, required this.controller});

  final ProductDetailsController controller;

  static double _cardWidth(BuildContext context) => context.isMobile ? 168 : 208;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.related.toList(growable: false);
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(
            eyebrow: 'Complete the look',
            title: 'You may also like',
          ),
          const SizedBox(height: OmSpacing.md),
          OmHorizontalScroller(
            height: 300,
            spacing: OmSpacing.md,
            children: <Widget>[
              for (Product product in items)
                SizedBox(
                  width: _cardWidth(context),
                  child: StoreProductCard(
                    product: product,
                    inWishlist: controller.wished(product.id),
                    onWishlistToggle: () => controller.toggleWishlist(product),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }
}
