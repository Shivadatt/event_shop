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
/// This build cannot complete a Firebase email action in the page — `AuthRepository` exposes no
/// `confirmPasswordReset`, so the controller reports that honestly instead of faking a submit. The
/// screen explains the emailed link and can request a fresh one; the `oobCode` is only checked for
/// presence, never read or stored.
final class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final TextEditingController _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send(ResetPasswordController controller) async {
    if (OmValidators.email(_email.text) != null) {
      Get.snackbar('Check the email', 'Enter the email address on your account first.');
      return;
    }
    await controller.sendAnotherEmail(_email.text);
    if (controller.failure.value == null) {
      Get.snackbar(
        'Reset email requested',
        'If that address has an account, a new link is on its way.',
        snackDuration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ResetPasswordController>();
    return AuthShell(
      eyebrow: 'Account access',
      title: 'Finish your password reset',
      intro: 'Open the email we sent and tap "Reset password". That button completes the reset in '
          'Firebase, where the new password is actually written.',
      notice: controller.hasOobCode
          ? 'This link carries a reset code. This build cannot apply it in the page, so use the '
              'button inside the email itself.'
          : null,
      failure: controller.hasOobCode ? controller.unsupported : null,
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
          OmTextField(
            label: 'Email on your account',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.alternate_email,
            helper: 'Only used to send a new reset email.',
            validator: OmValidators.email,
          ),
          const SizedBox(height: OmSpacing.md),
          Obx(
            () => OmButton(
              label: 'Send a fresh reset email',
              expanded: true,
              loading: controller.busy.value,
              busyLabel: 'Sending…',
              onPressed: () => _send(controller),
            ),
          ),
        ],
      ),
    );
  }
}
