import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/common/storefront_route_names.dart';

/// The chrome the eight account pages share: page title, a section that stays reachable on every
/// breakpoint, and the nav rail (compact screens get a wrapping chip row instead of a drawer
/// inside a drawer).
final class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.currentRoute,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final String? currentRoute;
  final List<Widget> actions;

  static const List<(String, String, IconData)> sections = <(String, String, IconData)>[
    (OmRoutes.account, 'Overview', Icons.dashboard_outlined),
    (StorefrontRouteNames.accountProfile, 'My details', Icons.person_outline),
    (OmRoutes.accountOrders, 'Orders', Icons.receipt_long_outlined),
    (OmRoutes.accountAddresses, 'Addresses', Icons.location_city_outlined),
    (OmRoutes.accountWishlist, 'Wishlist', Icons.favorite_border),
    (OmRoutes.accountNotifications, 'Notifications', Icons.notifications_none),
    (OmRoutes.accountSupport, 'Support', Icons.support_agent_outlined),
    (OmRoutes.accountSettings, 'Settings', Icons.tune),
  ];

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: OmSpacing.lg, bottom: OmSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OmSectionHeader(title: title, subtitle: subtitle),
            const SizedBox(height: OmSpacing.md),
            if (actions.isNotEmpty) ...<Widget>[
              Wrap(spacing: OmSpacing.sm, runSpacing: OmSpacing.sm, children: actions),
              const SizedBox(height: OmSpacing.md),
            ],
            OmAccountNav(current: currentRoute),
            const SizedBox(height: OmSpacing.lg),
            Obx(() {
              final profile = Get.find<SessionStore>().changes.value;
              if (profile == null) return const SizedBox.shrink();
              if (!profile.isBlocked) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.only(bottom: OmSpacing.md),
                child: OmCard(
                  borderColor: OmColors.danger,
                  child: OmText(
                    'This account is on hold. You can still read past orders; placing new ones or '
                    'using wholesale tools stays closed until the store team reviews it.',
                    variant: OmTextVariant.caption,
                    overflow: TextOverflow.visible,
                  ),
                ),
              );
            }),
            body,
          ],
        ),
      ),
    );
  }
}

/// Navigation across the account area, one row of pills that rewraps instead of scrolling
/// sideways, on every breakpoint.
final class OmAccountNav extends StatelessWidget {
  const OmAccountNav({super.key, this.current});

  final String? current;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: OmSpacing.sm,
      runSpacing: OmSpacing.sm,
      children: <Widget>[
        for (final (route, label, icon) in AccountPage.sections)
          OmButton(
            label: label,
            icon: icon,
            size: OmButtonSize.small,
            variant: current == route ? OmButtonVariant.primary : OmButtonVariant.secondary,
            onPressed: () => Get.offNamed<dynamic>(route),
          ),
        OmButton(
          label: 'Wholesale',
          icon: Icons.local_shipping_outlined,
          size: OmButtonSize.small,
          variant: OmButtonVariant.secondary,
          onPressed: () => Get.toNamed<dynamic>(OmRoutes.wholesaleApply),
        ),
      ],
    );
  }
}

/// A labelled key/value line used by the overview, order and quotation pages.
final class OmInfoRow extends StatelessWidget {
  const OmInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.selectable = true,
    this.trailing,
  });

  final String label;
  final String value;
  final bool selectable;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: context.isCompactLayout ? 112 : 168,
              child: Text(label.toUpperCase(), style: context.omText.label),
            ),
            Expanded(
              child: selectable
                  ? SelectableText(value, style: context.omText.body)
                  : Text(value, style: context.omText.body),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: OmSpacing.sm),
              trailing!,
            ],
          ],
        ),
      );
}

/// Wholesale status pill for the overview and the apply page — reads the session mirror only, so
/// a client can never paint itself approved.
final class WholesaleStatusBadge extends StatelessWidget {
  const WholesaleStatusBadge({super.key, required this.status});

  final WholesaleStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      WholesaleStatus.approved => ('Wholesale approved', OmTone.success),
      WholesaleStatus.pending => ('Wholesale pending', OmTone.warning),
      WholesaleStatus.rejected => ('Wholesale declined', OmTone.danger),
      WholesaleStatus.none => ('Retail account', OmTone.neutral),
    };
    return OmBadge(label: label, tone: tone, icon: Icons.local_shipping_outlined, dense: true);
  }
}
