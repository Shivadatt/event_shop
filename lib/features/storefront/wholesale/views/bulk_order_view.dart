import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/wholesale/wholesale_controller.dart';

/// `/wholesale/bulk-order`. Paste SKU + qty lines, resolve them against the live catalogue and
/// carry the intent into the cart. Prices shown are `PricingEngine` display math; the payable
/// figure is whatever `OrderRepository.createOrder` returns at checkout.
final class BulkOrderView extends GetView<BulkOrderController> {
  const BulkOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Bulk order',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const OmSectionHeader(
              title: 'Paste your buy list',
              subtitle:
                  'One line per item: `SKU, quantity`. Commas, tabs, spaces, colons and semicolons '
                  'all separate the two. A line without a quantity is rejected rather than guessed.',
            ),
            const SizedBox(height: OmSpacing.lg),
            Obx(
              () => controller.rows.isEmpty && !controller.resolving.value
                  ? _PastePanel(controller: controller)
                  : _Results(controller: controller),
            ),
            const SizedBox(height: OmSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _PastePanel extends StatelessWidget {
  const _PastePanel({required this.controller});

  final BulkOrderController controller;

  @override
  Widget build(BuildContext context) => OmCard(
        elevated: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmTextField(
              label: 'Buy list',
              controller: controller.paste,
              maxLines: 12,
              minLines: 8,
              keyboardType: TextInputType.text,
              counterText: '',
              hint: 'OME-BAL-11\nODE-BACK-02, 24',
              helper: 'Tip: export the SKU column from your purchase book and paste it here.',
            ),
            const SizedBox(height: OmSpacing.md),
            Obx(() => Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  children: <Widget>[
                    OmButton(
                      label: 'Check my lines',
                      icon: Icons.fact_check_outlined,
                      loading: controller.resolving.value,
                      busyLabel: 'Checking…',
                      onPressed: controller.hasInput ? controller.resolve : null,
                    ),
                    OmButton(
                      label: 'Clear',
                      variant: OmButtonVariant.secondary,
                      onPressed: controller.clear,
                    ),
                    OmButton(
                      label: 'Request a quotation instead',
                      variant: OmButtonVariant.ghost,
                      onPressed: () =>
                          Get.toNamed<dynamic>(OmRoutes.wholesaleQuotation),
                    ),
                  ],
                )),
            Obx(() {
              final failure = controller.failure.value;
              if (failure == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: OmSpacing.md),
                child: OmCard(
                  borderColor: OmColors.danger,
                  padding: const EdgeInsets.all(OmSpacing.sm),
                  child: OmText(failure.message,
                      variant: OmTextVariant.caption, overflow: TextOverflow.visible),
                ),
              );
            }),
            const SizedBox(height: OmSpacing.md),
            OmText(
              'Availability is advisory here: the server re-checks stock and every price when the '
              'order is created, so a resolved line is an intent, not a reservation.',
              variant: OmTextVariant.caption,
              overflow: TextOverflow.visible,
            ),
          ],
        ),
      );
}

class _Results extends StatelessWidget {
  const _Results({required this.controller});

  final BulkOrderController controller;

  @override
  Widget build(BuildContext context) {
    final valid = controller.validRows;
    final rejected = controller.rejectedRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OmCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.xs,
                  children: <Widget>[
                    OmBadge(
                      label: '${valid.length} line(s) ready',
                      tone: OmTone.success,
                      icon: Icons.check_circle_outline,
                    ),
                    if (rejected.isNotEmpty)
                      OmBadge(
                        label: '${rejected.length} rejected',
                        tone: OmTone.danger,
                        icon: Icons.report_gmailerrorred_outlined,
                      ),
                    if (controller.warnCountValue > 0)
                      OmBadge(
                        label: '${controller.warnCountValue} to review',
                        tone: OmTone.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                  ],
                ),
              ),
              OmButton(
                label: 'Edit list',
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                onPressed: controller.clear,
              ),
            ],
          ),
        ),
        const SizedBox(height: OmSpacing.lg),
        if (valid.isEmpty)
          OmEmptyState(
            title: 'Nothing matched',
            message: 'Every line was rejected. Check the SKU text against the catalogue and try again.',
            icon: Icons.search_off,
            actionLabel: 'Edit list',
            onAction: controller.clear,
          )
        else
          OmResponsiveTable(
            minTableWidth: OmBreakpoints.laptop,
            table: _ResolvedTable(rows: valid),
            asCards: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final row in valid) ...<Widget>[
                  _ResolvedCard(row: row),
                  const SizedBox(height: OmSpacing.sm),
                ],
              ],
            ),
          ),
        if (rejected.isNotEmpty) ...<Widget>[
          const SizedBox(height: OmSpacing.lg),
          const OmSectionHeader(
            title: 'Rejected lines',
            subtitle: 'These stay visible on purpose — nothing is quietly dropped.',
          ),
          const SizedBox(height: OmSpacing.md),
          for (final row in rejected) ...<Widget>[
            _RejectedCard(row: row),
            const SizedBox(height: OmSpacing.sm),
          ],
        ],
        const SizedBox(height: OmSpacing.lg),
        OmButton(
          label: 'Add ${valid.length} line(s) to cart',
          icon: Icons.shopping_cart_checkout_outlined,
          expanded: context.isCompactLayout,
          onPressed: controller.addValidLinesToCart,
        ),
        OmText(
          'Cart totals, freight and the payable amount are computed at checkout by the server.',
          variant: OmTextVariant.caption,
        ),
        const SizedBox(height: OmSpacing.md),
      ],
    );
  }
}

