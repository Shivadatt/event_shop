import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/admin/products/products_controller.dart';
import 'package:om_events/features/admin/products/widgets/slab_grid_editor.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_slabs.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Variant list and editor for one product.
///
/// Variants are separate documents written through `AdminRepository.saveVariant`, so a variant is
/// never smuggled into the product write. Each row owns its slab grid, because a customer's band
/// belongs to the thing they actually ordered. Cost price is only *displayed* for roles that may
/// see it; stripping it client-side would let a staff save wipe a stored cost, so the field is
/// round-tripped and the server decides what it persists.
final class OmProductVariantsEditor extends StatefulWidget {
  const OmProductVariantsEditor({super.key, required this.controller, required this.product});

  final ProductEditController controller;
  final Product product;

  @override
  State<OmProductVariantsEditor> createState() => _OmProductVariantsEditorState();
}

class _OmProductVariantsEditorState extends State<OmProductVariantsEditor> {
  String? _openId;
  bool _adding = false;

  void _toggle(String id) => setState(() => _openId = _openId == id ? null : id);

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Variants',
        subtitle: 'A variant is a separate price and stock line under this product. Products with '
            'no variants sell as a single option.',
        spaceAbove: 0,
        action: _adding ? null : 'Add variant',
        onActionTap: _adding ? null : () => setState(() => _adding = true),
        child: Obx(() {
          final rows = widget.controller.variantRows;
          final canEdit = widget.controller.product.value != null && widget.product.id.isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!canEdit)
                const OmAdminNotice(
                  tone: OmTone.info,
                  icon: Icons.info_outline,
                  message: 'Save the product first: a variant row must belong to a product id.',
                ),
              if (rows.isEmpty && !_adding)
                OmCard(
                  child: OmEmptyState(
                    compact: true,
                    icon: Icons.category_outlined,
                    title: 'No variants',
                    message: 'This product sells as one option at its own price bands.',
                  ),
                )
              else
                for (final variant in rows)
                  _VariantCard(
                    key: ValueKey<String>(variant.id),
                    variant: variant,
                    product: widget.product,
                    controller: widget.controller,
                    expanded: _openId == variant.id,
                    onToggle: () => _toggle(variant.id),
                    onClose: () => setState(() => _openId = null),
                  ),
              if (_adding)
                _VariantForm(
                  key: const ValueKey<String>('new-variant'),
                  product: widget.product,
                  controller: widget.controller,
                  existing: null,
                  onSaved: () => setState(() {
                    _adding = false;
                    _openId = null;
                  }),
                  onCancel: () => setState(() => _adding = false),
                )
              else if (canEdit && rows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: OmSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OmButton(
                      label: 'Add another variant',
                      icon: Icons.add,
                      variant: OmButtonVariant.ghost,
                      size: OmButtonSize.small,
                      onPressed: () => setState(() => _adding = true),
                    ),
                  ),
                ),
              const SizedBox(height: OmSpacing.sm),
              const OmAdminNotice(
                message: 'Variant price bands run the shared validator before the write, and the '
                    'write itself goes to a staff-gated repository method. Stock is not editable '
                    'here: it is only ever moved by an inventory adjustment, which appends a '
                    'ledger row.',
              ),
            ],
          );
        }),
      );
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    super.key,
    required this.variant,
    required this.product,
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.onClose,
  });

  final ProductVariant variant;
  final Product product;
  final ProductEditController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return OmCard(
      padding: const EdgeInsets.all(OmSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OmText(
                      variant.name.isEmpty ? '(unnamed variant)' : variant.name,
                      variant: OmTextVariant.bodyStrong,
                    ),
                    const SizedBox(height: OmSpacing.xs),
                    Text(
                      <String>[
                        variant.sku.isEmpty ? 'no SKU' : variant.sku,
                        '${AdminFormat.rupeeText(variant.retailPricePaise)} each',
                        '${variant.slabs.length} bands',
                        'min ${variant.minOrderQty}',
                        'stock ${variant.stockQty}',
                      ].join('  ·  '),
                      style: styles.caption,
                    ),
                  ],
                ),
              ),
              if (!variant.isActive)
                const OmBadge(tone: OmTone.neutral, dense: true, label: 'Hidden'),
              const SizedBox(width: OmSpacing.sm),
              OmButton(
                label: expanded ? 'Close' : 'Edit',
                size: OmButtonSize.small,
                variant: OmButtonVariant.ghost,
                onPressed: onToggle,
              ),
            ],
          ),
          if (controller.canSeeCost && variant.costPricePaise != null) ...<Widget>[
            const SizedBox(height: OmSpacing.xs),
            OmText(
              'Cost price: ${OmMoney.format(variant.costPricePaise!)} per unit '
              '(visible to admin and owner roles only)',
              variant: OmTextVariant.caption,
              maxLines: 2,
            ),
          ],
          if (expanded) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            _VariantForm(
              key: ValueKey<String>('form-${variant.id}'),
              product: product,
              controller: controller,
              existing: variant,
              onSaved: onClose,
              onCancel: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

class _VariantForm extends StatefulWidget {
  const _VariantForm({
    super.key,
    required this.product,
    required this.controller,
    required this.existing,
    required this.onSaved,
    required this.onCancel,
  });

  final Product product;
  final ProductEditController controller;
  final ProductVariant? existing;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_VariantForm> createState() => _VariantFormState();
}

class _VariantFormState extends State<_VariantForm> {
  late final TextEditingController _name = _t(widget.existing?.name ?? '');
  late final TextEditingController _sku = _t(widget.existing?.sku ?? '');
  late final TextEditingController _optionLabel = _t(widget.existing?.optionLabel ?? '');
  late final TextEditingController _optionValue = _t(widget.existing?.optionValue ?? '');
  late final TextEditingController _price =
      _t(AdminFormat.rupeeText(widget.existing?.retailPricePaise ?? widget.product.basePricePaise));
  late final TextEditingController _minQty = _t('${widget.existing?.minOrderQty ?? 1}');
  late final TextEditingController _cost = _t(
    widget.existing?.costPricePaise == null
        ? ''
        : AdminFormat.rupeeText(widget.existing!.costPricePaise!),
  );
  late bool _isActive = widget.existing?.isActive ?? true;
  late List<PriceSlab> _slabs = [...(widget.existing?.slabs ?? const <PriceSlab>[])];
  String? _slabError;
  int? _slabErrorRow;

  static TextEditingController _t(String value) => TextEditingController(text: value);

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _name,
      _sku,
      _optionLabel,
      _optionValue,
      _price,
      _minQty,
      _cost,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A new variant is created with an empty id; assigning the document id is the repository's job
  /// (see the NEEDS OWNER note in the agent report). Nothing here invents one client-side.
  ProductVariant get _draft => ProductVariant(
        id: widget.existing?.id ?? '',
        productId: widget.product.id,
        name: _name.text.trim(),
        sku: _sku.text.trim(),
        optionLabel: _optionLabel.text.trim(),
        optionValue: _optionValue.text.trim(),
        retailPricePaise: OmMoney.parseRupeeString(_price.text),
        slabs: _slabs,
        // Read-only echo of the ledger balance. Saving a variant is not the path that changes
        // stock, so this can never move a number on its own.
        stockQty: widget.existing?.stockQty ?? 0,
        costPricePaise: widget.controller.canSeeCost
            ? (_cost.text.trim().isEmpty ? widget.existing?.costPricePaise : OmMoney.parseRupeeString(_cost.text))
            : widget.existing?.costPricePaise,
        minOrderQty: int.tryParse(_minQty.text.trim()) ?? 1,
        imageUrl: widget.existing?.imageUrl ?? '',
        isActive: _isActive,
        order: widget.existing?.order ?? 0,
        createdAt: widget.existing?.createdAt,
        updatedAt: widget.existing?.updatedAt,
      );

  Future<void> _save() async {
    final variant = _draft;
    if (variant.name.isEmpty) {
      setState(() => _slabError = 'A variant needs a name.');
      return;
    }
    if (variant.retailPricePaise <= 0) {
      setState(() => _slabError = 'A variant needs a price above zero.');
      return;
    }
    // The same validator the cart and the Cloud Function use, run before the write so the operator
    // sees the offending row rather than a server error toast.
    final check = checkSlabGrid(_slabs);
    if (!check.isValid) {
      setState(() {
        _slabError = check.displayMessage;
        _slabErrorRow = check.rowIndex;
      });
      return;
    }
    setState(() => _slabError = null);
    await widget.controller.saveVariant(variant, slabs: _slabs);
    if (!mounted) return;
    final error = widget.controller.failure.value;
    if (error != null) {
      setState(() => _slabError = error.message);
      return;
    }
    widget.onSaved();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await omConfirmAdminAction(
      context: context,
      title: 'Delete variant ${existing.name}?',
      message: 'Past orders keep their own copy of the name and price, so history is safe. '
          'Any cart line pointing at this variant will have to be re-picked.',
      confirmLabel: 'Delete variant',
      destructive: true,
    );
    if (!ok) return;
    await widget.controller.deleteVariant(existing.id);
    if (mounted) widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final canSeeCost = widget.controller.canSeeCost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: OmSpacing.sm),
        OmAdminFormGrid(
          children: <Widget>[
            OmTextField(
              label: 'Variant name',
              controller: _name,
              required: true,
              hint: 'Gold tassel 12 m',
            ),
            OmTextField(
              label: 'SKU',
              controller: _sku,
              hint: 'OM-GLD-12M',
              validator: OmValidators.sku,
            ),
            OmTextField(
              label: 'Option label',
              controller: _optionLabel,
              helper: 'Shown above the choices on the product page, e.g. Length.',
            ),
            OmTextField(
              label: 'Option value',
              controller: _optionValue,
              helper: 'The chip the buyer taps, e.g. 12 m.',
            ),
            OmTextField(
              label: 'Retail price (rupees)',
              controller: _price,
              required: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) => OmValidators.price(value),
              onChanged: (_) => setState(() {}),
            ),
            OmNumberField(
              label: 'Minimum order quantity',
              controller: _minQty,
              min: 1,
              required: true,
              validator: (value) => OmValidators.wholeQuantity(value, minimum: 1),
              onChanged: (_) {},
            ),
            if (canSeeCost)
              OmTextField(
                label: 'Cost price (rupees)',
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                helper: 'Admin and owner only. Blank leaves the stored cost untouched.',
                onChanged: (_) {},
              ),
            OmSwitchRow(
              label: 'Visible to buyers',
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
              description: 'A hidden variant keeps its orders and history but cannot be purchased.',
            ),
          ],
        ),
        if (!canSeeCost)
          const Padding(
            padding: EdgeInsets.only(bottom: OmSpacing.md),
            child: OmAdminNotice(
              tone: OmTone.info,
              icon: Icons.lock_outline,
              message: 'Cost price is not shown to your role. The number is still carried with the '
                  'row on save, so an edit here cannot blank it, and the server re-checks the role '
                  'on the write.',
            ),
          ),
        const SizedBox(height: OmSpacing.md),
        OmSlabGridEditor(
          slabs: _slabs,
          product: widget.product,
          variant: _draft,
          enabled: widget.controller.canEditPricing,
          error: _slabError,
          errorRowIndex: _slabErrorRow,
          title: 'Price bands for this variant',
          onChanged: (next) => setState(() {
            _slabs = next;
            _slabError = null;
          }),
        ),
        const SizedBox(height: OmSpacing.md),
        Wrap(
          spacing: OmSpacing.sm,
          runSpacing: OmSpacing.sm,
          children: <Widget>[
            OmButton(
              label: widget.existing == null ? 'Create variant' : 'Save variant',
              variant: OmButtonVariant.primary,
              onPressed: widget.product.id.isEmpty ? null : _save,
            ),
            OmButton(
              label: 'Cancel',
              variant: OmButtonVariant.ghost,
              onPressed: widget.existing == null ? widget.onCancel : widget.onClose,
            ),
            if (widget.existing != null)
              OmButton(
                label: 'Delete variant',
                variant: OmButtonVariant.danger,
                size: OmButtonSize.small,
                onPressed: _delete,
              ),
          ],
        ),
      ],
    );
  }
}
