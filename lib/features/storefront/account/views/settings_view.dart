import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/account/account_order_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';

/// `/account/settings`. Consent the store acts on, plus local housekeeping. Every write goes
/// through `AuthRepository.updateProfile`, so the server records it and the session mirror shows it.
final class AccountSettingsView extends GetView<AccountSettingsController> {
  const AccountSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'Settings',
      subtitle: 'What the store may send you, and how this device keeps your cart.',
      currentRoute: OmRoutes.accountSettings,
      body: Obx(() {
        final failure = controller.failure.value;
        final profile = controller.profile;
        if (profile == null) {
          return OmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                OmText('Sign in to change settings.', variant: OmTextVariant.h3),
                const SizedBox(height: OmSpacing.md),
                OmButton(
                  label: 'Sign in',
                  onPressed: () => Get.toNamed<dynamic>(OmRoutes.login),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmCard(
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const OmSectionHeader(
                    title: 'Order updates',
                    subtitle: 'Turn a channel off and the store stops using it for your order '
                        'alerts. Account notices still arrive.',
                  ),
                  const SizedBox(height: OmSpacing.sm),
                  OmSwitchRow(
                    label: 'Email',
                    value: controller.notifyEmail,
                    onChanged: (value) => controller.setNotify(email: value),
                    description: profile.email.isEmpty
                        ? 'No email on your account yet'
                        : 'Sent to ${profile.email}',
                  ),
                  OmSwitchRow(
                    label: 'WhatsApp',
                    value: controller.notifyWhatsapp,
                    onChanged: (value) => controller.setNotify(whatsapp: value),
                    description: profile.phone.isEmpty
                        ? 'Add a mobile number in My details first'
                        : 'Sent to ${profile.phone}',
                  ),
                  OmSwitchRow(
                    label: 'SMS',
                    value: controller.notifySms,
                    onChanged: (value) => controller.setNotify(sms: value),
                    description: 'Delivery OTP and dispatch alerts',
                  ),
                  if (controller.busy.value) ...<Widget>[
                    const SizedBox(height: OmSpacing.sm),
                    const OmLoading(message: 'Saving…'),
                  ],
                  if (controller.saved.value && failure == null)
                    OmText('Saved by the store.',
                        variant: OmTextVariant.caption, color: OmColors.success),
                  if (failure != null)
                    OmText(failure.message,
                        variant: OmTextVariant.caption, color: OmColors.danger),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            OmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const OmSectionHeader(
                    title: 'This device',
                    subtitle: 'Your cart lives in this browser until the order is placed. '
                        'Recently-viewed history is stored the same way.',
                  ),
                  const SizedBox(height: OmSpacing.sm),
                  OmInfoRow(
                    label: 'Cart',
                    value: controller.cartLineCount == 0
                        ? 'Empty'
                        : '${controller.cartLineCount} line(s) waiting',
                    selectable: false,
                    trailing: OmButton(
                      label: 'Open',
                      variant: OmButtonVariant.ghost,
                      size: OmButtonSize.small,
                      onPressed: () => Get.toNamed<dynamic>(OmRoutes.cart),
                    ),
                  ),
                  OmInfoRow(
                    label: 'Wishlist',
                    value: '${profile.wishlistProductIds.length} saved item(s)',
                    selectable: false,
                    trailing: OmButton(
                      label: 'Open',
                      variant: OmButtonVariant.ghost,
                      size: OmButtonSize.small,
                      onPressed: () => Get.toNamed<dynamic>(OmRoutes.accountWishlist),
                    ),
                  ),
                  const SizedBox(height: OmSpacing.md),
                  Wrap(
                    spacing: OmSpacing.sm,
                    runSpacing: OmSpacing.sm,
                    children: <Widget>[
                      OmButton(
                        label: 'Clear recently viewed',
                        variant: OmButtonVariant.secondary,
                        size: OmButtonSize.small,
                        loading: controller.busy.value,
                        onPressed: controller.clearRecentlyViewed,
                      ),
                      if (controller.clearedHistory.value)
                        OmText('History cleared.',
                            variant: OmTextVariant.caption, color: OmColors.success),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            Obx(() {
              final store = Get.isRegistered<SettingsStore>() ? Get.find<SettingsStore>() : null;
              final live = store?.isLive ?? false;
              final reason = store == null
                  ? 'No settings store is bound for this route.'
                  : store.failure.value?.message ?? 'Nothing has been bound yet.';
              return OmCard(
                borderColor: live ? null : OmColors.warning,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OmText('Store connection', variant: OmTextVariant.bodyStrong),
                    const SizedBox(height: OmSpacing.xs),
                    OmText(
                      live
                          ? 'Store settings are reading from the backend.'
                          : 'Store settings are not connected. $reason '
                              'This page will not invent defaults and call them live data.',
                      variant: OmTextVariant.caption,
                      overflow: TextOverflow.visible,
                    ),
                    if (!live && store != null)
                      Padding(
                        padding: const EdgeInsets.only(top: OmSpacing.sm),
                        child: OmButton(
                          label: 'Retry settings',
                          variant: OmButtonVariant.outline,
                          size: OmButtonSize.small,
                          onPressed: store.load,
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: OmSpacing.lg),
            OmCard(
              borderColor: OmColors.danger,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OmText('Sign out of this device', variant: OmTextVariant.bodyStrong),
                  const SizedBox(height: OmSpacing.xs),
                  OmText(
                    'Your cart stays in this browser until you sign out; the store keeps the rest '
                    'of your data.',
                    variant: OmTextVariant.caption,
                    overflow: TextOverflow.visible,
                  ),
                  const SizedBox(height: OmSpacing.md),
                  OmButton(
                    label: 'Sign out',
                    icon: Icons.logout,
                    variant: OmButtonVariant.danger,
                    onPressed: controller.signOut,
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
