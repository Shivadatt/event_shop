import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/utils/om_slug.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/products/widgets/media_editor.dart';
import 'package:om_events/features/admin/products/widgets/slab_grid_editor.dart';
import 'package:om_events/features/admin/products/widgets/variants_editor.dart';
import 'package:om_events/features/admin/products/products_controller.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// The product create/edit screen.
///
/// Text fields are seeded with `initialValue` and push every keystroke into the controller's
/// draft, so the draft is the single editable object and the form never holds a second copy of a
/// price or a slug. Two deliberate omissions:
/// * stock is read-only here — it is a mirror of the append-only ledger and is only moved by an
///   inventory adjustment;
/// * there is no product-level cost field, because `Product` has no cost member; cost is recorded
///   per variant and per stock movement, both of which gate the value server-side.
final class ProductEditView extends StatefulWidget {
  const ProductEditView({super.key});

  @override
  State<ProductEditView> createState() => _ProductEditViewState();
}

class _ProductEditViewState extends State<ProductEditView> {
  ProductEditController get controller => Get.find<ProductEditController>();

  @override
  Widget build(BuildContext context) => AdminScaffold(
        child: Obx(() {
          final product = controller.product.value;
          return OmAdminPanel<Product>(
            isLoading: controller.isLoading.value,
            hasLoaded: controller.hasLoaded.value,
            failure: controller.failure.value,
            isEmpty: product == null,
            onRetry: controller.load,
            loadingMessage: 'Loading the product…',
            empty: OmEmptyState(
              icon: Icons.search_off,
              title: 'Nothing to edit',
              message: 'The product document could not be read. Open it again from the catalogue.',
              actionLabel: 'Back to products',
              onAction: () => Get.offNamed<dynamic>(OmRoutes.adminProducts),
            ),
            builder: (context) => _Form(controller: controller, product: product!),
          );
        }),
      );
}

class _Form extends StatelessWidget {
  const _Form({required this.controller, required this.product});

  final ProductEditController controller;
  final Product product;

  /// A successful save keeps the operator on the form: the new document now has an id, which is
  /// what unlocks image attachment and variant rows. Leaving immediately would look like the save
  /// did nothing for a brand-new product.
  Future<void> _save() => controller.save();

