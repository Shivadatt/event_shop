import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/storefront/product_details/product_details_controller.dart';

/// The purchase panel: variant picker, quantity stepper bounded by the product's ordering
/// granularity, the engine's display price, slab hint, and the cart / wishlist / enquiry exits.
/// Every number shown here is display-only and comes from `PricingEngine`; the payable amount is
/// only ever confirmed by the server at checkout.
final class ProductBuyBox extends StatelessWidget {
  const ProductBuyBox({super.key, required this.controller});

  final ProductDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final product = controller.product.value;
      if (product == null) return const SizedBox.shrink();

      // Reading quantity.value here is what makes the whole panel reactive to a stepper tap.
      final qty = controller.quantity.value;
      final variants = controller.variants.toList(growable: false);
      final selected = controller.selectedVariant.value;
      final line = controller.linePrice;
      final resolution = line.resolution;
      final granularity = line.granularity;
      final soldOut = controller.isSoldOut;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MetaRow(product: product, controller: controller),
          const SizedBox(height: OmSpacing.md),
          if (variants.isNotEmpty) ...<Widget>[
            _VariantPicker(
              variants: variants,
              selected: selected,
              onSelected: controller.selectVariant,
            ),
            const SizedBox(height: OmSpacing.md),
          ],
          if (line.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.sm),
              child: OmErrorState(failure: line.error!, compact: true),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                OmPriceTag(resolution: resolution),
                const SizedBox(height: OmSpacing.sm),
                OmNextSlabHint(resolution: resolution),
              ],
            ),
          const SizedBox(height: OmSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              OmQuantityStepper(
                value: qty,
                onChanged: controller.setQuantity,
                min: granularity.minQty,
                multiple: granularity.multiple,
                enabled: !soldOut,
                label: 'Quantity for ${product.name}',
              ),
              const SizedBox(width: OmSpacing.sm),
              Expanded(
                child: OmText(
                  granularity.violationFor(qty) ??
                      'Min ${granularity.minQty}'
                          '${granularity.multiple > 1 ? ', in multiples of ${granularity.multiple}' : ''}',
                  variant: OmTextVariant.caption,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: OmButton(
                  label: soldOut ? 'Out of stock' : 'Add $qty to cart',
                  icon: Icons.shopping_bag_outlined,
                  size: OmButtonSize.large,
                  expanded: true,
                  onPressed: soldOut ? null : controller.addToCart,
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              OmIconButton(
                icon: controller.wished(product.id) ? Icons.favorite : Icons.favorite_border,
                tooltip: controller.wished(product.id)
                    ? 'Remove ${product.name} from wishlist'
                    : 'Save ${product.name} to wishlist',
                selected: controller.wished(product.id),
                size: 52,
                onPressed: () => controller.toggleWishlist(product),
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              OmButton(
                label: 'Ask on WhatsApp',
                icon: Icons.chat,
                variant: OmButtonVariant.outline,
                size: OmButtonSize.small,
                onPressed: controller.enquiryOnWhatsApp,
              ),
              OmButton(
                label: 'Store location',
                icon: Icons.place_outlined,
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                onPressed: controller.openMap,
              ),
              OmButton(
                label: 'Copy link',
                icon: Icons.link,
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                onPressed: controller.copyShareLink,
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.md),
          OmText(
            'Add to cart to see the running total. The final payable amount and stock are '
            'confirmed by the store at checkout.',
            variant: OmTextVariant.caption,
            maxLines: 3,
            overflow: TextOverflow.visible,
          ),
        ],
      );
    });
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.product, required this.controller});

  final Product product;
  final ProductDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OmText(
          product.name,
          variant: OmTextVariant.h2,
          maxLines: 3,
          overflow: TextOverflow.visible,
        ),
        const SizedBox(height: OmSpacing.xs),
        Wrap(
          spacing: OmSpacing.sm,
          runSpacing: OmSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (product.brand.isNotEmpty)
              OmText(product.brand, variant: OmTextVariant.caption),
            if (product.sku.isNotEmpty)
              OmText('SKU ${product.sku}', variant: OmTextVariant.caption),
            if (product.packSize.isNotEmpty)
              OmText(product.packSize, variant: OmTextVariant.caption),
            _StockBadge(controller: controller),
          ],
        ),
        if (product.ratingCount > 0) ...<Widget>[
          const SizedBox(height: OmSpacing.xs),
          OmText(
            '${product.ratingAvg.toStringAsFixed(1)} ★ · ${product.ratingCount} reviews',
            variant: OmTextVariant.caption,
          ),
        ],
      ],
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.controller});

  final ProductDetailsController controller;

  @override
  Widget build(BuildContext context) {
    final soldOut = controller.isSoldOut;
    final stock = controller.currentStock;
    final label = soldOut
        ? 'Out of stock'
        : (stock > 0 && stock <= 5 ? 'Only $stock left' : 'In stock');
    return OmBadge(
      label: label,
      tone: soldOut ? OmTone.danger : (stock > 0 && stock <= 5 ? OmTone.warning : OmTone.success),
      dense: true,
    );
  }
}

class _VariantPicker extends StatelessWidget {
  const _VariantPicker({
    required this.variants,
    required this.selected,
    required this.onSelected,
  });

  final List<ProductVariant> variants;
  final ProductVariant? selected;
  final ValueChanged<ProductVariant?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OmText('Options', variant: OmTextVariant.bodyStrong),
        const SizedBox(height: OmSpacing.sm),
        Wrap(
          spacing: OmSpacing.sm,
          runSpacing: OmSpacing.sm,
          children: <Widget>[
            OmFilterChip(
              label: 'Standard',
              selected: selected == null,
              onTap: () => onSelected(null),
            ),
            for (final variant in variants)
              OmFilterChip(
                label: variant.name,
                selected: selected?.id == variant.id,
                onTap: () => onSelected(variant),
              ),
          ],
        ),
      ],
    );
  }
}
