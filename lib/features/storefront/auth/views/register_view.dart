import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/auth/auth_controller.dart';
import 'package:om_events/features/storefront/auth/widgets/auth_shell.dart';

/// `/register`. Marketing consent is a stored preference, never a pre-ticked box.
final class RegisterView extends GetView<RegisterController> {
  const RegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'New here',
      title: 'Create your account',
      intro: 'One account keeps your quotes, saved addresses and order tracking together.',
      footer: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(
              child: OmButton(
                label: 'I already have an account',
                variant: OmButtonVariant.outline,
                size: OmButtonSize.small,
                expanded: true,
                onPressed: controller.goLogin,
              ),
            ),
          ],
        ),
      ],
      child: Obx(() {
        return Form(
          key: controller.formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmTextField(
                  label: 'Full name',
                  controller: controller.displayName,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.name],
                  prefixIcon: Icons.badge_outlined,
                  validator: (value) => OmValidators.required(value, label: 'Name'),
                  required: true,
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Email',
                  controller: controller.email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.email],
                  prefixIcon: Icons.alternate_email,
                  validator: OmValidators.email,
                  required: true,
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Mobile number',
                  controller: controller.phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.telephoneNumber],
                  prefixIcon: Icons.phone_outlined,
                  helper: 'Optional — used for delivery updates only.',
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? null : OmValidators.phone(value),
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Password',
                  controller: controller.password,
                  obscure: !controller.showPassword.value,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.newPassword],
                  prefixIcon: Icons.lock_outline,
                  validator: OmValidators.password,
                  required: true,
                  suffix: PasswordVisibilityToggle(
                    visible: controller.showPassword.value,
                    onPressed: () => controller.showPassword.value =
                        !controller.showPassword.value,
                  ),
                ),
                const SizedBox(height: OmSpacing.md),
                OmTextField(
                  label: 'Re-type password',
                  controller: controller.confirm,
                  obscure: !controller.showPassword.value,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.lock_reset_outlined,
                  validator: controller.validateConfirm,
                  onSubmitted: (_) => controller.submit(),
                  required: true,
                ),
                const SizedBox(height: OmSpacing.sm),
                Obx(
                  () => OmSwitchRow(
                    label: 'Send me occasional party-season offers',
                    value: controller.acceptMarketing.value,
                    onChanged: (value) => controller.acceptMarketing.value = value,
                    description: 'You can switch this off any time in account settings.',
                  ),
                ),
                const SizedBox(height: OmSpacing.md),
                OmButton(
                  label: 'Create account',
                  expanded: true,
                  loading: controller.busy.value,
                  busyLabel: 'Creating…',
                  onPressed: controller.submit,
                ),
                const SizedBox(height: OmSpacing.sm),
                const OmText(
                  'By continuing you accept the store\'s terms and privacy policy.',
                  variant: OmTextVariant.caption,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
