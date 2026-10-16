import 'package:flutter/material.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_slabs.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Quantity-slab grid editor: the rows, the validator's verdict, and a live preview of what the
/// grid charges at real quantities.
///
/// The widget owns no truth. Every keystroke pushes a whole new `List<PriceSlab>` through
/// [onChanged], so the controller keeps the draft and the shared validator stays the only rulebook.
/// Two things are stated here rather than left to be discovered, because both have caused pricing
/// incidents elsewhere:
/// * a band's unit price applies to EVERY unit in the order once the order reaches that band — it
///   is not a marginal price for the units above the threshold;
/// * saving goes through the repository, so the Cloud Function re-validates this grid before it is
///   stored; a green tick here is not what makes the price legal.
final class OmSlabGridEditor extends StatelessWidget {
  const OmSlabGridEditor({
    super.key,
    required this.slabs,
    required this.product,
    required this.onChanged,
    this.error,
    this.errorRowIndex,
    this.variant,
    this.enabled = true,
    this.showPreview = true,
    this.title = 'Quantity price bands',
  });

  final List<PriceSlab> slabs;
  final Product product;
  final ValueChanged<List<PriceSlab>> onChanged;
  final String? error;
  final int? errorRowIndex;
  final ProductVariant? variant;
  final bool enabled;
  final bool showPreview;
  final String title;

  /// Shelf price the bands are measured against: a variant's own retail price when editing a
  /// variant grid, otherwise the product's live price (sale included).
  int get _basePricePaise =>
      variant != null && variant!.retailPricePaise > 0 ? variant!.retailPricePaise : product.basePricePaise;

  void _replace(List<PriceSlab> next) => onChanged(next);

  void _appendRow() => _replace(<PriceSlab>[
        ...slabs,
        nextSlabRow(slabs, basePricePaise: _basePricePaise),
      ]);

  void _removeAt(int index) => _replace(<PriceSlab>[
        ...slabs.sublist(0, index),
        ...slabs.sublist(index + 1),
      ]);

  void _updateAt(int index, PriceSlab slab) {
    final copy = [...slabs];
    copy[index] = slab;
    _replace(copy);
  }

  @override
  Widget build(BuildContext context) {
    return OmAdminSection(
      title: title,
      subtitle: 'A band price applies to every unit once the order reaches that band. Quantities '
          'below the first band pay the shelf price (${AdminFormat.rupeeText(_basePricePaise)}).',
      action: enabled ? 'Add band' : null,
      onActionTap: enabled ? _appendRow : null,
      spaceAbove: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!enabled)
            const Padding(
              padding: EdgeInsets.only(bottom: OmSpacing.md),
              child: OmAdminNotice(
                tone: OmTone.warning,
                icon: Icons.lock_outline,
                title: 'Read-only price grid',
                message: 'Your role can see the bands but not edit them. Price edits need the '
                    'admin or owner role, and the server checks the role on the write.',
              ),
            ),
          if (slabs.isEmpty)
            OmCard(
              child: OmEmptyState(
                compact: true,
                icon: Icons.table_rows_narrow,
                title: 'No quantity bands',
                message: 'Every quantity pays the shelf price. Add a band to discount bulk orders.',
                actionLabel: enabled ? 'Add band' : null,
                onAction: enabled
                    ? () => _replace(<PriceSlab>[
                          nextSlabRow(slabs, basePricePaise: _basePricePaise),
                        ])
                    : null,
              ),
            )
          else
            for (var index = 0; index < slabs.length; index++)
              _SlabRowEditor(
                key: ValueKey<int>(index),
                index: index,
                slab: slabs[index],
                basePricePaise: _basePricePaise,
                highlighted: errorRowIndex == index,
                enabled: enabled,
                onChange: (next) => _updateAt(index, next),
                onRemove: () => _removeAt(index),
              ),
          const SizedBox(height: OmSpacing.md),
          _SlabVerdict(error: error, slabs: slabs, isValid: error == null),
          if (showPreview && slabs.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            _SlabPreview(product: product, slabs: slabs, variant: variant),
          ],
          const SizedBox(height: OmSpacing.sm),
          const OmAdminNotice(
            message: 'Saving runs the shared slab validator here and again in the Cloud Function '
                'that writes the document. The function is the authority: a grid that disagrees '
                'with the server is rejected even when this screen showed a green tick.',
          ),
        ],
      ),
    );
  }
}

