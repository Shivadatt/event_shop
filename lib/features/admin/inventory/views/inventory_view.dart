import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/inventory/inventory_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// Inventory: the stock table, the append-only movement form and the movement ledger.
///
/// One screen, three controllers (table, adjust, ledger), each owning its own read/write. Nothing
/// here sends a balance: the table mirrors the ledger and every correction writes a movement row.
final class InventoryView extends StatefulWidget {
  const InventoryView({super.key});

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  late final TextEditingController _search =
      TextEditingController(text: list.search.value);

  InventoryController get list => Get.find<InventoryController>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
        title: 'Inventory',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StockTable(search: _search),
            const _AdjustForm(),
            const _Ledger(),
            const SizedBox(height: OmSpacing.xxl),
          ],
        ),
      );
}

class _StockTable extends StatelessWidget {
  const _StockTable({required this.search});

  /// Owned by the page state so the field keeps its text across reloads and is disposed once.
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<InventoryController>();
    return Obx(() {
      final rows = controller.visibleRows;
      return OmAdminPanel<Product>(
        isLoading: controller.isLoading.value,
        hasLoaded: controller.hasLoaded.value,
        failure: controller.failure.value,
        isEmpty: rows.isEmpty,
        onRetry: () =>
            controller.isReportMode ? controller.loadLowReport() : controller.loadFirstPage(),
        empty: OmEmptyState(
          icon: Icons.warehouse_outlined,
          title: controller.isReportMode
              ? 'Nothing below its threshold'
              : (controller.hasFilters ? 'No products match' : 'No products to stock yet'),
          message: controller.isReportMode
              ? 'Every active product is above its low-stock threshold right now.'
              : 'Stock only appears once a product exists. Create one from Products first.',
          actionLabel: controller.isReportMode ? 'Show all stock' : null,
          onAction: controller.isReportMode ? () => controller.applyScope(StockScope.all) : null,
        ),
        builder: (context) => OmAdminPage(
          title: 'Stock',
          eyebrow: 'Inventory',
          subtitle: 'Balances are a read-only mirror of the ledger. A correction writes a movement '
              'row below; it never edits a number in place.',
          actions: <Widget>[
            OmButton(
              label: 'Export CSV',
              variant: OmButtonVariant.secondary,
              size: OmButtonSize.small,
              icon: Icons.download_outlined,
              onPressed: rows.isEmpty
                  ? null
                  : () => omShowAdminCsv(
                        context,
                        title: 'Stock (this page${controller.isReportMode ? ' / report' : ''})',
                        csv: controller.exportLoaded(),
                        totalRows: rows.length,
                      ),
            ),
            OmButton(
              label: 'Reload',
              variant: OmButtonVariant.ghost,
              size: OmButtonSize.small,
              icon: Icons.refresh,
              onPressed: () => controller.isReportMode
                  ? controller.loadLowReport()
                  : controller.loadFirstPage(),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Filters(controller: controller, search: search),
              const SizedBox(height: OmSpacing.lg),
              OmAdminResponsiveList(
                itemCount: rows.length,
                onTapRow: (index) => controller.select(rows[index].id),
                columns: <OmAdminColumn>[
                  OmAdminColumn(
                    heading: 'Product',
                    cell: (context, index) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        OmText(rows[index].name, variant: OmTextVariant.bodyStrong, maxLines: 2),
                        OmText(
                          AdminFormat.missing(rows[index].sku, placeholder: rows[index].slug),
                          variant: OmTextVariant.caption,
                        ),
                      ],
                    ),
                  ),
                  OmAdminColumn(
                    heading: 'Balance',
                    numeric: true,
                    cell: (context, index) =>
                        OmText('${rows[index].stockQty}', variant: OmTextVariant.price),
                  ),
                  OmAdminColumn(
                    heading: 'Threshold',
                    numeric: true,
                    cell: (context, index) => _ThresholdCell(
                      controller: controller,
                      product: rows[index],
                    ),
                  ),
                  OmAdminColumn(
                    heading: 'State',
                    cell: (context, index) => stockBadge(
                      stockQty: rows[index].stockQty,
                      lowStockThreshold: rows[index].lowStockThreshold,
                    ),
                  ),
                  OmAdminColumn(
                    heading: 'Selected',
                    cell: (context, index) {
                      final selected = controller.selectedProductId.value == rows[index].id;
                      return OmBadge(
                        dense: true,
                        tone: selected ? OmTone.gold : OmTone.neutral,
                        label: selected ? 'Pointed below' : '—',
                      );
                    },
                  ),
                ],
                cardBuilder: (context, index) => OmAdminRowCard(
                  title: rows[index].name,
                  badges: <Widget>[
                    stockBadge(
                      stockQty: rows[index].stockQty,
                      lowStockThreshold: rows[index].lowStockThreshold,
                    ),
                  ],
                  lines: <String>[
                    'Balance ${rows[index].stockQty} · threshold ${rows[index].lowStockThreshold}',
                    AdminFormat.missing(rows[index].sku, placeholder: 'no SKU'),
                  ],
                  onTap: () => controller.select(rows[index].id),
                ),
                footer: controller.isReportMode
                    ? null
                    : OmAdminPager(
                        loadedCount: rows.length,
                        hasMore: controller.hasMore,
                        isLoading: controller.isLoading.value,
                        onLoadMore: controller.loadMore,
                        onRefresh: controller.refresh,
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller, required this.search});

  final InventoryController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) => Obx(() {
        final scope = controller.scope.value;
        return OmAdminFilterBar(
          searchController: search,
          searchHint: 'Search name or SKU',
          onSearch: controller.applySearch,
          children: <Widget>[
            Wrap(
              spacing: OmSpacing.xs,
              runSpacing: OmSpacing.xs,
              children: <Widget>[
                for (final entry in const <StockScope, String>{
                  StockScope.all: 'All stock',
                  StockScope.low: 'Low & out',
                  StockScope.inStock: 'In stock',
                }.entries)
                  OmFilterChip(
                    label: entry.value,
                    selected: scope == entry.key,
                    onTap: () => controller.applyScope(entry.key),
                  ),
              ],
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

/// Threshold edit. Privileged: it writes through the product save, and `stockQty` is absent from
/// the write map, so changing a threshold can never move a balance.
class _ThresholdCell extends StatelessWidget {
  const _ThresholdCell({required this.controller, required this.product});

  final InventoryController controller;
  final Product product;

  Future<void> _edit(BuildContext context) async {
    final value = await _promptThreshold(
      context: context,
      product: product,
    );
    if (value != null) await controller.setThreshold(product, value);
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          OmText('${product.lowStockThreshold}'),
          OmIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit low-stock threshold for ${product.name}',
            size: 30,
            onPressed: () => _edit(context),
          ),
        ],
      );
}

class _AdjustForm extends StatelessWidget {
  const _AdjustForm();

  @override
  Widget build(BuildContext context) {
    final adjust = Get.find<StockAdjustController>();
    return OmAdminSection(
      title: 'Write a stock movement',
      subtitle: 'There is no "set stock to N": a balance is derived from the ledger, so a '
          'correction is a signed movement with a reason. The server recomputes the balance.',
      child: OmCard(
        child: Obx(() {
          final target = adjust.target;
          final issues = adjust.blockingIssues();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (target != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: OmSpacing.md),
                  child: OmAdminNotice(
                    icon: Icons.center_focus_strong_outlined,
                    message: 'Pointed at ${target.name}. Current mirror: ${target.stockQty}. '
                        'This figure is display only — the write recomputes the true balance.',
                  ),
                ),
              if (issues.isNotEmpty && adjust.hasLoaded.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: OmSpacing.md),
                  child: OmAdminNotice(
                    tone: OmTone.warning,
                    icon: Icons.error_outline,
                    message: issues.map((i) => '• $i').join('\n'),
                  ),
                ),
              OmAdminFormGrid(
                children: <Widget>[
                  OmDropdown<String>(
                    label: 'Product',
                    value: adjust.productId.value,
                    // `OmDropdown` has no `required` flag; the form refuses to submit without a
                    // product (StockAdjustController.blockingIssues) and the hint says so.
                    hint: 'Required — select a product',
                    items: Get.find<InventoryController>()
                        .visibleRows
                        .map((p) => p.id)
                        .toList(growable: false),
                    itemLabel: (id) => Get.find<InventoryController>()
                        .visibleRows
                        .firstWhereOrNull((p) => p.id == id)
                        ?.name ?? 'Unknown',
                    onChanged: adjust.setProduct,
                  ),
                  OmDropdown<StockMovementKind>(
                    label: 'Movement kind',
                    value: adjust.kind.value,
                    hint: 'Select a kind',
                    items: StockAdjustController.writableKinds,
                    itemLabel: stockMovementLabel,
                    onChanged: adjust.setKind,
                  ),
                  _QtyField(controller: adjust),
                  OmTextField(
                    label: 'Reason',
                    required: true,
                    initialValue: adjust.reason.value,
                    hint: 'e.g. Stock count found 3 short',
                    helper: 'Written to the ledger row and the audit log.',
                    onChanged: adjust.setReason,
                  ),
                  OmTextField(
                    label: 'Reference (optional)',
                    initialValue: adjust.reference.value,
                    hint: 'GRN / transfer / supplier invoice number',
                    onChanged: adjust.setReference,
                  ),
                  if (adjust.canSeeCost)
                    OmTextField(
                      label: 'Unit cost (rupees, privileged)',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      initialValue: adjust.unitCostText.value ?? '',
                      helper: 'Only captured because your role may see cost price.',
                      onChanged: adjust.setUnitCost,
                    )
                  else
                    OmAdminNotice.requiresRole(
                      'admin or owner',
                      title: 'Unit cost hidden',
                    ),
                ],
              ),
              const SizedBox(height: OmSpacing.lg),
              Row(
                children: <Widget>[
                  OmText(
                    adjust.kind.value == null
                        ? 'Delta: —'
                        : 'This movement changes the balance by ${adjust.signedDelta}.',
                    variant: OmTextVariant.caption,
                  ),
                  const Spacer(),
                  OmButton(
                    label: 'Clear',
                    variant: OmButtonVariant.ghost,
                    onPressed: adjust.clearForm,
                  ),
                  const SizedBox(width: OmSpacing.sm),
                  OmButton(
                    label: 'Privileged: write movement',
                    icon: Icons.playlist_add_outlined,
                    loading: adjust.isSubmitting.value,
                    onPressed: adjust.isSubmitting.value ? null : adjust.submit,
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _QtyField extends StatefulWidget {
  const _QtyField({required this.controller});

  final StockAdjustController controller;

  @override
  State<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<_QtyField> {
  late final TextEditingController _text =
      TextEditingController(text: '${widget.controller.quantity.value}');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OmNumberField(
        label: 'Quantity',
        required: true,
        controller: _text,
        min: 1,
        helper: 'Enter a positive number; the kind decides the direction.',
        onChanged: widget.controller.setQuantity,
      );
}

class _Ledger extends StatelessWidget {
  const _Ledger();

  @override
  Widget build(BuildContext context) {
    final ledger = Get.find<StockLedgerController>();
    return OmAdminSection(
      title: 'Movement ledger',
      subtitle: 'Select a product in the table above to read its movements. The running '
          '`balanceAfter` on each row is the server-computed truth.',
      child: Obx(() {
        final rows = ledger.movements;
        return OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: OmText(
                      ledger.isProductScoped
                          ? 'Movements for ${Get.find<InventoryController>().selected?.name ?? ''}'
                          : 'No product selected',
                      variant: OmTextVariant.bodyStrong,
                    ),
                  ),
                  OmButton(
                    label: 'Export ledger',
                    variant: OmButtonVariant.ghost,
                    size: OmButtonSize.small,
                    icon: Icons.download_outlined,
                    onPressed: rows.isEmpty
                        ? null
                        : () => omShowAdminCsv(
                              context,
                              title: 'Movement ledger',
                              csv: ledger.exportCsv(),
                              totalRows: rows.length,
                            ),
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.md),
              OmAdminFilterBar(
                children: <Widget>[
                  OmAdminDateField(
                    label: 'Since',
                    value: ledger.since.value,
                    onChanged: ledger.setSince,
                  ),
                  OmDropdown<StockMovementKind>(
                    label: 'Kind',
                    value: ledger.kindFilter.value,
                    hint: 'All kinds',
                    items: StockMovementKind.values,
                    itemLabel: stockMovementLabel,
                    onChanged: ledger.setKind,
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.md),
              if (ledger.crossProductUnavailable.value)
                const OmAdminNotice(
                  tone: OmTone.warning,
                  icon: Icons.report_problem_outlined,
                  title: 'Store-wide ledger not available',
                  message: 'A cross-product, kind-and-date filtered ledger needs an '
                      'AdminRepository.movements(...) query that is not implemented yet. Pick a '
                      'product above to read its ledger.',
                )
              else if (!ledger.hasLoaded.value)
                const OmLoading(message: 'Reading the ledger…')
              else if (rows.isEmpty)
                const OmEmptyState(
                  compact: true,
                  icon: Icons.history,
                  title: 'No movements recorded',
                  message: 'This product has no ledger rows yet, or none since the chosen date.',
                )
              else
                OmAdminResponsiveList(
                  itemCount: rows.length,
                  columns: <OmAdminColumn>[
                    OmAdminColumn(
                      heading: 'When',
                      cell: (context, index) => OmText(
                        AdminFormat.dateTime(rows[index].createdAt),
                        variant: OmTextVariant.caption,
                      ),
                    ),
                    OmAdminColumn(
                      heading: 'Kind',
                      cell: (context, index) => movementBadge(rows[index].kind),
                    ),
                    OmAdminColumn(
                      heading: 'Qty',
                      numeric: true,
                      cell: (context, index) => OmText(
                        rows[index].isInbound ? '+${rows[index].quantity}' : '-${rows[index].quantity}',
                        variant: OmTextVariant.bodyStrong,
                      ),
                    ),
                    OmAdminColumn(
                      heading: 'Balance after',
                      numeric: true,
                      cell: (context, index) => OmText('${rows[index].balanceAfter}'),
                    ),
                    OmAdminColumn(
                      heading: 'Reason / reference',
                      cell: (context, index) => OmText(
                        <String>[
                          AdminFormat.missing(rows[index].reason, placeholder: ''),
                          AdminFormat.missing(rows[index].reference, placeholder: ''),
                        ].where((s) => s.isNotEmpty).join(' · ').isEmpty
                            ? '—'
                            : <String>[
                                rows[index].reason,
                                rows[index].reference,
                              ].where((s) => s.trim().isNotEmpty).join(' · '),
                        variant: OmTextVariant.caption,
                        maxLines: 2,
                      ),
                    ),
                  ],
                  cardBuilder: (context, index) => OmAdminRowCard(
                    title: stockMovementLabel(rows[index].kind),
                    badges: <Widget>[movementBadge(rows[index].kind)],
                    lines: <String>[
                      '${rows[index].isInbound ? '+' : '-'}${rows[index].quantity} · '
                          'balance ${rows[index].balanceAfter}',
                      AdminFormat.dateTime(rows[index].createdAt),
                      if (rows[index].reason.trim().isNotEmpty) rows[index].reason,
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// Whole-number prompt for the low-stock threshold.
///
/// It reuses `OmNumberField` inside a plain dialog rather than adding a new shared primitive; the
/// value only feeds `InventoryController.setThreshold`, which sends a product save (the balance is
/// absent from the write map), so this dialog cannot touch stock itself.
Future<int?> _promptThreshold({
  required BuildContext context,
  required Product product,
}) async {
  final controller = TextEditingController(text: '${product.lowStockThreshold}');
  final formKey = GlobalKey<FormState>();
  int? result;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Threshold for ${product.name}'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OmNumberField(
                label: 'Low-stock threshold',
                controller: controller,
                helper: 'Flagged at or below this. Does not change the balance — only a movement '
                    'does.',
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        OmButton(
          label: 'Privileged: save threshold',
          onPressed: () {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 0) return;
            result = parsed;
            Navigator.of(dialogContext).pop();
          },
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
