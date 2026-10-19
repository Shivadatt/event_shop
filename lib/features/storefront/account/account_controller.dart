import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';

/// `/account`. The hub a signed-in buyer lands on: identity the session mirror reports, plus the
/// links into the rest of the account area. Nothing here re-decides a role.
final class AccountHomeController extends GetxController {
  SessionStore get session => Get.find<SessionStore>();

  Future<void> signOut() async {
    final ok = await tryCall(() => Get.find<AuthRepository>().signOut());
    if (ok) {
      unawaited(Get.offAllNamed<dynamic>(OmRoutes.home));
    }
  }

  String get firstName {
    final profile = session.profile;
    final name = (profile?.displayName ?? '').trim();
    if (name.isNotEmpty) return name.split(' ').first;
    return profile?.email.isNotEmpty == true ? profile!.email.split('@').first : 'there';
  }

  bool get isApprovedWholesale =>
      session.profile?.wholesaleStatus == WholesaleStatus.approved;
}

/// `/account` profile edit. Fields mirror the profile document the server owns; the write goes
/// through `AuthRepository.updateProfile` and the session mirror updates from the auth stream.
final class ProfileController extends GetxController {
  final TextEditingController displayName = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController gstNumber = TextEditingController();
  final TextEditingController companyName = TextEditingController();

  final RxBool loading = false.obs;
  final RxBool busy = false.obs;
  final RxBool saved = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  UserProfile? get profile => Get.find<SessionStore>().profile;
  String get email => profile?.email ?? '';

  @override
  void onInit() {
    super.onInit();
    hydrate();
  }

  void hydrate() {
    final p = profile;
    displayName.text = p?.displayName ?? '';
    phone.text = p?.phone ?? '';
    gstNumber.text = p?.gstNumber ?? '';
    companyName.text = p?.companyName ?? '';
    saved.value = false;
  }

  @override
  void onClose() {
    displayName.dispose();
    phone.dispose();
    gstNumber.dispose();
    companyName.dispose();
    super.onClose();
  }

  Future<void> save() async {
    if (busy.value) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    busy.value = true;
    failure.value = null;
    final gst = gstNumber.text.trim();
    final ok = await tryCall(
      () => Get.find<AuthRepository>().updateProfile(
        displayName: displayName.text.trim(),
        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
        gstNumber: gst.isEmpty ? null : gst.toUpperCase(),
        companyName: companyName.text.trim().isEmpty ? null : companyName.text.trim(),
      ),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    saved.value = ok;
  }

  void discardChanges() {
    hydrate();
    failure.value = null;
  }
}