class _SlabRowEditor extends StatefulWidget {
  const _SlabRowEditor({
    super.key,
    required this.index,
    required this.slab,
    required this.basePricePaise,
    required this.onChange,
    required this.onRemove,
    required this.highlighted,
    required this.enabled,
  });

  final int index;
  final PriceSlab slab;
  final int basePricePaise;
  final ValueChanged<PriceSlab> onChange;
  final VoidCallback onRemove;
  final bool highlighted;
  final bool enabled;

  @override
  State<_SlabRowEditor> createState() => _SlabRowEditorState();
}

class _SlabRowEditorState extends State<_SlabRowEditor> {
  late final TextEditingController _min = TextEditingController(text: '${widget.slab.minQty}');
  late final TextEditingController _max =
      TextEditingController(text: widget.slab.maxQty?.toString() ?? '');
  late final TextEditingController _price =
      TextEditingController(text: AdminFormat.rupeeText(widget.slab.unitPricePaise));

  @override
  void didUpdateWidget(covariant _SlabRowEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Absorb only when the incoming value genuinely differs, so a server echo or a neighbour's
    // edit never moves the caret out from under the operator while they are typing.
    if (_parseInt(_min.text, 0) != widget.slab.minQty) {
      _min.text = '${widget.slab.minQty}';
    }
    if (_parseInt(_max.text, -1) != (widget.slab.maxQty ?? -1)) {
      _max.text = widget.slab.maxQty?.toString() ?? '';
    }
    if (OmMoney.parseRupeeString(_price.text) != widget.slab.unitPricePaise) {
      _price.text = AdminFormat.rupeeText(widget.slab.unitPricePaise);
    }
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _price.dispose();
    super.dispose();
  }

  static int _parseInt(String value, int fallback) => int.tryParse(value.trim()) ?? fallback;

  int? get _maxQty => _max.text.trim().isEmpty ? null : _parseInt(_max.text, 0);

  PriceSlab get _current => PriceSlab(
        minQty: _parseInt(_min.text, 0),
        maxQty: _maxQty,
        unitPricePaise: OmMoney.parseRupeeString(_price.text),
        label: widget.slab.label,
      );

  void _commit() => widget.onChange(_current);

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final accent = widget.highlighted ? OmColors.danger : OmColors.line;
    return Container(
      margin: const EdgeInsets.only(bottom: OmSpacing.sm),
      padding: const EdgeInsets.all(OmSpacing.md),
      decoration: BoxDecoration(
        borderRadius: OmRadius.smAll,
        border: Border.all(color: accent, width: widget.highlighted ? 1.6 : 1),
        color: widget.highlighted ? OmColors.danger.withValues(alpha: 0.06) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              OmText(
                'Band ${widget.index + 1}',
                variant: OmTextVariant.label,
                color: widget.highlighted ? OmColors.danger : null,
              ),
              const Spacer(),
              if (widget.enabled)
                OmIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove band ${widget.index + 1}',
                  size: 34,
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          OmAdminFormGrid(
            children: <Widget>[
              OmNumberField(
                label: 'From quantity',
                controller: _min,
                enabled: widget.enabled,
                required: true,
                min: 1,
                validator: (value) => OmValidators.wholeQuantity(value, minimum: 1),
                onChanged: (_) => _commit(),
              ),
              OmNumberField(
                label: 'To quantity',
                controller: _max,
                enabled: widget.enabled,
                min: 0,
                helper: 'Leave blank for an open-ended band (usually the last one).',
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  final max = int.tryParse(text);
                  if (max == null) return 'Maximum must be a whole number';
                  return OmValidators.slabRange(_parseInt(_min.text, 1), max);
                },
                onChanged: (_) => _commit(),
              ),
              OmTextField(
                label: 'Unit price (rupees)',
                controller: _price,
                enabled: widget.enabled,
                required: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                helper: 'Charged for every unit in this band.',
                validator: (value) => OmValidators.price(value),
                onChanged: (_) => _commit(),
              ),
              _SlabRowEffect(
                slab: _current,
                basePricePaise: widget.basePricePaise,
                muted: styles.muted,
              ),
            ],
          ),
          if (widget.highlighted)
            Padding(
              padding: const EdgeInsets.only(top: OmSpacing.xs),
              child: OmText(
                'The validator rejected this row.',
                variant: OmTextVariant.caption,
                color: OmColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

/// Fourth cell of a band row: what the band does to the shelf price. Derived on every build from
/// the row's own text, so nothing is stored twice.
class _SlabRowEffect extends StatelessWidget {
  const _SlabRowEffect({
    required this.slab,
    required this.basePricePaise,
    required this.muted,
  });

  final PriceSlab slab;
  final int basePricePaise;
  final TextStyle muted;

  @override
  Widget build(BuildContext context) {
    final off = basePricePaise > 0 && slab.unitPricePaise > 0
        ? OmMoney.discountPercent(basePricePaise, slab.unitPricePaise)
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OmText('EFFECT', variant: OmTextVariant.label),
        const SizedBox(height: OmSpacing.xs),
        if (slab.unitPricePaise <= 0)
          const OmText('No price entered', variant: OmTextVariant.caption)
        else
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OmMoneyText(slab.unitPricePaise),
              OmBadge(
                dense: true,
                tone: off > 0 ? OmTone.gold : (off < 0 ? OmTone.warning : OmTone.neutral),
                label: off > 0
                    ? '$off% below shelf'
                    : (off < 0 ? 'Above shelf price' : 'Same as shelf'),
              ),
            ],
          ),
        const SizedBox(height: OmSpacing.xs),
        Text(
          'Band ${slabRangeLabel(slab)} units',
          style: muted,
        ),
      ],
    );
  }
}

