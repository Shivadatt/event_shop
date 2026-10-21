import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_theme.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/repositories/auth_repository.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// One entry in the admin navigation. `base` is the route prefix used to work out which item is
/// current, so `/admin/products/abc123` still highlights "Products".
final class AdminNavItem {
  const AdminNavItem({
    required this.base,
    required this.label,
    required this.icon,
    this.pricingOnly = false,
    this.costOnly = false,
  });

  final String base;
  final String label;
  final IconData icon;

  /// Item is *listed* for staff but the target route also carries `PricingAdminGuard`, and the
  /// notice here says so. Hiding a route is never a permission: the guard and the server decide.
  final bool pricingOnly;
  final bool costOnly;
}

abstract final class AdminNav {
  static const List<AdminNavItem> items = <AdminNavItem>[
    AdminNavItem(base: OmRoutes.admin, label: 'Dashboard', icon: Icons.dashboard_outlined),
    AdminNavItem(
        base: OmRoutes.adminProducts, label: 'Products', icon: Icons.inventory_2_outlined),
    AdminNavItem(
        base: OmRoutes.adminPricing,
        label: 'Pricing',
        icon: Icons.local_offer_outlined,
        pricingOnly: true),
    AdminNavItem(
        base: OmRoutes.adminCategories, label: 'Categories', icon: Icons.category_outlined),
    AdminNavItem(
        base: OmRoutes.adminInventory, label: 'Inventory', icon: Icons.warehouse_outlined),
    AdminNavItem(base: OmRoutes.adminOrders, label: 'Orders', icon: Icons.receipt_long_outlined),
    AdminNavItem(base: OmRoutes.adminCustomers, label: 'Customers', icon: Icons.people_outlined),
    AdminNavItem(
        base: OmRoutes.adminWholesale, label: 'Wholesale', icon: Icons.groups_outlined),
    AdminNavItem(
        base: OmRoutes.adminReviews, label: 'Reviews', icon: Icons.star_border_outlined),
    AdminNavItem(
        base: OmRoutes.adminCoupons,
        label: 'Coupons',
        icon: Icons.confirmation_number_outlined,
        pricingOnly: true),
    AdminNavItem(base: OmRoutes.adminMedia, label: 'Media', icon: Icons.image_outlined),
    AdminNavItem(base: OmRoutes.adminReports, label: 'Reports', icon: Icons.insights_outlined),
    AdminNavItem(
        base: OmRoutes.adminSettings, label: 'Settings', icon: Icons.settings_outlined),
    AdminNavItem(base: OmRoutes.adminAudit, label: 'Audit log', icon: Icons.history_outlined),
  ];

  static AdminNavItem? currentFor(String path) {
    AdminNavItem? best;
    for (final item in items) {
      if (path == item.base || path.startsWith('${item.base}/')) {
        if (best == null || item.base.length > best.base.length) best = item;
      }
    }
    return best;
  }
}

/// The admin frame: light theme, side rail on wide screens, drawer on compact ones, session chip
/// and sign-out.
///
/// `OmTheme.light` is applied here rather than inherited from the storefront because the brand's
/// gold-on-black surface destroys the contrast a dense table needs. Wrapping the shell means every
/// admin screen gets it, including dialogs and snackbars opened from inside it.
final class AdminScaffold extends StatefulWidget {
  const AdminScaffold({
    super.key,
    required this.child,
    this.title = 'Admin',
    this.actions = const <Widget>[],
  });

  final Widget child;
  final String title;
  final List<Widget> actions;

  @override
  State<AdminScaffold> createState() => _AdminScaffoldState();
}

