import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/categories_store.dart';
import 'package:om_events/features/storefront/common/external_links.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';

/// The chrome every customer page shares: brand bar with search / cart / account, a category
/// drawer, and the policy footer. Content pages never draw their own app bar so the cart badge
/// and navigation stay identical everywhere.
class StoreScaffold extends StatelessWidget {
  const StoreScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showFooter = true,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final bool showFooter;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final settings = Get.isRegistered<SettingsStore>()
        ? Get.find<SettingsStore>().value
        : StoreSettings.fallback;

    return Scaffold(
      appBar: StoreAppBar(title: title, settings: settings),
      drawer: const StoreDrawer(),
      floatingActionButton: floatingActionButton,
      body: Column(
        children: <Widget>[
          Expanded(
            child: OmContentWidth(child: body),
          ),
          if (showFooter) ...<Widget>[
            const OmDivider(space: OmSpacing.sm),
            const StoreFooter(),
          ],
        ],
      ),
    );
  }
}

class StoreAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StoreAppBar({super.key, required this.title, required this.settings});

  final String title;
  final StoreSettings settings;

  static const double _barHeight = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final cart = Get.isRegistered<CartStore>() ? Get.find<CartStore>() : null;
    final session = Get.isRegistered<SessionStore>()
        ? Get.find<SessionStore>()
        : SessionStore();

    return AppBar(
      toolbarHeight: _barHeight,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Open menu',
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Semantics(
        header: true,
        child: GestureDetector(
          onTap: () => Get.toNamed<dynamic>(OmRoutes.home),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                settings.shopName.isEmpty ? 'OM Events' : settings.shopName,
                style: styles.h3.copyWith(fontSize: context.isMobile ? 17 : 20),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!context.isMobile && settings.tagline.isNotEmpty)
                Text(settings.tagline, style: styles.label),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (context.isWideLayout)
          SizedBox(
            width: 260,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: OmSpacing.sm),
              child: OmTextField(
                label: 'Search products',
                hint: 'Search products…',
                prefixIcon: Icons.search,
                onSubmitted: (value) {
                  final query = value.trim();
                  Get.toNamed<dynamic>(
                    OmRoutes.search,
                    parameters: <String, String>{
                      if (query.isNotEmpty) OmRouteArgs.search: query,
                    },
                  );
                },
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Get.toNamed<dynamic>(OmRoutes.search),
          ),
        if (cart != null)
          Obx(
            () => IconButton(
              icon: Badge(
                isLabelVisible: cart.lines.isNotEmpty,
                label: Text('${cart.lines.length}'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              tooltip: 'Cart, ${cart.lines.length} items',
              onPressed: () => Get.toNamed<dynamic>(OmRoutes.cart),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined),
            tooltip: 'Cart',
            onPressed: () => Get.toNamed<dynamic>(OmRoutes.cart),
          ),
        IconButton(
          icon: Icon(
            session.isSignedIn ? Icons.account_circle_outlined : Icons.person_outline,
          ),
          tooltip: session.isSignedIn ? 'My account' : 'Sign in',
          onPressed: () => Get.toNamed<dynamic>(
            session.isSignedIn ? OmRoutes.account : OmRoutes.login,
          ),
        ),
        const SizedBox(width: OmSpacing.sm),
      ],
    );
  }
}

class StoreDrawer extends StatelessWidget {
  const StoreDrawer({super.key});

  /// GetX has no `closeOpenDrawer`; the Scaffold owns the drawer, so it is closed through
  /// [ScaffoldState.closeDrawer] before the route is pushed. Without this the drawer stays painted
  /// over the new page on wide layouts where it is pinned open.
  void _go(BuildContext context, String route) {
    Scaffold.maybeOf(context)?.closeDrawer();
    Get.toNamed<dynamic>(route);
  }

