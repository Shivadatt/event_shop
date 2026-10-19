import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/settings/settings_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Store settings.
///
/// One immutable draft is edited locally and written through `saveSettings`, whose Cloud Function
/// re-checks the role. Money stays in paise and tax stays in basis points; the ₹ example under the
/// tax field is display arithmetic computed from the draft, never a stored number.
final class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsController>();
    return AdminScaffold(
      title: 'Settings',
      child: Obx(() {
        final draft = controller.draft.value;
        return OmAdminPanel<StoreSettings>(
          isLoading: controller.isLoading.value,
          hasLoaded: controller.hasDraft,
          failure: controller.failure.value,
          isEmpty: false,
          onRetry: controller.load,
          empty: const OmEmptyState(
            icon: Icons.settings_outlined,
            title: 'No settings document',
            message: 'The store settings document could not be loaded.',
          ),
          builder: (context) =>
              draft == null ? const OmLoading() : _Form(controller: controller, draft: draft),
        );
      }),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.controller, required this.draft});

  final SettingsController controller;
  final StoreSettings draft;

  @override
  Widget build(BuildContext context) => OmAdminPage(
        title: 'Store settings',
        eyebrow: 'Configuration',
        subtitle: 'These values drive the storefront, tax line, shipping and checkout. Saving is a '
            'privileged write: the function re-checks your role and appends an audit entry.',
        actions: <Widget>[
          OmButton(
            label: 'Save settings',
            icon: Icons.save_outlined,
            loading: controller.isSubmitting.value,
            onPressed: () => _save(context),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (controller.savedAt.value != null)
              OmAdminNotice(
                tone: OmTone.success,
                icon: Icons.check_circle_outline,
                message: 'Last saved ${AdminFormat.dateTime(DateTime.tryParse(controller.savedAt.value!))}.',
              ),
            _identity(context),
            _taxSection(context),
            _shippingSection(context),
            _paymentSection(context),
            _pickupSection(context),
            _reviewsSection(context),
            _socialSection(context),
            _seoSection(context),
            _policySection(context),
            const SizedBox(height: OmSpacing.xl),
            OmButton(
              label: 'Save settings (privileged write)',
              icon: Icons.lock_outline,
              loading: controller.isSubmitting.value,
              onPressed: () => _save(context),
            ),
          ],
        ),
      );

  Future<void> _save(BuildContext context) async {
    // controller.save() already announces success/failure and re-checks the role server-side;
    // the view does not fabricate a second confirmation.
    await controller.save();
  }

  Widget _identity(BuildContext context) => OmAdminSection(
        title: 'Store identity',
        subtitle: 'Name, contact and address shown across the storefront and invoices.',
        child: OmAdminFormGrid(
          children: <Widget>[
            _text('Shop name', draft.shopName, (v) => controller.set((w) => w.shopName = v)),
            _text('Tagline', draft.tagline, (v) => controller.set((w) => w.tagline = v)),
            _text('Phone', draft.phone, (v) => controller.set((w) => w.phone = v), keyboard: true),
            _text(
              'WhatsApp number',
              draft.whatsapp,
              (v) => controller.set((w) => w.whatsapp = v),
              keyboard: true,
              helper: 'Digits only. Click-to-chat link is built from this and the GST-free wa.me format.',
            ),
            _text('Email', draft.email, (v) => controller.set((w) => w.email = v)),
            _text('Opening hours', draft.openingHours, (v) => controller.set((w) => w.openingHours = v)),
            _text('Address line 1', draft.addressLine1, (v) => controller.set((w) => w.addressLine1 = v)),
            _text('Address line 2', draft.addressLine2, (v) => controller.set((w) => w.addressLine2 = v)),
            _text('City', draft.city, (v) => controller.set((w) => w.city = v)),
            _text('State', draft.state, (v) => controller.set((w) => w.state = v)),
            _text('Pincode', draft.pincode, (v) => controller.set((w) => w.pincode = v), keyboard: true),
            _text('Google Maps URL', draft.googleMapsUrl, (v) => controller.set((w) => w.googleMapsUrl = v)),
            _text('GST number', draft.gstNumber, (v) => controller.set((w) => w.gstNumber = v)),
            _text('Invoice prefix', draft.invoicePrefix, (v) => controller.set((w) => w.invoicePrefix = v)),
            _area('Description', draft.description, (v) => controller.set((w) => w.description = v)),
          ],
        ),
      );

  Widget _taxSection(BuildContext context) => OmAdminSection(
        title: 'Tax & order rules',
        subtitle: 'GST is stored as basis points (18% = 1800) so a double never touches a rupee figure.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmSwitchRow(
              label: draft.taxInclusive ? 'Prices are GST-inclusive' : 'Prices are GST-exclusive',
              value: draft.taxInclusive,
              description: 'Exclusive adds the rate below on top of line totals at checkout.',
              onChanged: (v) => controller.set((w) => w.taxInclusive = v),
            ),
            const SizedBox(height: OmSpacing.md),
            OmAdminFormGrid(
              children: <Widget>[
                _rupee(
                  'GST rate (percent)',
                  _bpsRupee(draft.taxRateBps),
                  (v) => controller.set((w) => w.taxRateBps(_bpsFromPercentInput(v))),
                  helper: '0–100. Example: 18',
                ),
                _rupee(
                  'Minimum order value (₹)',
                  _rupeeInput(draft.minOrderValuePaise),
                  (v) => controller.set((w) => w.minOrderPaise(OmMoney.parseRupeeString(v))),
                ),
                _rupee(
                  'Free shipping above (₹)',
                  draft.freeShippingAbovePaise == null ? '' : _rupeeInput(draft.freeShippingAbovePaise!),
                  (v) => controller.set((w) => w.freeShippingPaise(
                        v.trim().isEmpty ? null : OmMoney.parseRupeeString(v),
                      )),
                  helper: 'Leave blank for no store-wide free-shipping threshold.',
                ),
              ],
            ),
            const SizedBox(height: OmSpacing.md),
            OmAdminNotice(
              icon: Icons.calculate_outlined,
              message: 'Live check — ${controller.taxExample()}',
            ),
          ],
        ),
      );

  Widget _shippingSection(BuildContext context) => OmAdminSection(
        title: 'Shipping zones',
        subtitle: 'A zone matches a delivery pincode by its prefix. Rate and free-above are paise under the hood.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (draft.shippingZones.isEmpty)
              const OmAdminNotice(message: 'No shipping zones yet. Orders will fall back to the store-wide rules.')
            else
              for (final zone in draft.shippingZones)
                Padding(
                  padding: const EdgeInsets.only(bottom: OmSpacing.md),
                  child: _ZoneEditor(
                    controller: controller,
                    zone: zone,
                    key: ValueKey<String>(zone.id),
                  ),
                ),
          ],
        ),
      );

  Widget _paymentSection(BuildContext context) => OmAdminSection(
        title: 'Payment methods',
        subtitle: 'Toggling here only shows or hides a method at checkout; capture is always server verified.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (draft.paymentMethods.isEmpty)
              const OmAdminNotice(message: 'No payment methods configured for this store.')
            else
              for (final method in draft.paymentMethods)
                OmSwitchRow(
                  key: ValueKey<String>('pay-${method.code}'),
                  label: method.label,
                  value: method.isEnabled,
                  description: method.description.trim().isEmpty
                      ? 'code: ${method.code}'
                      : '${method.description} · code: ${method.code}',
                  onChanged: (v) => controller.set((w) => w.paymentEnabled(method.code, v)),
                ),
          ],
        ),
      );

  Widget _pickupSection(BuildContext context) => OmAdminSection(
        title: 'Store pickup',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmSwitchRow(
              label: 'Allow customer pickup',
              value: draft.isPickupEnabled,
              onChanged: (v) => controller.set((w) => w.isPickupEnabled = v),
            ),
            const SizedBox(height: OmSpacing.md),
            _area('Pickup notes', draft.pickupNotes, (v) => controller.set((w) => w.pickupNotes = v)),
          ],
        ),
      );

  Widget _reviewsSection(BuildContext context) => OmAdminSection(
        title: 'Reviews & checkout',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmSwitchRow(
              label: 'Auto-publish new reviews',
              value: draft.autoPublishReviews,
              description: 'Off means every review waits in the moderation queue.',
              onChanged: (v) => controller.set((w) => w.autoPublishReviews = v),
            ),
            OmSwitchRow(
              label: 'Allow guest checkout',
              value: draft.allowGuestCheckout,
              onChanged: (v) => controller.set((w) => w.allowGuestCheckout = v),
            ),
            const SizedBox(height: OmSpacing.md),
            _rupee(
              'Reports before a review is flagged',
              draft.reviewReportThreshold.toString(),
              (v) => controller.set((w) => w.reviewThreshold(int.tryParse(v.trim()) ?? draft.reviewReportThreshold)),
              helper: 'Integer count of user reports that auto-flags a review.',
            ),
          ],
        ),
      );

  Widget _socialSection(BuildContext context) {
    const known = <String>['instagram', 'facebook', 'youtube', 'twitter', 'whatsapp'];
    final keys = <String>{...known, ...draft.socialLinks.keys}.toList()..sort();
    return OmAdminSection(
      title: 'Social links',
      subtitle: 'Blank clears a link and hides its icon on the storefront.',
      child: OmAdminFormGrid(
        children: <Widget>[
          for (final key in keys)
            _text(
              _titleCase(key),
              draft.socialLinks[key] ?? '',
              (v) => controller.set((w) => w.social(key, v)),
              keySeed: 'social-$key',
            ),
        ],
      ),
    );
  }

  Widget _seoSection(BuildContext context) => OmAdminSection(
        title: 'SEO defaults',
        subtitle: 'Used when a page has no override of its own.',
        child: OmAdminFormGrid(
          children: <Widget>[
            _text('Meta title', draft.seoTitle, (v) => controller.set((w) => w.seoTitle = v)),
            _area('Meta description', draft.seoDescription, (v) => controller.set((w) => w.seoDescription = v)),
          ],
        ),
      );

  Widget _policySection(BuildContext context) => OmAdminSection(
        title: 'Policies',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _area('Cancellation policy', draft.cancellationPolicy, (v) => controller.set((w) => w.cancellationPolicy = v)),
            _area('Refund policy', draft.refundPolicy, (v) => controller.set((w) => w.refundPolicy = v)),
            _area('Shipping policy', draft.shippingPolicy, (v) => controller.set((w) => w.shippingPolicy = v)),
            _area('Privacy policy', draft.privacyPolicy, (v) => controller.set((w) => w.privacyPolicy = v)),
            _area('Terms', draft.termsPolicy, (v) => controller.set((w) => w.termsPolicy = v)),
          ],
        ),
      );

  // --- field builders -------------------------------------------------------

  Widget _text(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool keyboard = false,
    String? helper,
    String? keySeed,
  }) =>
      OmTextField(
        key: keySeed == null ? null : ValueKey<String>(keySeed),
        label: label,
        initialValue: value,
        helper: helper,
        keyboardType: keyboard ? TextInputType.phone : null,
        onChanged: onChanged,
      );

  Widget _area(String label, String value, ValueChanged<String> onChanged) => OmTextField(
        label: label,
        initialValue: value,
        maxLines: 4,
        minLines: 2,
        onChanged: onChanged,
      );

  Widget _rupee(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    String? helper,
  }) =>
      OmTextField(
        label: label,
        initialValue: value,
        helper: helper,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChanged,
      );
}

