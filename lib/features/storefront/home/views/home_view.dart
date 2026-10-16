import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/storefront/common/categories_store.dart';
import 'package:om_events/features/storefront/common/external_links.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/common/store_product_card.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/home/home_controller.dart';

final class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsStore>();
    return StoreScaffold(
      title: 'Home',
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: OmSpacing.md),
            _HeroSection(settings: settings, controller: controller),
            const SizedBox(height: OmSpacing.xl),
            const _CategoryRail(),
            const SizedBox(height: OmSpacing.xl),
            _ShelfSection(
              eyebrow: 'Ordered again and again',
              title: 'Best sellers',
              emptyHint: 'Best sellers appear once the store has sales history.',
              items: controller.bestSellers,
              loading: controller.loading,
              failure: controller.failure,
              onRetry: controller.retry,
            ),
            const SizedBox(height: OmSpacing.xl),
            _ShelfSection(
              eyebrow: 'Fresh stock',
              title: 'new arrivals',
              emptyHint: 'New products will show here as they are added.',
              items: controller.newArrivals,
              loading: controller.loading,
              failure: controller.failure,
              onRetry: controller.retry,
            ),
            const SizedBox(height: OmSpacing.xl),
            const _WholesalePitch(),
            const SizedBox(height: OmSpacing.xl),
            const _TrustStrip(),
            const SizedBox(height: OmSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.settings, required this.controller});

  final SettingsStore settings;
  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Obx(() {
      final value = settings.settings.value;
      final tagline = (value?.tagline ?? '').isNotEmpty
          ? value!.tagline
          : StoreSettings.fallback.tagline;
      final banner = (value != null && value.banners.isNotEmpty)
          ? value.banners.first
          : null;
      final whatsapp = value?.whatsappLink ?? '';

      return Container(
        padding: EdgeInsets.all(context.isMobile ? OmSpacing.lg : OmSpacing.xxl),
        decoration: BoxDecoration(
          gradient: OmColors.heroGlow,
          borderRadius: OmRadius.lgAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(tagline.toUpperCase(), style: styles.label),
                  const SizedBox(height: OmSpacing.sm),
                  OmText(
                    'Decor, balloons and party supplies at wholesale prices.',
                    variant: OmTextVariant.display,
                    color: OmColors.textOnDark,
                    overflow: TextOverflow.visible,
                    maxLines: 4,
                  ),
                  const SizedBox(height: OmSpacing.md),
                  const OmGoldRule(),
                  const SizedBox(height: OmSpacing.lg),
                  Wrap(
                    spacing: OmSpacing.md,
                    runSpacing: OmSpacing.sm,
                    children: <Widget>[
                      OmButton(
                        label: 'Browse the catalogue',
                        icon: Icons.storefront_outlined,
                        size: OmButtonSize.large,
                        onPressed: () {
                          final rails = controller.railCategories;
                          Get.toNamed<dynamic>(
                            rails.isEmpty
                                ? OmRoutes.search
                                : OmRoutes.forCategory(rails.first.pathSlug),
                          );
                        },
                      ),
                      OmButton(
                        label: 'Apply for wholesale pricing',
                        variant: OmButtonVariant.outline,
                        size: OmButtonSize.large,
                        onPressed: () => Get.toNamed<dynamic>(OmRoutes.wholesaleApply),
                      ),
                    ],
                  ),
                  if (whatsapp.isNotEmpty) ...<Widget>[
                    const SizedBox(height: OmSpacing.md),
                    OmButton(
                      label: 'Ask us on WhatsApp',
                      icon: Icons.chat,
                      variant: OmButtonVariant.ghost,
                      onPressed: () => OmExternalLink.open(
                        context,
                        OmExternalLink.whatsappChat(
                          whatsapp,
                          message: 'Hello! I would like to ask about party supplies.',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (context.isWideLayout && banner != null) ...<Widget>[
              const SizedBox(width: OmSpacing.xl),
              Expanded(
                flex: 2,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: OmMediaImage(ref: banner, useThumbnail: false),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail();

  @override
  Widget build(BuildContext context) {
    final store = Get.find<CategoriesStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OmSectionHeader(
          eyebrow: 'Shop by category',
          title: 'Everything for the event',
          action: 'Search all products',
          onActionTap: () => Get.toNamed<dynamic>(OmRoutes.search),
        ),
        const SizedBox(height: OmSpacing.md),
        Obx(() {
          if (store.loading.value && store.categories.isEmpty) {
            return const SizedBox(
              height: 120,
              child: OmLoading(message: 'Loading categories…'),
            );
          }
          final failure = store.failure.value;
          if (failure != null && store.categories.isEmpty) {
            return OmErrorState(failure: failure, onRetry: store.retry, compact: true);
          }
          if (store.topLevel.isEmpty) {
            return const OmEmptyState(
              title: 'No categories yet',
              message: 'The store team has not published category pages so far.',
              compact: true,
            );
          }
          return OmHorizontalScroller(
            height: 132,
            children: <Widget>[
              for (final category in store.topLevel)
                _CategoryTile(category: category),
            ],
          );
        }),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final width = context.isMobile ? 150.0 : 190.0;
    return SizedBox(
      width: width,
      child: OmCard(
        padding: EdgeInsets.zero,
        onTap: () => Get.toNamed<dynamic>(OmRoutes.forCategory(category.pathSlug)),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 64,
              height: 132,
              child: OmMediaImage(ref: category.images.isEmpty ? null : category.images.first),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(OmSpacing.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OmText(category.name, variant: OmTextVariant.bodyStrong, maxLines: 2),
                    if (category.productCount > 0) ...<Widget>[
                      const SizedBox(height: 2),
                      OmText('${category.productCount} items',
                          variant: OmTextVariant.caption),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfSection extends StatelessWidget {
  const _ShelfSection({
    required this.eyebrow,
    required this.title,
    required this.emptyHint,
    required this.items,
    required this.loading,
    required this.failure,
    required this.onRetry,
  });

  final String eyebrow;
  final String title;
  final String emptyHint;
  final RxList<Product> items;
  final RxBool loading;
  final Rxn<OmFailure> failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HomeController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OmSectionHeader(eyebrow: eyebrow, title: title),
        const SizedBox(height: OmSpacing.md),
        Obx(() {
          final list = items.toList(growable: false);
          if (loading.value && list.isEmpty) {
            return OmProductGrid(
              itemCount: context.omColumnCount,
              itemBuilder: (_, __) => const OmProductCardSkeleton(),
            );
          }
          final error = failure.value;
          if (error != null && list.isEmpty) {
            return OmErrorState(failure: error, onRetry: onRetry);
          }
          if (list.isEmpty) {
            return OmEmptyState(title: 'Nothing to show yet', message: emptyHint, compact: true);
          }
          return OmProductGrid(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final product = list[index];
              return StoreProductCard(
                product: product,
                inWishlist: controller.wished(product.id),
                onWishlistToggle: () => controller.toggleWishlist(product),
              );
            },
          );
        }),
      ],
    );
  }
}

class _WholesalePitch extends StatelessWidget {
  const _WholesalePitch();

  @override
  Widget build(BuildContext context) => OmCard(
        highlight: true,
        elevated: true,
        padding: EdgeInsets.all(context.isMobile ? OmSpacing.lg : OmSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('WHOLESALE PROGRAMME', style: context.omText.label),
            const SizedBox(height: OmSpacing.sm),
            OmText(
              'Event decorators, retailers and caterers: unlock quantity pricing, negotiated '
              'rates and the bulk-order sheet once your business details are approved.',
              variant: OmTextVariant.lead,
              maxLines: 3,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: OmSpacing.lg),
            OmButton(
              label: 'Apply for wholesale',
              onPressed: () => Get.toNamed<dynamic>(OmRoutes.wholesaleApply),
            ),
          ],
        ),
      );
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String, String)>[
      (Icons.local_shipping_outlined, 'Courier or store pickup',
          'Delivery zones and pickup hours shown at checkout.'),
      (Icons.verified_outlined, 'Server-confirmed totals',
          'Every order price is re-verified before payment.'),
      (Icons.support_agent_outlined, 'WhatsApp support',
          'Ask about stock, slabs or event bulk orders.'),
      (Icons.replay_outlined, 'Straightforward cancellation',
          'Cancel while the order is still in processing.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int start = 0; start < items.length; start += context.isMobile ? 1 : 2)
          Padding(
            padding: const EdgeInsets.only(bottom: OmSpacing.md),
            child: Row(
              children: <Widget>[
                for (int i = start;
                    i < start + (context.isMobile ? 1 : 2) && i < items.length;
                    i++)
                  Expanded(
                    child: _TrustItem(
                      icon: items[i].$1,
                      title: items[i].$2,
                      note: items[i].$3,
                    ),
                  ),
                if (context.isMobile) const Spacer(),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.title, required this.note});

  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 26, color: OmColors.gold),
          const SizedBox(width: OmSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                OmText(title, variant: OmTextVariant.bodyStrong),
                OmText(note, variant: OmTextVariant.caption),
              ],
            ),
          ),
        ],
      );
}
