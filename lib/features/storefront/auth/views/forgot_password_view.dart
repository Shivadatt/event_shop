import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/auth/auth_controller.dart';
import 'package:om_events/features/storefront/auth/widgets/auth_shell.dart';

/// `/forgot-password`. Firebase sends the reset mail; this screen never claims the mail reached a
/// specific address, because that would leak which emails have accounts.
final class ForgotPasswordView extends GetView<ForgotPasswordController> {
  const ForgotPasswordView({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'Account access',
      title: 'Reset your password',
      intro: 'Enter the email on your account and we will ask Firebase to send a reset link.',
      footer: <Widget>[
        OmButton(
          label: 'Back to sign in',
          variant: OmButtonVariant.outline,
          expanded: true,
          size: OmButtonSize.small,
          onPressed: controller.goLogin,
        ),
      ],
      child: Obx(() {
        if (controller.sent.value) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const OmCard(
                borderColor: OmColors.success,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.mark_email_read_outlined,
                        size: 20, color: OmColors.success),
                    SizedBox(width: OmSpacing.sm),
                    Expanded(
                      child: OmText(
                        'If that address has an account, a reset link is on its way. Check your '
                        'spam folder too — the link is single-use and expires after an hour.',
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: OmSpacing.md),
              OmButton(
                label: 'Send another link',
                variant: OmButtonVariant.secondary,
                onPressed: () => controller.sent.value = false,
              ),
            ],
          );
        }
        return Form(
          key: controller.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OmTextField(
                label: 'Email',
                controller: controller.email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.email],
                prefixIcon: Icons.alternate_email,
                validator: OmValidators.email,
                onSubmitted: (_) => controller.submit(),
                required: true,
              ),
              const SizedBox(height: OmSpacing.lg),
              OmButton(
                label: 'Email me a reset link',
                expanded: true,
                loading: controller.busy.value,
                busyLabel: 'Sending…',
                onPressed: controller.submit,
              ),
            ],
          ),
        );
      }),
    );
  }
}