class _ResolvedTable extends StatelessWidget {
  const _ResolvedTable({required this.rows});

  final List<BulkRow> rows;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(1.4),
              2: FlexColumnWidth(1.6),
              3: FlexColumnWidth(1.6),
              4: FlexColumnWidth(1.6),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  _heading(context, 'Product'),
                  _heading(context, 'Qty'),
                  _heading(context, 'Rate'),
                  _heading(context, 'Slab'),
                  _heading(context, 'Line total', align: TextAlign.end),
                ],
              ),
              for (final row in rows)
                TableRow(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          OmText(row.product?.name ?? row.input, variant: OmTextVariant.bodyStrong),
                          OmText(row.input, variant: OmTextVariant.caption),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm),
                      child: OmText('${row.qty}', variant: OmTextVariant.body),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm),
                      child: OmMoneyText(row.price?.resolution.unitPricePaise ?? 0, decimals: false),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm),
                      child: OmText(
                        row.price?.resolution.slabDescription ?? 'List price',
                        variant: OmTextVariant.caption,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm),
                      child: OmMoneyText(
                        row.price?.resolution.lineTotalPaise ?? 0,
                        decimals: false,
                        style: styles.price,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (rows.any((row) => row.warning != null)) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            for (final row in rows.where((row) => row.warning != null))
              OmText(
                '${row.product?.name ?? row.input}: ${row.warning}',
                variant: OmTextVariant.caption,
                color: OmColors.warning,
                overflow: TextOverflow.visible,
              ),
          ],
        ],
      ),
    );
  }

  static Widget _heading(BuildContext context, String label, {TextAlign align = TextAlign.start}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: OmSpacing.xs),
        child: Text(label.toUpperCase(), textAlign: align, style: context.omText.label),
      );
}

class _ResolvedCard extends StatelessWidget {
  const _ResolvedCard({required this.row});

  final BulkRow row;

  @override
  Widget build(BuildContext context) {
    final price = row.price;
    final resolution = price?.resolution;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OmText(row.product?.name ?? row.input, variant: OmTextVariant.bodyStrong),
                    OmText('${row.input} · qty ${row.qty}', variant: OmTextVariant.caption),
                  ],
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              if (resolution != null)
                OmPriceTag(resolution: resolution, compact: true, showStrikeThrough: false),
            ],
          ),
          if (resolution != null && resolution.slab != null) ...<Widget>[
            const SizedBox(height: OmSpacing.xs),
            OmBadge(
              dense: true,
              tone: OmTone.gold,
              label: resolution.slabDescription,
            ),
          ],
          if (row.warning != null) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            OmText(row.warning!, variant: OmTextVariant.caption, overflow: TextOverflow.visible),
          ],
        ],
      ),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({required this.row});

  final BulkRow row;

  @override
  Widget build(BuildContext context) => OmCard(
        borderColor: OmColors.danger,
        padding: const EdgeInsets.all(OmSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.block, size: 18, color: OmColors.danger),
            const SizedBox(width: OmSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OmText(
                    row.product?.name ?? row.input,
                    variant: OmTextVariant.bodyStrong,
                  ),
                  OmText(
                    'Qty ${row.qty > 0 ? row.qty : '—'} · ${row.error ?? 'Not orderable'}',
                    variant: OmTextVariant.caption,
                    overflow: TextOverflow.visible,
                  ),
                ],
              ),
            ),
            if (row.product != null)
              OmButton(
                label: 'Open',
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                onPressed: () =>
                    Get.toNamed<dynamic>(OmRoutes.forProduct(row.product!.pathSlug)),
              ),
          ],
        ),
      );
}
