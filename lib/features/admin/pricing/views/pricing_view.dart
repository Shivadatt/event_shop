import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/pricing/pricing_controller.dart';
import 'package:om_events/features/admin/products/widgets/slab_grid_editor.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Cross-product price-band management plus negotiated per-customer prices.
///
/// Both halves are privileged and guarded by `PricingAdminGuard` at the route. A grid is validated
/// with the shared engine before save, and an override is only ever applied by the backend — this
/// screen records intent, it does not itself set a live price.
final class PricingView extends StatefulWidget {
  const PricingView({super.key});

  @override
  State<PricingView> createState() => _PricingViewState();
}

class _PricingViewState extends State<PricingView> {
  final TextEditingController _uid = TextEditingController();
  final TextEditingController _product = TextEditingController();
  final TextEditingController _variant = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime? _expires;

  @override
  void dispose() {
    _uid.dispose();
    _product.dispose();
    _variant.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PricingController>();
    return AdminScaffold(
      title: 'Pricing',
      child: OmAdminPage(
        title: 'Pricing control',
        eyebrow: 'Privileged',
        subtitle: 'Quantity bands and negotiated customer prices. Everything here is re-validated and '
            'role-checked by the server on save; the pricing engine stays the single source of truth.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const OmAdminNotice(
              tone: OmTone.warning,
              icon: Icons.lock_outline,
              title: 'Privileged area',
              message: 'This route is behind PricingAdminGuard. Hiding it is a convenience; the write '
                  'functions are the permission.',
            ),
            const SizedBox(height: OmSpacing.lg),
            _slabSection(controller),
            const SizedBox(height: OmSpacing.xl),
            _overrideSection(controller),
          ],
        ),
      ),
    );
  }

  Widget _slabSection(PricingController controller) => OmAdminSection(
        title: 'Product price bands',
        subtitle: 'Pick a product, edit its bands, save. A band price applies to every unit once the '
            'order reaches that band; quantities below the first band pay the shelf price.',
        child: Obx(() {
          final product = controller.selected.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OmDropdown<Product>(
                label: 'Product',
                value: product,
                items: controller.products.toList(growable: false),
                itemLabel: (p) => p.name.isEmpty ? p.id : p.name,
                hint: controller.products.isEmpty ? 'Loading products…' : 'Select a product',
                onChanged: (p) => controller.selectProduct(p),
              ),
              if (controller.isLoading.value && controller.products.isEmpty) const OmLoading(),
              if (product != null) ...<Widget>[
                const SizedBox(height: OmSpacing.lg),
                OmSlabGridEditor(
                  product: product,
                  slabs: controller.workingSlabs.toList(growable: false),
                  error: controller.slabError.value,
                  errorRowIndex: controller.slabErrorRow.value,
                  onChanged: controller.onSlabsChanged,
                ),
                const SizedBox(height: OmSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: OmButton(
                    label: 'Save price bands (privileged)',
                    icon: controller.slabError.value == null ? Icons.save_outlined : Icons.error_outline,
                    loading: controller.isSubmitting.value,
                    onPressed: controller.slabError.value != null
                        ? null
                        : () => controller.saveSlabs(),
                  ),
                ),
              ],
            ],
          );
        }),
      );

  Widget _overrideSection(PricingController controller) => OmAdminSection(
        title: 'Negotiated customer prices',
        subtitle: 'A per-customer override beats public bands but is applied only by the backend.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (controller.overridesListUnavailable.value)
              const OmAdminNotice(
                message: 'Existing overrides cannot be listed yet: AdminRepository has no customer-price '
                    'listing method (see PricingController.loadOverrides). Add and delete-by-id work; '
                    'the panel below only reflects what you add in this session.',
                tone: OmTone.info,
              ),
            const SizedBox(height: OmSpacing.md),
            OmAdminFormGrid(
              children: <Widget>[
                OmTextField(label: 'Customer uid', controller: _uid),
                OmTextField(label: 'Product id', controller: _product),
                OmTextField(
                  label: 'Variant id (optional)',
                  controller: _variant,
                  helper: 'Blank applies to the product-level price.',
                ),
                OmTextField(
                  label: 'Unit price (₹)',
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
            const SizedBox(height: OmSpacing.sm),
            OmTextField(label: 'Note', controller: _note, maxLines: 2),
            const SizedBox(height: OmSpacing.sm),
            OmAdminDateField(
              label: 'Expires (optional)',
              value: _expires,
              onChanged: (v) => setState(() => _expires = v),
            ),
            const SizedBox(height: OmSpacing.md),
            OmButton(
              label: 'Save override (privileged)',
              icon: Icons.lock_outline,
              loading: controller.isSubmitting.value,
              onPressed: () => controller.addOverride(
                uid: _uid.text,
                productId: _product.text,
                unitPricePaise: OmMoney.parseRupeeString(_price.text),
                variantId: _variant.text,
                note: _note.text,
                expiresAt: _expires,
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            Obx(() {
              if (controller.overrides.isEmpty) {
                return const OmAdminNotice(
                  message: 'No overrides added in this session.',
                  tone: OmTone.neutral,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final o in controller.overrides)
                    _OverrideRow(controller: controller, override: o),
                ],
              );
            }),
          ],
        ),
      );
}

class _OverrideRow extends StatelessWidget {
  const _OverrideRow({required this.controller, required this.override});

  final PricingController controller;
  final CustomerPriceOverride override;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: OmSpacing.sm),
        child: OmAdminRowCard(
          title: '${override.uid} → ${override.productId}',
          badges: <Widget>[
            OmBadge(
              label: override.isAlive() ? 'Active' : 'Expired',
              tone: override.isAlive() ? OmTone.success : OmTone.neutral,
              dense: true,
            ),
          ],
          lines: <String>[
            'Unit price ${OmMoney.format(override.unitPricePaise)}',
            if (override.variantId != null) 'Variant ${override.variantId}',
            if (override.note.isNotEmpty) override.note,
            if (override.expiresAt != null) 'Expires ${AdminFormat.date(override.expiresAt)}',
            'id: ${override.id}',
          ],
          actions: <Widget>[
            OmButton(
              label: 'Delete override',
              variant: OmButtonVariant.danger,
              size: OmButtonSize.small,
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await omConfirmAdminAction(
      context: context,
      title: 'Remove this customer override?',
      message: 'The backend stops applying this negotiated price. This is audited.',
    );
    if (confirmed) await controller.deleteOverride(override.id);
  }
}
