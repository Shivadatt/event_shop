import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/account/account_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';

/// `/account` — the signed-in hub.
final class AccountHomeView extends GetView<AccountHomeController> {
  const AccountHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'My account',
      subtitle: 'Signed in as ${controller.firstName}. Everything below is your own data; the '
          'store’s records stay authoritative.',
      currentRoute: OmRoutes.account,
      actions: <Widget>[
        OmButton(
          label: 'Sign out',
          icon: Icons.logout,
          variant: OmButtonVariant.ghost,
          size: OmButtonSize.small,
          onPressed: controller.signOut,
        ),
      ],
      body: Obx(() {
        final profile = controller.session.changes.value;
        final cart = Get.find<CartStore>();
        if (profile == null) {
          return OmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const OmText('Your session could not be read.', variant: OmTextVariant.h3),
                const SizedBox(height: OmSpacing.sm),
                const OmText(
                  'The sign-in state comes from the store’s auth service, so this page will not '
                  'guess it. Sign in again to continue.',
                  variant: OmTextVariant.muted,
                  overflow: TextOverflow.visible,
                ),
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
                  Row(
                    children: <Widget>[
                      Expanded(child: OmText(profile.displayName.isEmpty
                          ? profile.email
                          : profile.displayName, variant: OmTextVariant.h3)),
                      WholesaleStatusBadge(status: profile.wholesaleStatus),
                    ],
                  ),
                  const SizedBox(height: OmSpacing.sm),
                  OmInfoRow(label: 'Email', value: profile.email.isEmpty ? '—' : profile.email),
                  OmInfoRow(label: 'Mobile', value: profile.phone.isEmpty ? 'Not saved' : profile.phone),
                  OmInfoRow(
                    label: 'GST number',
                    value: profile.gstNumber.isEmpty ? 'Not saved' : profile.gstNumber,
                  ),
                  OmInfoRow(
                    label: 'Company',
                    value: profile.companyName.isEmpty ? 'Not saved' : profile.companyName,
                  ),
                  OmInfoRow(
                    label: 'Account since',
                    value: OmDates.date(profile.createdAt),
                    selectable: false,
                  ),
                  if (profile.lastOrderAt != null)
                    OmInfoRow(
                      label: 'Last order',
                      value: OmDates.date(profile.lastOrderAt),
                      selectable: false,
                    ),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            const OmSectionHeader(title: 'Where to next'),
            const SizedBox(height: OmSpacing.sm),
            _QuickLinks(
              links: <(String, String, String)>[
                (OmRoutes.accountOrders, 'Orders & tracking', 'Place, follow and reorder'),
                (OmRoutes.accountAddresses, 'Delivery addresses', 'Used to prefill checkout'),
                (
                  OmRoutes.accountWishlist,
                  'Wishlist',
                  '${profile.wishlistProductIds.length} saved'
                ),
                (OmRoutes.accountNotifications, 'Notifications', 'Order and stock updates'),
                (OmRoutes.accountSupport, 'Support desk', 'Tickets and replies'),
                (OmRoutes.accountSettings, 'Settings', 'Consent and sign-out'),
              ],
            ),
            const SizedBox(height: OmSpacing.lg),
            OmCard(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OmText(
                      cart.lines.isEmpty
                          ? 'Cart right now: empty. Prices shown anywhere in this app are '
                              'estimates — the store confirms the payable total when the order '
                              'is created.'
                          : 'Cart right now: ${cart.lines.length} lines, ${cart.unitCount} units. '
                              'Prices shown anywhere in this app are estimates — the store '
                              'confirms the payable total when the order is created.',
                      variant: OmTextVariant.caption,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  const SizedBox(width: OmSpacing.sm),
                  OmButton(
                    label: 'Open cart',
                    variant: OmButtonVariant.secondary,
                    size: OmButtonSize.small,
                    onPressed: () => Get.toNamed<dynamic>(OmRoutes.cart),
                  ),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.lg),
            OmInfoRow(
              label: 'Account role',
              value: profile.role.code,
              selectable: false,
              trailing: profile.role.canManageStore
                  ? const OmBadge(label: 'Store staff', tone: OmTone.gold, dense: true)
                  : null,
            ),
            const OmText(
              'Your role is set by the store, never by this device. Staff accounts can open the '
              'admin panel from the header.',
              variant: OmTextVariant.caption,
              overflow: TextOverflow.visible,
            ),
            if (profile.role.canManageStore)
              Padding(
                padding: const EdgeInsets.only(top: OmSpacing.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OmButton(
                    label: 'Open admin panel',
                    icon: Icons.admin_panel_settings_outlined,
                    variant: OmButtonVariant.outline,
                    onPressed: () => Get.toNamed<dynamic>(OmRoutes.admin),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _QuickLinks extends StatelessWidget {
  const _QuickLinks({required this.links});

  final List<(String, String, String)> links;

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: links.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: context.omColumnCount > 2 ? 3 : 2,
          crossAxisSpacing: OmSpacing.md,
          mainAxisSpacing: OmSpacing.md,
          childAspectRatio: 2.1,
        ),
        itemBuilder: (context, index) {
          final (route, title, note) = links[index];
          return OmCard(
            onTap: () => Get.toNamed<dynamic>(route),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OmText(title, variant: OmTextVariant.bodyStrong),
                const SizedBox(height: OmSpacing.xs),
                OmText(note, variant: OmTextVariant.caption, maxLines: 2),
              ],
            ),
          );
        },
      );
}
