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

/// `/reset-password`.
///
/// With an `oobCode` in the URL this is a set-new-password form; the code is handed to Firebase and
/// the new password is written there, not here. Without one, the screen explains the emailed link
/// and can request a fresh one.
final class ResetPasswordView extends GetView<ResetPasswordController> {
  const ResetPasswordView({super.key});

  Future<void> _sendAnother(BuildContext context) async {
    final email = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset email address'),
        content: OmTextField(
          label: 'Email on your account',
          controller: email,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.alternate_email,
          validator: OmValidators.email,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop<String>(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop<String>(dialogContext, email.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    email.dispose();
    if (value == null || value.isEmpty) return;
    await controller.sendAnotherEmail(value);
    if (controller.failure.value == null) {
      Get.snackbar(
        'Reset email requested',
        'If that address has an account, a new link is on its way.',
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.hasOobCode) return _noCode(context);
    return Obx(() {
      if (controller.done.value) return _done();
      return _form();
    });
  }

  Widget _noCode(BuildContext context) {
    return AuthShell(
      eyebrow: 'Account access',
      title: 'Finish your password reset',
      intro: 'Open the email we sent and tap "Reset password". That link either completes the '
          'reset itself or brings you back here with the code needed to do it.',
      footer: <Widget>[
        OmButton(
          label: 'Go to sign in',
          variant: OmButtonVariant.outline,
          expanded: true,
          size: OmButtonSize.small,
          onPressed: controller.goLogin,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const OmSectionHeader(
            title: 'Need a new link?',
            subtitle: 'Reset links are single-use and are never stored in this app.',
          ),
          const SizedBox(height: OmSpacing.md),
          Obx(
            () => OmButton(
              label: 'Send a fresh reset email',
              expanded: true,
              loading: controller.busy.value,
              busyLabel: 'Sending…',
              onPressed: () => _sendAnother(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    final failure = controller.failure.value;
    return AuthShell(
      eyebrow: 'Account access',
      title: 'Choose a new password',
      intro: 'This link is good for one reset. The new password is written by Firebase, '
          'so sign-in stays exactly as it was before.',
      failure: failure,
      footer: <Widget>[
        OmButton(
          label: 'Back to sign in',
          variant: OmButtonVariant.ghost,
          expanded: true,
          size: OmButtonSize.small,
          onPressed: controller.goLogin,
        ),
      ],
      child: Form(
        key: controller.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmTextField(
              label: 'New password',
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
              label: 'Confirm new password',
              controller: controller.confirm,
              obscure: !controller.showPassword.value,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.lock_outline,
              validator: controller.validateConfirm,
              onSubmitted: (_) => controller.submit(),
              required: true,
            ),
            if (failure != null) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              const OmText(
                'If it says the link is invalid or already used, the reset already happened or the '
                'code expired — request a fresh one from the sign-in page.',
                variant: OmTextVariant.caption,
                overflow: TextOverflow.visible,
              ),
            ],
            const SizedBox(height: OmSpacing.lg),
            OmButton(
              label: 'Set new password',
              expanded: true,
              loading: controller.busy.value,
              busyLabel: 'Saving…',
              onPressed: controller.submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _done() {
    return AuthShell(
      eyebrow: 'Account access',
      title: 'Password updated',
      intro: 'Firebase accepted the link and saved the new password. Sign in with it now — this '
          'link cannot be used again.',
      footer: <Widget>[
        OmButton(
          label: 'Go to sign in',
          expanded: true,
          onPressed: controller.goLogin,
        ),
      ],
      child: const OmText(
        'Your other devices stay signed in until they refresh; the change applies the next time '
        'each one reads the session.',
        variant: OmTextVariant.muted,
        overflow: TextOverflow.visible,
      ),
    );
  }
}
