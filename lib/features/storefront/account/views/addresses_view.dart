import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/address.dart';
import 'package:om_events/features/storefront/account/account_data_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';

/// `/account/addresses`. Card list on every breakpoint — an address is multi-line text, which no
/// table renders honestly.
final class AddressesView extends GetView<AddressController> {
  const AddressesView({super.key});

  Future<void> _openForm(BuildContext context, [AddressBookEntry? existing]) async {
    final entry = await showModalBottomSheet<AddressBookEntry>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: AddressFormSheet(existing: existing),
      ),
    );
    if (entry == null) return;
    await controller.save(entry);
  }

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'Delivery addresses',
      subtitle: 'Saved addresses only prefill checkout. An order keeps the address it was placed '
          'with, so editing one here cannot move a parcel already on its way.',
      currentRoute: OmRoutes.accountAddresses,
      actions: <Widget>[
        OmButton(
          label: 'Add address',
          icon: Icons.add_location_alt_outlined,
          size: OmButtonSize.small,
          onPressed: () => _openForm(context),
        ),
      ],
      body: Obx(() {
        if (controller.loading.value && controller.entries.isEmpty) {
          return const OmLoading(message: 'Loading your addresses…');
        }
        final failure = controller.failure.value;
        if (failure != null && controller.entries.isEmpty) {
          return OmErrorState(failure: failure, onRetry: controller.load);
        }
        if (controller.entries.isEmpty) {
          return OmEmptyState(
            title: 'No saved addresses',
            message: 'Add one now and checkout will fill itself in on the next order.',
            icon: Icons.location_off_outlined,
            actionLabel: 'Add address',
            onAction: () => _openForm(context),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (controller.busy.value)
              const Padding(
                padding: EdgeInsets.only(bottom: OmSpacing.sm),
                child: OmLoading(message: 'Saving…'),
              ),
            for (final entry in controller.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.md),
                child: _AddressCard(
                  entry: entry,
                  controller: controller,
                  onEdit: () => _openForm(context, entry),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.entry,
    required this.controller,
    required this.onEdit,
  });

  final AddressBookEntry entry;
  final AddressController controller;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return OmCard(
      highlight: entry.isDefaultShipping,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: OmText(entry.name, variant: OmTextVariant.h3)),
              if (entry.isWorkAddress)
                const OmBadge(label: 'Work', tone: OmTone.info, dense: true),
            ],
          ),
          const SizedBox(height: OmSpacing.xs),
          SelectableText(entry.fullAddress, style: context.omText.muted),
          const SizedBox(height: OmSpacing.sm),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.xs,
            children: <Widget>[
              if (entry.isDefaultShipping)
                const OmBadge(
                    label: 'Default delivery', tone: OmTone.gold, dense: true,
                    icon: Icons.star),
              if (entry.isDefaultBilling)
                const OmBadge(label: 'Default billing', tone: OmTone.neutral, dense: true),
              if (entry.gstNumber.isNotEmpty)
                OmBadge(label: 'GSTIN ${entry.gstNumber}', tone: OmTone.neutral, dense: true),
            ],
          ),
          const SizedBox(height: OmSpacing.md),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              OmButton(
                label: 'Edit',
                variant: OmButtonVariant.secondary,
                size: OmButtonSize.small,
                onPressed: onEdit,
              ),
              if (!entry.isDefaultShipping)
                OmButton(
                  label: 'Make default delivery',
                  variant: OmButtonVariant.outline,
                  size: OmButtonSize.small,
                  onPressed: () => controller.makeDefault(entry),
                ),
              if (!entry.isDefaultBilling)
                OmButton(
                  label: 'Default for billing',
                  variant: OmButtonVariant.ghost,
                  size: OmButtonSize.small,
                  onPressed: () => controller.makeDefault(entry, billing: true),
                ),
              OmButton(
                label: 'Delete',
                variant: OmButtonVariant.danger,
                size: OmButtonSize.small,
                onPressed: () => controller.remove(entry),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet form. Returns the entry to save; the controller performs the write.
final class AddressFormSheet extends StatefulWidget {
  const AddressFormSheet({super.key, this.existing});

  final AddressBookEntry? existing;

  @override
  State<AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<AddressFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final TextEditingController line1 =
      TextEditingController(text: widget.existing?.line1 ?? '');
  late final TextEditingController line2 =
      TextEditingController(text: widget.existing?.line2 ?? '');
  late final TextEditingController city =
      TextEditingController(text: widget.existing?.city ?? '');
  late final TextEditingController state =
      TextEditingController(text: widget.existing?.state ?? '');
  late final TextEditingController pincode =
      TextEditingController(text: widget.existing?.pincode ?? '');
  late final TextEditingController gstNumber =
      TextEditingController(text: widget.existing?.gstNumber ?? '');

  bool defaultShipping = false;
  bool defaultBilling = false;
  bool isWork = false;

  @override
  void initState() {
    super.initState();
    defaultShipping = widget.existing?.isDefaultShipping ?? false;
    defaultBilling = widget.existing?.isDefaultBilling ?? false;
    isWork = widget.existing?.isWorkAddress ?? false;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      name,
      phone,
      line1,
      line2,
      city,
      state,
      pincode,
      gstNumber,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = Get.find<SessionStore>().uid ?? '';
    final gst = gstNumber.text.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(OmSpacing.lg),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmSectionHeader(
                  title: widget.existing == null ? 'New address' : 'Edit address',
                  subtitle: 'Pincodes are checked against the store’s serviceable zones at '
                      'checkout.',
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Receiver name',
                  controller: name,
                  keyboardType: TextInputType.name,
                  validator: (value) => OmValidators.required(value, label: 'Name'),
                  required: true,
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Mobile number',
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  validator: OmValidators.phone,
                  required: true,
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Flat / house / street',
                  controller: line1,
                  keyboardType: TextInputType.streetAddress,
                  maxLines: 2,
                  minLines: 1,
                  validator: (value) => OmValidators.required(value, label: 'Address line'),
                  required: true,
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Area / landmark (optional)',
                  controller: line2,
                  keyboardType: TextInputType.streetAddress,
                ),
                const SizedBox(height: OmSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OmTextField(
                        label: 'City',
                        controller: city,
                        keyboardType: TextInputType.name,
                        validator: (value) => OmValidators.required(value, label: 'City'),
                        required: true,
                      ),
                    ),
                    const SizedBox(width: OmSpacing.md),
                    SizedBox(
                      width: 130,
                      child: OmTextField(
                        label: 'Pincode',
                        controller: pincode,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        validator: OmValidators.pincode,
                        required: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'State',
                  controller: state,
                  keyboardType: TextInputType.name,
                  validator: (value) => OmValidators.required(value, label: 'State'),
                  required: true,
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'GSTIN for this address (optional)',
                  controller: gstNumber,
                  maxLength: 15,
                  helper: 'Used on the invoice when this address bills the order.',
                ),
                const SizedBox(height: OmSpacing.sm),
                SwitchListTile.adaptive(
                  value: defaultShipping,
                  onChanged: (value) => setState(() => defaultShipping = value),
                  title: Text('Default delivery address', style: context.omText.bodyStrong),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: OmColors.gold,
                ),
                SwitchListTile.adaptive(
                  value: defaultBilling,
                  onChanged: (value) => setState(() => defaultBilling = value),
                  title: Text('Default billing address', style: context.omText.bodyStrong),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: OmColors.gold,
                ),
                SwitchListTile.adaptive(
                  value: isWork,
                  onChanged: (value) => setState(() => isWork = value),
                  title: Text('This is a work / venue address', style: context.omText.bodyStrong),
                  subtitle: Text('Helps the courier plan weekday delivery',
                      style: context.omText.caption),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: OmColors.gold,
                ),
                const SizedBox(height: OmSpacing.md),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  children: <Widget>[
                    OmButton(
                      label: 'Save address',
                      onPressed: () {
                        if (!(_formKey.currentState?.validate() ?? false)) return;
                        if (uid.isEmpty) {
                          Get.snackbar('Sign in first',
                              'Addresses are stored against your account.');
                          return;
                        }
                        Navigator.of(context).pop(
                          AddressBookEntry(
                            id: widget.existing?.id ?? '',
                            uid: uid,
                            name: name.text.trim(),
                            phone: phone.text.trim(),
                            line1: line1.text.trim(),
                            line2: line2.text.trim(),
                            city: city.text.trim(),
                            state: state.text.trim(),
                            pincode: pincode.text.trim(),
                            gstNumber: gst.isEmpty ? '' : gst.toUpperCase(),
                            isDefaultShipping: defaultShipping,
                            isDefaultBilling: defaultBilling,
                            isWorkAddress: isWork,
                            createdAt: widget.existing?.createdAt,
                            updatedAt: widget.existing?.updatedAt,
                          ),
                        );
                      },
                    ),
                    OmButton(
                      label: 'Cancel',
                      variant: OmButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
