import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/storefront/common/line_price.dart';

/// The merchandising card used by home rails, catalogue grids, wishlist and related products.
/// Prices are always the engine's answer for this product's minimum order quantity, so two
/// screens can never quote different "from" prices.
final class StoreProductCard extends StatelessWidget {
  const StoreProductCard({
    super.key,
    required this.product,
    this.inWishlist = false,
    this.onWishlistToggle,
    this.width,
  });

  final Product product;
  final bool inWishlist;
  final VoidCallback? onWishlistToggle;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final line = priceLine(product: product, qty: product.minOrderQty);
    final priceText = line.hasError
        ? 'Price on request'
        : OmMoney.formatRupees(line.resolution.unitPricePaise);

    return SizedBox(
      width: width,
      child: OmCard(
        padding: EdgeInsets.zero,
        onTap: () => Get.toNamed<dynamic>(OmRoutes.forProduct(product.pathSlug)),
        child: Semantics(
          link: true,
          label: '${product.name}, $priceText',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    OmMediaImage(ref: product.primaryImage),
                    if (onWishlistToggle != null)
                      Positioned(
                        top: OmSpacing.sm,
                        right: OmSpacing.sm,
                        child: OmIconButton(
                          icon: inWishlist ? Icons.favorite : Icons.favorite_border,
                          tooltip: inWishlist
                              ? 'Remove ${product.name} from wishlist'
                              : 'Save ${product.name} to wishlist',
                          selected: inWishlist,
                          size: 40,
                          onPressed: onWishlistToggle,
                        ),
                      ),
                    Positioned(
                      left: OmSpacing.sm,
                      bottom: OmSpacing.sm,
                      child: Wrap(
                        spacing: OmSpacing.xs,
                        runSpacing: OmSpacing.xs,
                        children: <Widget>[
                          if (product.isSoldOut)
                            const OmBadge(label: 'Sold out', tone: OmTone.danger, dense: true),
                          if (!product.isSoldOut && product.isLowStock)
                            const OmBadge(label: 'Low stock', tone: OmTone.warning, dense: true),
                          if (product.isBestSeller)
                            const OmBadge(label: 'Bestseller', tone: OmTone.gold, dense: true),
                          if (product.isNewArrival)
                            const OmBadge(label: 'New', tone: OmTone.info, dense: true),
                          if (product.isWholesaleOnly)
                            const OmBadge(label: 'Wholesale', tone: OmTone.neutral, dense: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(OmSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OmText(product.name, maxLines: 2, variant: OmTextVariant.bodyStrong),
                    if (product.packSize.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      OmText(product.packSize, variant: OmTextVariant.caption),
                    ],
                    const SizedBox(height: OmSpacing.sm),
                    if (line.hasError)
                      OmText('Price on request', variant: OmTextVariant.caption)
                    else
                      OmPriceTag(resolution: line.resolution, compact: true, showStrikeThrough: false),
                    if (product.hasQuantitySlabs && !line.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: OmText(
                          'Bulk discounts available',
                          variant: OmTextVariant.caption,
                          color: OmColors.gold,
                        ),
                      ),
                    if (product.ratingCount > 0) ...<Widget>[
                      const SizedBox(height: OmSpacing.xs),
                      Row(
                        children: <Widget>[
                          Icon(Icons.star, size: 14, color: OmColors.gold),
                          const SizedBox(width: 2),
                          OmText(
                            '${product.ratingAvg.toStringAsFixed(1)} (${product.ratingCount})',
                            variant: OmTextVariant.caption,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
