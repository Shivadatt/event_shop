import 'dart:async';

import 'package:flutter/material.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/cart/cart_controller.dart';

/// Cart lines in both shapes the contract asks for: a real table on wide screens, cards on
/// narrow ones. Neither variant ever scrolls sideways — [OmResponsiveTable] swaps them.
final class CartLines extends StatelessWidget {
  const CartLines({super.key, required this.controller});

  final CartController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
        final rows = controller.rows;
        return OmResponsiveTable(
          minTableWidth: 1080,
          table: _CartTable(controller: controller, rows: rows),
          asCards: Column(
            children: <Widget>[
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: OmSpacing.md),
                  child: CartLineCard(controller: controller, row: row),
                ),
            ],
          ),
        );
      });
}

class _CartTable extends StatelessWidget {
  const _CartTable({required this.controller, required this.rows});

  final CartController controller;
  final List<CartRow> rows;

  @override
  Widget build(BuildContext context) => DataTable(
        headingRowHeight: 40,
        horizontalMargin: OmSpacing.sm,
        columnSpacing: OmSpacing.xl,
        columns: <DataColumn>[
          const DataColumn(label: Text('Item')),
          const DataColumn(label: Text('Unit price')),
          const DataColumn(label: Text('Quantity')),
          const DataColumn(label: Text('Line total')),
          const DataColumn(label: Text(''), numeric: true),
        ],
        rows: <DataRow>[
          for (final row in rows)
            DataRow(
              cells: <DataCell>[
                DataCell(_LineIdentity(row: row, onOpen: () => controller.openProduct(row))),
                DataCell(
                  row.canPrice
                      ? Text(OmMoney.format(row.price.resolution.unitPricePaise))
                      : Text(
                          row.price.resolution.unitPricePaise == 0
                              ? 'Re-checked at checkout'
                              : OmMoney.format(row.price.resolution.unitPricePaise),
                          style: context.omText.caption,
                        ),
                ),
                DataCell(_QuantityControl(controller: controller, row: row)),
                DataCell(
                  row.canPrice
                      ? OmMoneyText(row.price.resolution.lineTotalPaise)
                      : Text('—', style: context.omText.muted),
                ),
                DataCell(_LineActions(controller: controller, row: row)),
              ],
            ),
        ],
      );
}

/// Card form of a single line. Public because the bulk-order grid reuses the same anatomy.
final class CartLineCard extends StatelessWidget {
  const CartLineCard({super.key, required this.controller, required this.row});

  final CartController controller;
  final CartRow row;

  @override
  Widget build(BuildContext context) {
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 76,
                width: 76,
                child: OmMediaImage(ref: row.product?.primaryImage),
              ),
              const SizedBox(width: OmSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _LineIdentity(row: row, onOpen: () => controller.openProduct(row)),
                    if (row.canPrice) ...<Widget>[
                      const SizedBox(height: OmSpacing.sm),
                      OmPriceTag(resolution: row.price.resolution, compact: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              _LineActions(controller: controller, row: row),
            ],
          ),
          const SizedBox(height: OmSpacing.md),
          Row(
            children: <Widget>[
              Expanded(child: _QuantityControl(controller: controller, row: row)),
              if (row.canPrice)
                OmMoneyText(
                  row.price.resolution.lineTotalPaise,
                  style: context.omText.price,
                ),
            ],
          ),
          if (row.canPrice && row.price.resolution.unitsToNextSlab > 0) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            OmNextSlabHint(resolution: row.price.resolution),
          ],
        ],
      ),
    );
  }
}

class _LineIdentity extends StatelessWidget {
  const _LineIdentity({required this.row, required this.onOpen});

  final CartRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final product = row.product;
    final styles = context.omText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: row.missing ? null : onOpen,
          child: Text(
            product?.name ?? 'Item still loading',
            style: row.missing ? styles.muted : styles.bodyStrong,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (product != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            <String>[
              if (product.packSize.isNotEmpty) product.packSize,
              if (row.variant != null) row.variant!.name,
              if (product.sku.isNotEmpty) 'SKU ${product.sku}',
            ].where((s) => s.isNotEmpty).join(' · '),
            style: styles.caption,
          ),
        ],
        if (row.notice != null) ...<Widget>[
          const SizedBox(height: OmSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, size: 14, color: OmColors.warning),
              const SizedBox(width: OmSpacing.xs),
              Expanded(
                child: Text(
                  row.notice!,
                  style: styles.caption.copyWith(color: OmColors.warning),
                ),
              ),
            ],
          ),
        ],
        if (row.price.error != null) ...<Widget>[
          const SizedBox(height: OmSpacing.xs),
          OmBadge(
            label: row.price.error!.message,
            tone: OmTone.warning,
            dense: true,
            icon: Icons.price_change_outlined,
          ),
        ],
      ],
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({required this.controller, required this.row});

  final CartController controller;
  final CartRow row;

  @override
  Widget build(BuildContext context) {
    final granularity = row.price.granularity;
    final product = row.product;
    final stock = row.variant?.stockQty ?? product?.stockQty;
    // An advisory ceiling only: the server re-checks stock at order creation, so a negative
    // (unknown/untracked) figure must not clamp the stepper to zero.
    final max = stock == null || stock < 0
        ? null
        : (stock < granularity.minQty ? granularity.minQty : stock);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OmQuantityStepper(
          value: row.line.qty,
          min: granularity.minQty,
          multiple: granularity.multiple,
          max: max,
          dense: true,
          label: 'Quantity for ${product?.name ?? 'cart item'}: ${row.line.qty}',
          onChanged: (next) => controller.setQuantity(row, next),
        ),
        if (granularity.multiple > 1 || granularity.minQty > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              granularity.multiple > 1
                  ? 'Min ${granularity.minQty}, in multiples of ${granularity.multiple}'
                  : 'Minimum ${granularity.minQty}',
              style: context.omText.caption,
            ),
          ),
      ],
    );
  }
}

class _LineActions extends StatelessWidget {
  const _LineActions({required this.controller, required this.row});

  final CartController controller;
  final CartRow row;

  @override
  Widget build(BuildContext context) {
    final name = row.product?.name ?? 'this item';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OmIconButton(
          icon: Icons.favorite_border,
          tooltip: 'Move $name to wishlist',
          size: 36,
          onPressed: () => unawaited(controller.moveToWishlist(row)),
        ),
        const SizedBox(width: OmSpacing.sm),
        OmIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Remove $name from cart',
          size: 36,
          onPressed: () => controller.remove(row),
        ),
      ],
    );
  }
}