  /// Close discards the in-memory draft — nothing is written until Save runs, so there is nothing
  /// to roll back. We return to the catalogue list rather than popping so a pasted deep link to a
  /// product does not leave the operator with an empty history.
  void _close() => Get.offNamed<dynamic>(OmRoutes.adminProducts);

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return OmAdminPage(
      title: controller.isNew ? 'New product' : product.name.isEmpty ? 'Untitled product' : product.name,
      eyebrow: 'Catalogue',
      subtitle: controller.isNew
          ? 'Draft a product. It stays invisible to customers until you set its status to active.'
          : 'Editing ${product.slug}. Changes to price bands and status are audited.',
      actions: <Widget>[
        Obx(
          () => OmButton(
            label: 'Save product',
            icon: Icons.save_outlined,
            loading: controller.isSubmitting.value,
            onPressed: controller.isSubmitting.value ? null : _save,
          ),
        ),
        OmButton(
          label: 'Close',
          variant: OmButtonVariant.ghost,
          onPressed: _close,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Obx(() {
            final issues = controller.issues;
            if (issues.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.lg),
              child: OmAdminNotice(
                tone: OmTone.danger,
                icon: Icons.report_gmailerrorred_outlined,
                title: '${issues.length} thing(s) still block this save',
                message: issues.map((i) => '• $i').join('\n'),
              ),
            );
          }),
          OmAdminSection(
            title: 'Identity',
            spaceAbove: 0,
            child: OmAdminFormGrid(
              children: <Widget>[
                OmTextField(
                  label: 'Name',
                  required: true,
                  initialValue: product.name,
                  onChanged: controller.setName,
                  validator: (value) => OmValidators.required(value, label: 'Name'),
                ),
                OmTextField(
                  label: 'SKU',
                  required: true,
                  initialValue: product.sku,
                  hint: 'OM-BAL-GOLD-12M',
                  helper: 'Unique across the catalogue; the server rejects a duplicate.',
                  onChanged: controller.setSku,
                  validator: OmValidators.sku,
                ),
                _SlugField(controller: controller, product: product),
                OmDropdown<String>(
                  label: 'Category',
                  value: product.categoryId.isEmpty ? null : product.categoryId,
                  hint: 'Choose a category',
                  items: controller.categories.map((c) => c.id).toList(growable: false),
                  itemLabel: (id) => controller
                      .categories
                      .firstWhereOrNull((c) => c.id == id)
                      ?.name ?? 'Unknown',
                  onChanged: (id) => controller.setCategory(id),
                ),
                OmTextField(
                  label: 'Brand',
                  initialValue: product.brand,
                  onChanged: controller.setBrand,
                ),
                OmTextField(
                  label: 'Pack size / unit text',
                  initialValue: product.packSize,
                  helper: 'e.g. "Pack of 12". Shown on the product card.',
                  onChanged: controller.setPackSize,
                ),
                OmTextField(
                  label: 'Unit noun',
                  initialValue: product.unit,
                  hint: 'pcs',
                  helper: 'Used by quantity steppers and cart lines.',
                  onChanged: controller.setUnit,
                ),
                OmTextField(
                  label: 'Shipping weight (grams)',
                  initialValue: product.weightGrams?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  helper: 'Blank means the courier estimate falls back to the zone default.',
                  onChanged: (value) =>
                      controller.setCostWeightGrams(int.tryParse(value.trim())),
                ),
              ],
            ),
          ),
          OmAdminSection(
            title: 'Description and search',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmTextField(
                  label: 'Description',
                  initialValue: product.description,
                  maxLines: 5,
                  hint: 'What it is, what it is for, and what is in the pack.',
                  onChanged: controller.setDescription,
                ),
                const SizedBox(height: OmSpacing.md),
                OmAdminFormGrid(
                  children: <Widget>[
                    OmTextField(
                      label: 'Tags',
                      initialValue: product.tags.join(', '),
                      helper: 'Comma separated. Used by filters and related products.',
                      onChanged: (value) => controller.setTags(_splitList(value)),
                    ),
                    OmTextField(
                      label: 'Search keywords',
                      initialValue: product.keywords.join(', '),
                      helper: 'Comma separated words buyers type that are not in the name.',
                      onChanged: (value) => controller.setKeywords(_splitList(value)),
                    ),
                    OmTextField(
                      label: 'SEO title',
                      initialValue: product.seoTitle,
                      helper: 'Blank falls back to the product name.',
                      onChanged: (value) => controller.setSeo(title: value),
                    ),
                    OmTextField(
                      label: 'Meta description',
                      initialValue: product.seoDescription,
                      onChanged: (value) => controller.setSeo(description: value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OmAdminSection(
            title: 'Price and ordering rules',
            subtitle: 'Prices are stored as paise. A quantity band is charged for every unit of '
                'the order once the order reaches that band.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmAdminFormGrid(
                  children: <Widget>[
                    OmTextField(
                      label: 'Retail price (rupees)',
                      required: true,
                      initialValue: _rupees(product.retailPricePaise),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) => OmValidators.price(value),
                      onChanged: (value) =>
                          controller.setRetailPrice(OmMoney.parseRupeeString(value)),
                    ),
                    OmTextField(
                      label: 'Sale price (rupees, optional)',
                      initialValue: product.salePricePaise == null
                          ? ''
                          : _rupees(product.salePricePaise!),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      helper: 'Must be below the retail price.',
                      onChanged: (value) {
                        final text = value.trim();
                        controller.setSalePrice(
                          text.isEmpty ? null : OmMoney.parseRupeeString(text),
                        );
                      },
                    ),
                    _DateField(
                      label: 'Sale starts',
                      value: product.saleFrom,
                      helper: 'Leave blank to run the sale until it is cleared.',
                      onChanged: controller.setSaleFrom,
                    ),
                    _DateField(
                      label: 'Sale ends',
                      value: product.saleTo,
                      onChanged: controller.setSaleTo,
                    ),
                    _IntField(
                      label: 'Minimum order quantity',
                      required: true,
                      value: product.minOrderQty,
                      onChanged: controller.setMinOrderQty,
                    ),
                    _IntField(
                      label: 'Order multiple',
                      required: true,
                      value: product.orderMultiple,
                      helper: 'Cart quantities step by this, e.g. 12 for a box.',
                      onChanged: controller.setOrderMultiple,
                    ),
                    _IntField(
                      label: 'Low-stock threshold',
                      value: product.lowStockThreshold,
                      minimum: 0,
                      helper: 'The dashboard and inventory list flag the product at or below this.',
                      onChanged: controller.setLowStockThreshold,
                    ),
                    OmDropdown<ProductStatus>(
                      label: 'Status',
                      value: product.status,
                      items: ProductStatus.values,
                      itemLabel: (status) => switch (status) {
                        ProductStatus.active => 'Active - visible and buyable',
                        ProductStatus.draft => 'Draft - hidden from the shop',
                        ProductStatus.archived => 'Archived - retired, history kept',
                      },
                      onChanged: (status) => status == null
                          ? null
                          : controller.setStatus(status),
                    ),
                  ],
                ),
                const SizedBox(height: OmSpacing.md),
                Obx(
                  () => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      OmSwitchRow(
                        label: 'Wholesale only',
                        value: product.isWholesaleOnly,
                        description: 'Buyable only by approved wholesale accounts.',
                        onChanged: (value) => controller.setFlags(wholesaleOnly: value),
                      ),
                      OmSwitchRow(
                        label: 'Feature on the home shelf',
                        value: product.isFeatured,
                        onChanged: (value) => controller.setFlags(featured: value),
                      ),
                      OmSwitchRow(
                        label: 'Mark as best seller',
                        value: product.isBestSeller,
                        onChanged: (value) => controller.setFlags(bestSeller: value),
                      ),
                      OmSwitchRow(
                        label: 'Show the new-arrival ribbon',
                        value: product.isNewArrival,
                        onChanged: (value) => controller.setFlags(newArrival: value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OmSpacing.lg),
                Obx(
                  () => OmSlabGridEditor(
                    product: controller.product.value ?? product,
                    slabs: controller.draftSlabs.toList(growable: false),
                    enabled: controller.canEditPricing,
                    error: controller.slabError.value,
                    errorRowIndex: controller.slabErrorRowIndex.value,
                    onChanged: (next) {
                      controller.draftSlabs.assignAll(next);
                      controller.validateSlabs();
                    },
                  ),
                ),
              ],
            ),
          ),
          _StockMirror(controller: controller, product: product),
          Obx(() => OmProductMediaEditor(
                controller: controller,
                product: controller.product.value ?? product,
              )),
          Obx(
            () => OmProductVariantsEditor(
              controller: controller,
              product: controller.product.value ?? product,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stock is displayed, never edited: the balance is the ledger's running total.
class _StockMirror extends StatelessWidget {
  const _StockMirror({
    required this.controller,
    required this.product,
  });

  final ProductEditController controller;
  final Product product;

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Stock on hand',
        subtitle: 'Read from the inventory ledger. Adjust it on the Inventory screen, where the '
            'move is written as a ledger row with a reason.',
        action: 'Re-read',
        onActionTap: () => controller.reloadStock(),
        child: Obx(() {
          final reported = controller.stockDisplay.value;
          return OmCard(
            child: OmAdminMetaRow(
              entries: <OmAdminMeta>[
                OmAdminMeta(
                  label: 'Balance',
                  value: reported ?? '${product.stockQty}',
                  emphasise: true,
                ),
                OmAdminMeta(
                  label: 'Low-stock flag',
                  value: switch (product.status) {
                    ProductStatus.archived => 'Not tracked (archived)',
                    _ => product.isSoldOut
                        ? 'Out of stock'
                        : (product.isLowStock ? 'Below threshold' : 'Healthy'),
                  },
                ),
                OmAdminMeta(label: 'Threshold', value: '${product.lowStockThreshold}'),
                OmAdminMeta(
                  label: 'Sold',
                  value: '${product.soldCount} units (server counter)',
                ),
              ],
            ),
          );
        }),
      );
}

/// Slug field with the availability probe. The probe is a question to the server, not a promise:
/// a concurrent save can still take the slug, and the write is what decides.
class _SlugField extends StatefulWidget {
  const _SlugField({required this.controller, required this.product});

  final ProductEditController controller;
  final Product product;

  @override
  State<_SlugField> createState() => _SlugFieldState();
}

class _SlugFieldState extends State<_SlugField> {
  late final TextEditingController _slug = TextEditingController(text: widget.product.slug);

  @override
  void dispose() {
    _slug.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: OmTextField(
                  label: 'URL slug',
                  controller: _slug,
                  required: true,
                  helper: 'Auto-filled from the name until you type one. Changing it breaks any '
                      'link already shared.',
                  validator: (value) => OmSlug.isValid((value ?? '').trim())
                      ? null
                      : 'Slug must be 2-96 lowercase letters, digits or single hyphens',
                  onChanged: (value) {
                    widget.controller.setSlug(value);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              OmButton(
                label: 'Check',
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                loading: widget.controller.checkingSlug.value,
                onPressed: () => widget.controller.checkSlug(_slug.text),
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.xs),
          Obx(() {
            final verdict = widget.controller.slugAvailability.value;
            if (verdict == null) return const SizedBox.shrink();
            return OmText(
              verdict,
              variant: OmTextVariant.caption,
              color: verdict.startsWith('Taken') || verdict.startsWith('Could not')
                  ? OmColors.danger
                  : OmColors.success,
              maxLines: 2,
            );
          }),
        ],
      );
}

/// Whole-number field whose text buffer belongs to the field, not to the rebuild loop.
///
/// The controller must not be created inside `build`: an `Obx` here re-runs on every keystroke, and
/// a fresh `TextEditingController` each time would reset the caret to position zero.
class _IntField extends StatefulWidget {
  const _IntField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.minimum = 1,
    this.required = false,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String? helper;
  final int minimum;
  final bool required;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _text = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant _IntField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (int.tryParse(_text.text.trim()) != widget.value) _text.text = '${widget.value}';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OmNumberField(
        label: widget.label,
        controller: _text,
        required: widget.required,
        min: widget.minimum,
        helper: widget.helper,
        validator: (value) => OmValidators.wholeQuantity(value, minimum: widget.minimum),
        onChanged: (value) => widget.onChanged(int.tryParse(value.trim()) ?? widget.minimum),
      );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? helper;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: label,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => OmTextField(
        label: label,
        readOnly: true,
        initialValue: value == null
            ? ''
            : '${value!.day.toString().padLeft(2, '0')}/'
                '${value!.month.toString().padLeft(2, '0')}/${value!.year}',
        hint: 'Not set',
        helper: helper,
        suffix: OmIconButton(
          icon: Icons.event_outlined,
          tooltip: 'Pick a date',
          size: 32,
          onPressed: () => _pick(context),
        ),
      );
}

String _rupees(int paise) => (paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2);

List<String> _splitList(String value) => value
    .split(',')
    .map((item) => item.trim().toLowerCase())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);
