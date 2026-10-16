import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/storefront/checkout/checkout_controller.dart';

/// Step 1: who the order belongs to. A guest may check out when the store allows it; otherwise
/// this step is a sign-in door, and nothing about the identity is faked locally.
final class CheckoutContactStep extends StatelessWidget {
  const CheckoutContactStep({super.key, required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Form(
      key: controller.contactForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Obx(() {
            if (controller.isSignedIn) return const SizedBox.shrink();
            final gate = controller.guestGate;
            if (gate == null) {
              return const _Notice(
                tone: OmTone.info,
                text: 'Checking out as a guest. Create an account after this order to keep its '
                    'history, or sign in now to link it.',
              );
            }
            return _Notice(
              tone: OmTone.warning,
              text: gate,
              action: OmButton(
                label: 'Sign in to continue',
                size: OmButtonSize.small,
                onPressed: controller.goToLogin,
              ),
            );
          }),
          const SizedBox(height: OmSpacing.md),
          OmTextField(
            label: 'Full name',
            controller: controller.name,
            required: true,
            prefixIcon: Icons.person_outline,
            autofillHints: const <String>[AutofillHints.name],
            validator: (value) => OmValidators.required(value, label: 'Full name'),
          ),
          const SizedBox(height: OmSpacing.md),
          OmTextField(
            label: 'Email',
            controller: controller.email,
            required: true,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.mail_outline,
            helper: 'The order confirmation and invoice are sent here.',
            autofillHints: const <String>[AutofillHints.email],
            validator: OmValidators.email,
          ),
          const SizedBox(height: OmSpacing.md),
          OmTextField(
            label: 'Mobile number',
            controller: controller.phone,
            required: true,
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
            helper: 'Our team calls this number for delivery updates.',
            autofillHints: const <String>[AutofillHints.telephoneNumber],
            validator: OmValidators.phone,
          ),
          const SizedBox(height: OmSpacing.md),
          OmTextField(
            label: 'GSTIN (optional)',
            controller: controller.gstNumber,
            prefixIcon: Icons.receipt_outlined,
            helper: 'Printed on the invoice for business buyers.',
            validator: (value) {
              final v = (value ?? '').trim();
              if (v.isEmpty) return null;
              return RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]{3}$').hasMatch(v.toUpperCase())
                  ? null
                  : 'GSTIN looks like 22ABCDE1234F1Z5';
            },
          ),
          const SizedBox(height: OmSpacing.lg),
          Text(
            'We never store a password or card number on this page. '
            '${controller.isSignedIn ? 'Signed in as ${controller.email.text}.' : 'Guest orders are linked to the contact details above.'}',
            style: styles.caption,
          ),
        ],
      ),
    );
  }
}

