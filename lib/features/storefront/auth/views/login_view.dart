import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/auth/auth_controller.dart';
import 'package:om_events/features/storefront/auth/widgets/auth_shell.dart';

/// `/login`. Honours the `?return=` + `&from=admin` handshake the guards emit; the controller owns
/// that logic, this screen only renders it.
final class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final failure = controller.failure.value;
      return AuthShell(
        eyebrow: 'Members',
        title: 'Sign in',
        intro:
            'Order history, saved addresses and wholesale pricing live behind this door.',
        notice:
            controller.blockedNotice ??
            (controller.isBlockedNotice
                ? 'The link you followed needs an account the store has not put on hold.'
                : null),
        footer: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: OmButton(
                  label: 'Create an account',
                  variant: OmButtonVariant.outline,
                  size: OmButtonSize.small,
                  onPressed: controller.goRegister,
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              OmButton(
                label: 'Forgot password?',
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                onPressed: controller.goForgotPassword,
              ),
            ],
          ),
        ],
        failure: failure,
        child: Form(
          key: controller.formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
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
                  label: 'Password',
                  controller: controller.password,
                  obscure: !controller.showPassword.value,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.password],
                  prefixIcon: Icons.lock_outline,
                  validator: (value) =>
                      OmValidators.required(value, label: 'Password'),
                  onSubmitted: (_) => controller.submit(),
                  suffix: PasswordVisibilityToggle(
                    visible: controller.showPassword.value,
                    onPressed: () => controller.showPassword.value =
                        !controller.showPassword.value,
                  ),
                ),
                if (failure != null && failure.isAuthFailure) ...<Widget>[
                  const SizedBox(height: OmSpacing.sm),
                  const OmText(
                    'Check the email spelling, or use "Forgot password?" — after several failed '
                    'tries Firebase may temporarily block sign-in.',
                    variant: OmTextVariant.caption,
                  ),
                ],
                const SizedBox(height: OmSpacing.lg),
                OmButton(
                  label: 'Sign in',
                  expanded: true,
                  loading: controller.busy.value,
                  busyLabel: 'Signing in…',
                  onPressed: controller.submit,
                ),
                const SizedBox(height: OmSpacing.sm),
                OmText(
                  controller.returnUrl.isEmpty
                      ? 'You will land on your account after signing in.'
                      : 'After signing in you will be taken back to ${controller.returnUrl}.',
                  variant: OmTextVariant.caption,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