class _ZoneEditor extends StatelessWidget {
  const _ZoneEditor({required this.controller, required this.zone, super.key});

  final SettingsController controller;
  final ShippingZone zone;

  @override
  Widget build(BuildContext context) => OmAdminRowCard(
        title: zone.name.trim().isEmpty ? 'Zone ${zone.id}' : zone.name,
        badges: <Widget>[
          OmBadge(
            label: zone.isActive ? 'Active' : 'Disabled',
            tone: zone.isActive ? OmTone.success : OmTone.neutral,
            dense: true,
          ),
        ],
        lines: <String>['Covers prefixes: ${zone.pincodePrefixes.join(', ').isEmpty ? 'none' : zone.pincodePrefixes.join(', ')} · ETA ${zone.etaLabel}'],
        trailing: OmSwitchRow(
          label: '',
          value: zone.isActive,
          onChanged: (v) => controller.set((w) => w.zone(zone, isActive: v)),
        ),
        actions: <Widget>[
          OmAdminFormGrid(
            children: <Widget>[
              OmTextField(
                label: 'Zone name',
                initialValue: zone.name,
                onChanged: (v) => controller.set((w) => w.zone(zone, name: v)),
              ),
              OmTextField(
                label: 'Pincode prefixes (comma separated)',
                initialValue: zone.pincodePrefixes.join(', '),
                onChanged: (v) => controller.set(
                  (w) => w.zone(
                    zone,
                    prefixes: v
                        .split(',')
                        .map((p) => p.trim())
                        .where((p) => p.isNotEmpty)
                        .toList(growable: false),
                  ),
                ),
              ),
              OmTextField(
                label: 'Flat rate (₹)',
                initialValue: _rupeeInput(zone.flatRatePaise),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => controller.set((w) => w.zone(zone, flatRatePaise: OmMoney.parseRupeeString(v))),
              ),
              OmTextField(
                label: 'Free above (₹, blank = never free)',
                initialValue: zone.freeAbovePaise == null ? '' : _rupeeInput(zone.freeAbovePaise!),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => controller.set(
                  (w) => w.zone(
                    zone,
                    freeAbovePaise: v.trim().isEmpty ? null : OmMoney.parseRupeeString(v),
                  ),
                ),
              ),
              OmTextField(
                label: 'ETA min (days)',
                initialValue: zone.etaDaysMin.toString(),
                keyboardType: TextInputType.number,
                onChanged: (v) => controller.set((w) => w.zone(zone, etaDaysMin: int.tryParse(v.trim()) ?? zone.etaDaysMin)),
              ),
              OmTextField(
                label: 'ETA max (days)',
                initialValue: zone.etaDaysMax.toString(),
                keyboardType: TextInputType.number,
                onChanged: (v) => controller.set((w) => w.zone(zone, etaDaysMax: int.tryParse(v.trim()) ?? zone.etaDaysMax)),
              ),
            ],
          ),
        ],
      );
}

// --- numeric formatting helpers --------------------------------------------

/// Rupee text for a money field. Delegates to the shared admin formatter so there is one rupee
/// rendering in the panel; it also stays in integer paise instead of round-tripping a double.
String _rupeeInput(int paise) => AdminFormat.rupeeText(paise);

/// Basis points are shown as a plain percent number in the field (1800 -> "18").
String _bpsRupee(int bps) {
  final percent = bps / 100;
  return bps % 100 == 0 ? percent.toStringAsFixed(0) : percent.toStringAsFixed(2);
}

int _bpsFromPercentInput(String text) {
  final percent = double.tryParse(text.trim());
  if (percent == null) return 0;
  return (percent * 100).round().clamp(0, 10000);
}

String _titleCase(String key) => key.isEmpty
    ? key
    : key[0].toUpperCase() + key.substring(1);