/// Step 2: how the order travels and to where.
final class CheckoutDeliveryStep extends StatelessWidget {
  const CheckoutDeliveryStep({super.key, required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: controller.deliveryForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ModeCard(
                  title: 'Courier delivery',
                  detail: controller.isPickup
                      ? 'Ship to an address by pincode.'
                      : 'Selected. We charge by delivery band.',
                  icon: Icons.local_shipping_outlined,
                  selected: controller.deliveryMode.value == DeliveryMode.courier,
                  onTap: () => controller.deliveryMode.value = DeliveryMode.courier,
                ),
                const SizedBox(height: OmSpacing.sm),
                _ModeCard(
                  title: 'Store pickup',
                  detail: controller.pickupEnabled
                      ? 'Collect from the shop counter — no delivery charge.'
                      : 'The store has switched pickup off right now.',
                  icon: Icons.storefront_outlined,
                  selected: controller.isPickup,
                  enabled: controller.pickupEnabled,
                  onTap: () => controller.deliveryMode.value = DeliveryMode.pickup,
                ),
              ],
            ),
          ),
          const SizedBox(height: OmSpacing.lg),
          Obx(
            () => controller.isPickup
                ? const _PickupCard()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (controller.addresses.isNotEmpty) _AddressPicker(controller: controller),
                      const SizedBox(height: OmSpacing.md),
                      OmTextField(
                        label: 'Address line 1',
                        controller: controller.line1,
                        required: true,
                        maxLines: 2,
                        minLines: 1,
                        prefixIcon: Icons.home_outlined,
                        keyboardType: TextInputType.streetAddress,
                        validator: (value) =>
                            OmValidators.required(value, label: 'Address'),
                      ),
                      const SizedBox(height: OmSpacing.md),
                      OmTextField(
                        label: 'Address line 2 (optional)',
                        controller: controller.line2,
                        prefixIcon: Icons.location_city_outlined,
                      ),
                      const SizedBox(height: OmSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: OmTextField(
                              label: 'City',
                              controller: controller.city,
                              required: true,
                              validator: (value) => OmValidators.required(value, label: 'City'),
                            ),
                          ),
                          const SizedBox(width: OmSpacing.md),
                          Expanded(
                            child: OmTextField(
                              label: 'State',
                              controller: controller.state,
                              required: true,
                              validator: (value) => OmValidators.required(value, label: 'State'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OmSpacing.md),
                      OmTextField(
                        label: 'Pincode',
                        controller: controller.pincode,
                        required: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        prefixIcon: Icons.pin_drop_outlined,
                        onChanged: (value) => controller.activePincode.value = value.trim(),
                        validator: controller.pincodeError,
                      ),
                      const SizedBox(height: OmSpacing.sm),
                      _ZoneHint(controller: controller),
                      if (controller.isSignedIn) ...<Widget>[
                        const SizedBox(height: OmSpacing.sm),
                        Obx(
                          () => OmSwitchRow(
                            label: 'Save this address to my account',
                            value: controller.saveAddressToBook.value,
                            onChanged: (value) => controller.saveAddressToBook.value = value,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: OmSpacing.lg),
          OmTextField(
            label: 'Note for the store (optional)',
            controller: controller.customerNote,
            maxLines: 3,
            minLines: 2,
            hint: 'Delivery day preference, decoration timing, gift message…',
            maxLength: 500,
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.detail,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String detail;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OmCard(
        onTap: enabled ? onTap : null,
        highlight: selected,
        child: Row(
          children: <Widget>[
            Icon(icon, color: selected ? OmColors.gold : context.omText.muted.color),
            const SizedBox(width: OmSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OmText(title, variant: OmTextVariant.bodyStrong),
                  const SizedBox(height: 2),
                  OmText(detail, variant: OmTextVariant.caption),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? OmColors.gold : context.omText.muted.color,
            ),
          ],
        ),
      );
}

class _AddressPicker extends StatelessWidget {
  const _AddressPicker({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = controller.selectedAddress.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OmText('Saved addresses', variant: OmTextVariant.bodyStrong),
          const SizedBox(height: OmSpacing.sm),
          for (final entry in controller.addresses)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.sm),
              child: OmCard(
                onTap: () => controller.selectAddress(entry),
                highlight: selected?.id == entry.id,
                padding: const EdgeInsets.all(OmSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      selected?.id == entry.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected?.id == entry.id
                          ? OmColors.gold
                          : context.omText.muted.color,
                    ),
                    const SizedBox(width: OmSpacing.sm),
                    Expanded(
                      child: SelectableText(
                        entry.fullAddress,
                        style: context.omText.caption,
                      ),
                    ),
                    if (entry.isDefaultShipping)
                      const OmBadge(label: 'Default', tone: OmTone.gold, dense: true),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OmButton(
              label: 'Use a new address',
              variant: OmButtonVariant.ghost,
              size: OmButtonSize.small,
              onPressed: controller.useNewAddress,
            ),
          ),
        ],
      );
    });
  }
}

class _ZoneHint extends StatelessWidget {
  const _ZoneHint({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final zone = controller.zone;
      final shipping = controller.shippingPaise;
      final parts = <Widget>[
        OmText(
          zone == null ? controller.etaLabel : 'Band: ${zone.name} · ${zone.etaLabel}',
          variant: OmTextVariant.caption,
        ),
        const SizedBox(height: OmSpacing.xs),
        OmText(
          zone == null
              ? 'Shipping shown as ₹0 until a serviced pincode is entered — the server confirms '
                    'the charge when the order is created.'
              : 'Estimated delivery charge ${OmMoney.format(shipping)} (waived over the free-shipping '
                    'threshold if your order qualifies). Confirmed by the server at checkout.',
          variant: OmTextVariant.caption,
        ),
      ];
      return OmCard(
        padding: const EdgeInsets.all(OmSpacing.sm),
        borderColor: zone == null ? OmColors.line : OmColors.success,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: parts),
      );
    });
  }
}

class _PickupCard extends StatelessWidget {
  const _PickupCard();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CheckoutController>();
    return Obx(() {
      final full = controller.pickupAddress;
      return OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OmText('Pick up from', variant: OmTextVariant.bodyStrong),
            const SizedBox(height: OmSpacing.sm),
            OmText(
              full.isEmpty ? 'The store has not published a pickup address yet.' : full,
              variant: OmTextVariant.muted,
              maxLines: 4,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: OmSpacing.sm),
            OmText(controller.etaLabel, variant: OmTextVariant.caption),
            const SizedBox(height: OmSpacing.sm),
            OmText(
              'No delivery charge is added for pickup. The confirmed bill still comes from the '
              'order server.',
              variant: OmTextVariant.caption,
            ),
          ],
        ),
      );
    });
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.tone, required this.text, this.action});

  final OmTone tone;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      OmTone.warning => OmColors.warning,
      OmTone.danger => OmColors.danger,
      _ => OmColors.info,
    };
    return OmCard(
      borderColor: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: OmSpacing.sm),
          Expanded(child: OmText(text, variant: OmTextVariant.caption)),
          if (action != null) ...<Widget>[
            const SizedBox(width: OmSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}
