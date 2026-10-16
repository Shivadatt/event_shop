import 'dart:async';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';

/// Shared plumbing for the four auth screens. Each screen still owns its own controller — this
/// mixin only keeps the busy flag, the presentable failure and the `?return=` handshake
/// identical across them, so a bounced visitor always lands back where the guard found them.
mixin AuthFormMixin on GetxController {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final RxBool busy = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  AuthRepository get auth => Get.find<AuthRepository>();
  SessionStore get session => Get.find<SessionStore>();

  /// `AuthGuard` appends `?return=` when it bounces a visitor here and `AdminGuard` adds
  /// `&from=admin`. Only an in-app path is accepted: an absolute URL straight out of a query
  /// string would turn the sign-in page into an open redirect.
  String get returnUrl {
    final raw = Get.parameters[OmRouteArgs.returnUrl] ?? '';
    if (!raw.startsWith('/') || raw.startsWith('//')) return '';
    return raw;
  }

  bool get cameFromAdmin => Get.parameters[OmRouteArgs.source] == 'admin';

  String get landingRoute {
    if (returnUrl.isNotEmpty) return returnUrl;
    if (cameFromAdmin) return OmRoutes.admin;
    return OmRoutes.account;
  }

  /// `?reason=blocked` is what `AuthGuard` leaves on `/account` for a blocked profile; the sign-in
  /// form has to say so instead of silently looping the visitor back into the same guard.
  bool get isBlockedNotice => Get.parameters['reason'] == 'blocked';

  Future<void> run(Future<void> Function() action) async {
    if (busy.value) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    busy.value = true;
    failure.value = null;
    await safeCall<void>(action, onFailure: (value) => failure.value = value);
    busy.value = false;
  }

  void clearFailure() => failure.value = null;

  /// A profile the guard has blocked can sign in but can do nothing; say it plainly rather than
  /// navigating into a page that will bounce straight back here.
  String? get blockedNotice {
    if (!session.isBlocked) return null;
    return 'This account is on hold. Sign-in works, but orders and wholesale tools stay '
        'closed until the store team reviews it.';
  }
}

/// `/login`.
final class LoginController extends GetxController with AuthFormMixin {
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();

  final RxBool showPassword = false.obs;

  @override
  void onClose() {
    email.dispose();
    password.dispose();
    super.onClose();
  }

  Future<void> submit() async {
    await run(() async {
      await auth.signIn(email: email.text, password: password.text);
      // The session mirror is written by the auth implementation; this screen only reads it,
      // because a client may not decide who is signed in.
      if (session.isBlocked) {
        failure.value = const PermissionFailure(
          'This account is on hold. The store team has to release it before you can order.',
        );
        return;
      }
      unawaited(Get.offNamed<void>(landingRoute));
    });
  }

  void goRegister() => Get.toNamed<void>(
        OmRoutes.register,
        parameters: <String, String>{
          if (returnUrl.isNotEmpty) OmRouteArgs.returnUrl: returnUrl,
          if (cameFromAdmin) OmRouteArgs.source: 'admin',
        },
      );

  void goForgotPassword() => Get.toNamed<void>(OmRoutes.forgotPassword);
}

/// `/register`.
final class RegisterController extends GetxController with AuthFormMixin {
  final TextEditingController displayName = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController confirm = TextEditingController();

  final RxBool showPassword = false.obs;
  final RxBool acceptMarketing = false.obs;

  @override
  void onClose() {
    displayName.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
    confirm.dispose();
    super.onClose();
  }

  /// Matching is a form rule, not a security control: the server validates the password itself.
  String? validateConfirm(String? value) {
    if (value != password.text) return 'The two passwords do not match';
    return null;
  }

  Future<void> submit() async {
    await run(() async {
      await auth.signUp(
        email: email.text,
        password: password.text,
        displayName: displayName.text,
        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
      );
      unawaited(Get.offNamed<void>(landingRoute));
    });
  }

  void goLogin() => Get.toNamed<void>(
        OmRoutes.login,
        parameters: <String, String>{
          if (returnUrl.isNotEmpty) OmRouteArgs.returnUrl: returnUrl,
          if (cameFromAdmin) OmRouteArgs.source: 'admin',
        },
      );
}

/// `/forgot-password`.
final class ForgotPasswordController extends GetxController with AuthFormMixin {
  final TextEditingController email = TextEditingController();

  final RxBool sent = false.obs;

  @override
  void onClose() {
    email.dispose();
    super.onClose();
  }

  Future<void> submit() async {
    await run(() async {
      await auth.sendPasswordReset(email.text);
      sent.value = true;
    });
  }

  void goLogin() => Get.back<void>();
}

/// `/reset-password`.
///
/// Firebase delivers a one-tap link that completes the reset itself. Finishing it *inside* the
/// app needs `AuthRepository.confirmPasswordReset`, which the repository interface does not
/// expose (see `lib/data/repositories/auth_repository.dart:23`), so this screen never pretends to
/// submit a new password: it explains the emailed link and offers to send another one.
final class ResetPasswordController extends GetxController with AuthFormMixin {
  /// Presence only — the token value is never read, held in a controller field or passed on.
  bool get hasOobCode =>
      (Get.parameters['oobCode'] ?? '').isNotEmpty ||
      Uri.parse(Get.fullPath ?? Get.currentRoute).queryParameters.containsKey('oobCode');

  OmFailure get unsupported => const NotImplementedFailure(
        'This build cannot complete a reset link in the page. Use the button in the email '
        'Firebase sent you, or send a fresh reset email below.',
      );

  Future<void> sendAnotherEmail(String email) async {
    if (busy.value) return;
    busy.value = true;
    failure.value = null;
    await safeCall<void>(
      () async => auth.sendPasswordReset(email),
      onFailure: (value) => failure.value = value,
    );
    busy.value = false;
  }

  void goLogin() => Get.offNamed<void>(OmRoutes.login);
}
