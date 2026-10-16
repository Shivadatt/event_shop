import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/account/account_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';

/// `/account` profile edit. Email is shown but not editable — it is the auth identity, owned by
/// Firebase, not a profile field.
final class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'My details',
      subtitle: 'Used to prefill checkout and invoices. The store keeps the copy; this page is '
          'the request to change it.',
      currentRoute: OmRoutes.account,
      body: Obx(() {
        final profile = controller.profile;
        if (profile == null) {
          return OmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                OmText('Sign in to edit your details.', variant: OmTextVariant.h3),
                const SizedBox(height: OmSpacing.md),
                OmButton(
                  label: 'Sign in',
                  onPressed: () => Get.toNamed<dynamic>(OmRoutes.login),
                ),
              ],
            ),
          );
        }

        final failure = controller.failure.value;
        return OmCard(
          elevated: true,
          child: Form(
            key: controller.formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmInfoRow(
                  label: 'Email',
                  value: controller.email.isEmpty ? '—' : controller.email,
                  trailing: const OmBadge(label: 'Cannot be changed here', dense: true),
                ),
                const OmDivider(space: OmSpacing.sm),
                OmTextField(
                  label: 'Full name',
                  controller: controller.displayName,
                  keyboardType: TextInputType.name,
                  prefixIcon: Icons.badge_outlined,
                  validator: (value) => OmValidators.required(value, label: 'Name'),
                  required: true,
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Mobile number',
                  controller: controller.phone,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                  helper: 'Delivery updates and counter contact.',
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? null : OmValidators.phone(value),
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Company / firm name',
                  controller: controller.companyName,
                  keyboardType: TextInputType.name,
                  prefixIcon: Icons.business_outlined,
                  helper: 'Printed on wholesale invoices when you have one.',
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'GSTIN',
                  controller: controller.gstNumber,
                  prefixIcon: Icons.receipt_long_outlined,
                  helper: 'Optional. Uppercased for you when saved.',
                  maxLength: 15,
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    if (!RegExp(r'^[0-9A-Z]{15}$').hasMatch(text.toUpperCase())) {
                      return 'GSTIN is 15 characters, letters and digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: OmSpacing.lg),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  children: <Widget>[
                    OmButton(
                      label: 'Save changes',
                      loading: controller.busy.value,
                      busyLabel: 'Saving…',
                      onPressed: controller.save,
                    ),
                    OmButton(
                      label: 'Reload saved values',
                      variant: OmButtonVariant.secondary,
                      onPressed: controller.discardChanges,
                    ),
                  ],
                ),
                if (controller.saved.value && failure == null) ...<Widget>[
                  const SizedBox(height: OmSpacing.md),
                  OmText(
                    'Saved. The store confirmed the write; your session updates from it.',
                    variant: OmTextVariant.caption,
                    color: OmColors.success,
                    overflow: TextOverflow.visible,
                  ),
                ],
                if (failure != null) ...<Widget>[
                  const SizedBox(height: OmSpacing.md),
                  OmCard(
                    borderColor: OmColors.danger,
                    padding: const EdgeInsets.all(OmSpacing.sm),
                    child: OmText(failure.message,
                        variant: OmTextVariant.caption, overflow: TextOverflow.visible),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}