  @override
  Widget build(BuildContext context) {
    final store = Get.isRegistered<CategoriesStore>()
        ? Get.find<CategoriesStore>()
        : null;
    return NavigationDrawer(
      onDestinationSelected: (index) {
        const routes = <String>[
          OmRoutes.home,
          OmRoutes.search,
          OmRoutes.cart,
          OmRoutes.account,
          OmRoutes.wholesaleApply,
          OmRoutes.contact,
        ];
        if (index < routes.length) _go(context, routes[index]);
      },
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(OmSpacing.md),
          child: Text('Shop', style: context.omText.label),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.home_outlined),
          label: Text('Home'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.search),
          label: Text('Search'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.shopping_bag_outlined),
          label: Text('Cart'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.person_outline),
          label: Text('Account'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.local_shipping_outlined),
          label: Text('Wholesale'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.support_agent_outlined),
          label: Text('Contact'),
        ),
        if (store != null)
          Obx(() {
            if (store.loading.value && store.categories.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(OmSpacing.md),
                child: OmLoading(message: 'Loading categories…'),
              );
            }
            final failure = store.failure.value;
            if (failure != null && store.categories.isEmpty) {
              return OmErrorState(failure: failure, compact: true, onRetry: store.retry);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(OmSpacing.md),
                  child: Text('Categories', style: context.omText.label),
                ),
                for (final category in store.topLevel)
                  ListTile(
                    dense: true,
                    title: Text(category.name),
                    onTap: () => _go(context, OmRoutes.forCategory(category.pathSlug)),
                  ),
              ],
            );
          }),
      ],
    );
  }
}

/// Trust + policy strip. Doubles as the footer everywhere: contact, policies, WhatsApp and map
/// exits, all driven by `StoreSettings`.
class StoreFooter extends StatelessWidget {
  const StoreFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.isRegistered<SettingsStore>()
        ? Get.find<SettingsStore>().value
        : StoreSettings.fallback;
    final styles = context.omText;

    return OmContentWidth(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: OmSpacing.xl,
              runSpacing: OmSpacing.lg,
              children: <Widget>[
                const _FooterColumn(
                  title: 'Shop',
                  links: <(String, String)>[
                    ('Search', OmRoutes.search),
                    ('Cart', OmRoutes.cart),
                    ('Wholesale', OmRoutes.wholesaleApply),
                    ('My account', OmRoutes.account),
                  ],
                ),
                const _FooterColumn(
                  title: 'Help',
                  links: <(String, String)>[
                    ('FAQ', OmRoutes.faq),
                    ('Contact us', OmRoutes.contact),
                    ('About', OmRoutes.about),
                    ('Support desk', OmRoutes.accountSupport),
                  ],
                ),
                _FooterColumn(
                  title: 'Policies',
                  links: <(String, String)>[
                    ('Shipping', OmRoutes.forPolicy('shipping')),
                    ('Cancellations', OmRoutes.forPolicy('cancellation')),
                    ('Returns & refunds', OmRoutes.forPolicy('refund')),
                    ('Privacy', OmRoutes.forPolicy('privacy')),
                    ('Terms', OmRoutes.forPolicy('terms')),
                  ],
                ),
                if (settings.fullAddress.isNotEmpty ||
                    settings.phone.isNotEmpty ||
                    settings.whatsapp.isNotEmpty)
                  _FooterColumn(
                    title: 'Visit',
                    children: <Widget>[
                      if (settings.fullAddress.isNotEmpty)
                        SelectableText(settings.fullAddress, style: styles.muted),
                      if (settings.openingHours.isNotEmpty)
                        SelectableText(settings.openingHours, style: styles.caption),
                      Row(
                        children: <Widget>[
                          if (settings.whatsappLink.isNotEmpty)
                            OmButton(
                              label: 'WhatsApp',
                              icon: Icons.chat,
                              variant: OmButtonVariant.outline,
                              size: OmButtonSize.small,
                              onPressed: () => OmExternalLink.open(
                                context,
                                settings.whatsappLink,
                                label: 'WhatsApp chat',
                              ),
                            ),
                          if (settings.googleMapsUrl.isNotEmpty) ...<Widget>[
                            const SizedBox(width: OmSpacing.sm),
                            OmButton(
                              label: 'Map',
                              icon: Icons.location_on_outlined,
                              variant: OmButtonVariant.outline,
                              size: OmButtonSize.small,
                              onPressed: () => OmExternalLink.open(
                                context,
                                settings.googleMapsUrl,
                                label: 'Shop location',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: OmSpacing.lg),
            Text(
              '© ${settings.shopName} — wholesale & party supplies. Prices and availability are '
              'confirmed at checkout.',
              style: styles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({
    required this.title,
    this.links = const <(String, String)>[],
    this.children = const <Widget>[],
  });

  final String title;
  final List<(String, String)> links;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title.toUpperCase(), style: context.omText.label),
            const SizedBox(height: OmSpacing.sm),
            for (final (label, route) in links)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Get.toNamed<dynamic>(route),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(label, style: context.omText.body),
                ),
              ),
            ...children,
          ],
        ),
      );
}