class _SlabVerdict extends StatelessWidget {
  const _SlabVerdict({required this.error, required this.slabs, required this.isValid});

  final String? error;
  final List<PriceSlab> slabs;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    if (!isValid) {
      return OmAdminNotice(
        tone: OmTone.danger,
        icon: Icons.error_outline,
        title: 'Grid not accepted (${slabs.length} bands)',
        message: error ?? 'The price slab grid is invalid.',
      );
    }
    if (slabs.isEmpty) return const SizedBox.shrink();
    return OmAdminNotice(
      tone: OmTone.success,
      icon: Icons.check_circle_outline,
      title: 'Grid shape is valid (${slabs.length} bands)',
      message: 'No overlapping or inverted bands, and every band carries a price. The server '
          'still has the final say when the product is saved.',
    );
  }
}

class _SlabPreview extends StatelessWidget {
  const _SlabPreview({required this.product, required this.slabs, this.variant});

  final Product product;
  final List<PriceSlab> slabs;
  final ProductVariant? variant;

  @override
  Widget build(BuildContext context) {
    final rows = previewSlabGrid(product: product, slabs: slabs, variant: variant);
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OmText('Preview at these order quantities', variant: OmTextVariant.bodyStrong),
          const SizedBox(height: OmSpacing.xs),
          const OmText(
            'Calculated by the same pricing engine the cart uses, from the unsaved grid on screen.',
            variant: OmTextVariant.caption,
            maxLines: 2,
          ),
          const SizedBox(height: OmSpacing.md),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 76,
                    child: OmText('${row.qty} units', variant: OmTextVariant.body),
                  ),
                  Expanded(
                    child: OmText(
                      row.hasBand ? row.band : 'No band - ${row.band}',
                      variant: OmTextVariant.caption,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: OmSpacing.sm),
                  SizedBox(
                    width: 112,
                    child: OmText(
                      '${OmMoney.format(row.unitPricePaise)} ea',
                      variant: OmTextVariant.price,
                      align: TextAlign.end,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  const SizedBox(width: OmSpacing.sm),
                  SizedBox(
                    width: 132,
                    child: OmText(
                      'line ${OmMoney.format(row.lineTotalPaise)}',
                      variant: OmTextVariant.bodyStrong,
                      align: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: OmSpacing.sm),
          OmSlabTable(slabs: slabs, basePricePaise: variant?.retailPricePaise ?? product.basePricePaise),
        ],
      ),
    );
  }
}