class _AdminScaffoldState extends State<AdminScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Seed from the route actually on screen so a pasted deep link highlights correctly; updated on
  /// tap so the rail follows navigation without a route observer.
  late String _path = Get.currentRoute;

  void _open(String route) {
    setState(() => _path = route);
    if (Navigator.of(context).canPop() && !OmRoutes.isAdmin(Get.currentRoute)) {
      Get.toNamed<dynamic>(route);
    } else {
      Get.offNamed<dynamic>(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionStore>();
    final item = AdminNav.currentFor(_path);
    final heading = item?.label ?? widget.title;
    final isWide = context.isWideLayout;

    return Theme(
      data: OmTheme.light,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Row(
            children: <Widget>[
              if (!isWide) ...<Widget>[
                IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Open admin navigation',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(width: OmSpacing.xs),
              ],
              Flexible(child: Text(heading, overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: <Widget>[
            ...widget.actions,
            _SessionChip(session: session),
            const SizedBox(width: OmSpacing.sm),
          ],
        ),
        drawer: isWide ? null : _NavDrawer(path: _path, onSelect: _open),
        body: SafeArea(
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _NavRail(path: _path, onSelect: _open, session: session),
                    Expanded(
                      child: _BodyScroll(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const _BackendStatusBanner(),
                            widget.child,
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : _BodyScroll(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _BackendStatusBanner(),
                      widget.child,
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _BodyScroll extends StatelessWidget {
  const _BodyScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: OmSpacing.lg),
          // Horizontal is never scrollable at the page level: a wide table scrolls inside its own
          // card, so the app bar, rail and page column stay put.
          child: child,
        ),
      );
}

/// Sign-out and identity live in the app bar so the operator always knows which role is acting —
/// the same role the server re-checks on every write.
class _SessionChip extends StatelessWidget {
  const _SessionChip({required this.session});

  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = session.profile;
      final raw = current == null
          ? ''
          : (current.displayName.isEmpty ? current.email : current.displayName);
      final label = raw.isEmpty ? 'Signed out' : raw;
      final initial = label.trim().isEmpty
          ? '?'
          : label.trim().substring(0, 1).toUpperCase();
      final roleCode = (current?.role ?? UserRole.guest).code.toUpperCase();

      return Semantics(
        label: 'Signed in as $label, role $roleCode',
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OmSpacing.sm,
            vertical: OmSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircleAvatar(
                radius: 14,
                backgroundColor: OmColors.goldSoft,
                child: Text(
                  initial,
                  style: context.omText.caption.copyWith(
                    color: OmColors.onGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(label, overflow: TextOverflow.ellipsis, style: context.omText.caption),
                    Text(roleCode, style: context.omText.label),
                  ],
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              OmIconButton(
                icon: Icons.logout,
                tooltip: 'Sign out of admin',
                size: 36,
                onPressed: () => _signOut(context),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await omConfirmAdminAction(
      context: context,
      title: 'Sign out of admin',
      message: 'The storefront cart is kept. You will need to sign in again to reach '
          'these screens.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    try {
      await Get.find<AuthRepository>().signOut();
    } on OmFailure {
      // Token removal already happened locally in the implementation; the honest response is to
      // leave the admin area either way rather than to keep rendering privileged surfaces.
    }
    session.clear();
    await Get.offAllNamed<dynamic>(OmRoutes.home);
  }
}

/// States an unconfigured backend on screen. An operator reading "0 orders" from a store that is
/// not connected would draw exactly the wrong conclusion, so the missing half is named.
class _BackendStatusBanner extends StatelessWidget {
  const _BackendStatusBanner();

  @override
  Widget build(BuildContext context) {
    final report = AppBootstrap.report;
    if (report.isComplete) return const SizedBox.shrink();

    final parts = <String>[
      if (!report.firebaseReady) 'Firestore/Auth',
      if (!report.supabaseReady) 'Supabase media',
    ];
    final detail = report.failure ??
        (report.missing.isEmpty
            ? ''
            : ' Missing configuration: ${report.missing.join(', ')}.');

    // Which half is missing decides the claim. Firestore down means nothing below can be trusted.
    // Only Supabase down means the images are missing and every number on the page is still a real
    // read — saying "every list is empty or failing" there would tell an operator their stock
    // counts were junk when they were not.
    final bool dataDown = !report.firebaseReady;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmSpacing.md,
        OmSpacing.md,
        OmSpacing.md,
        0,
      ),
      child: OmAdminNotice(
        title: dataDown ? 'Backend not connected' : 'Media backend not connected',
        tone: dataDown ? OmTone.danger : OmTone.warning,
        icon: Icons.cloud_off,
        message: dataDown
            ? 'Admin is running against ${parts.isEmpty ? 'no backend' : parts.join(' and ')} '
                'that is configured.$detail Every list below is therefore empty or failing — this is '
                'not a store with no data.'
            : 'Product and category images cannot be served: Supabase media is not configured.$detail '
                'Order, stock, pricing and customer reads still come from Firestore and are shown '
                'normally.',
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.path, required this.onSelect, required this.session});

  final String path;
  final ValueChanged<String> onSelect;
  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    final extended = context.isDesktop;
    final width = extended ? 244.0 : 88.0;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: OmSpacing.md),
          OmText(
            extended ? 'OM Events admin' : 'ADMIN',
            variant: OmTextVariant.label,
            maxLines: 1,
          ).pad(extended),
          const SizedBox(height: OmSpacing.md),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: extended ? OmSpacing.sm : OmSpacing.xs),
              itemCount: AdminNav.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: OmSpacing.xs),
              itemBuilder: (context, index) {
                final item = AdminNav.items[index];
                return _NavTile(
                  item: item,
                  selected: item.base == path || path.startsWith('${item.base}/'),
                  extended: extended,
                  locked: _isLocked(item, session),
                  onTap: () => onSelect(item.base),
                );
              },
            ),
          ),
          const SizedBox(height: OmSpacing.md),
        ],
      ),
    );
  }
}

bool _isLocked(AdminNavItem item, SessionStore session) {
  if (item.pricingOnly && !session.canEditPricing) return true;
  if (item.costOnly && !session.canSeeCostPrice) return true;
  return false;
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.extended,
    required this.locked,
    required this.onTap,
  });

  final AdminNavItem item;
  final bool selected;
  final bool extended;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final tile = InkWell(
      onTap: onTap,
      borderRadius: OmRadius.smAll,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? OmColors.goldSoft.withValues(alpha: 0.45) : Colors.transparent,
          borderRadius: OmRadius.smAll,
          border: Border.all(
            color: selected ? OmColors.gold : Colors.transparent,
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: extended ? OmSpacing.md : OmSpacing.xs,
          vertical: OmSpacing.sm,
        ),
        child: extended
            ? Row(
                children: <Widget>[
                  Icon(
                    item.icon,
                    size: 18,
                    color: selected ? OmColors.onGold : styles.muted.color,
                  ),
                  const SizedBox(width: OmSpacing.md),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodyStrong.copyWith(
                        color: selected ? OmColors.onGold : null,
                      ),
                    ),
                  ),
                  if (locked)
                    const Icon(Icons.lock_outline, size: 14, color: OmColors.warning),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    item.icon,
                    size: 20,
                    color: selected ? OmColors.onGold : styles.muted.color,
                  ),
                  if (locked) ...<Widget>[
                    const SizedBox(height: 2),
                    const Icon(Icons.lock_outline, size: 11, color: OmColors.warning),
                  ],
                ],
              ),
      ),
    );
    return Tooltip(
      message: locked ? '${item.label} — needs admin or owner role' : item.label,
      child: Semantics(selected: selected, button: true, label: item.label, child: tile),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.path, required this.onSelect});

  final String path;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionStore>();
    return Drawer(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(OmSpacing.md),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: OmText('OM Events admin', variant: OmTextVariant.h3),
                  ),
                  OmIconButton(
                    icon: Icons.close,
                    tooltip: 'Close navigation',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OmText(
                      session.profile?.email ?? 'No session',
                      variant: OmTextVariant.caption,
                    ),
                  ),
                  roleBadge(session.role),
                ],
              ),
            ),
            const OmDivider(space: OmSpacing.md),
            Expanded(
              child: ListView.builder(
                itemCount: AdminNav.items.length,
                itemBuilder: (context, index) {
                  final item = AdminNav.items[index];
                  final selected = item.base == path || path.startsWith('${item.base}/');
                  return ListTile(
                    selected: selected,
                    leading: Icon(item.icon),
                    trailing: _isLocked(item, session)
                        ? const Icon(Icons.lock_outline, size: 16, color: OmColors.warning)
                        : null,
                    title: Text(item.label),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelect(item.base);
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(OmSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: OmButton(
                  label: 'Back to storefront',
                  variant: OmButtonVariant.secondary,
                  expanded: true,
                  icon: Icons.storefront_outlined,
                  onPressed: () {
                    Navigator.of(context).pop();
                    Get.offAllNamed<dynamic>(OmRoutes.home);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on Widget {
  Widget pad(bool extended) => Padding(
        padding: EdgeInsets.symmetric(horizontal: extended ? OmSpacing.md : OmSpacing.xs),
        child: this,
      );
}
