import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';

/// Chrome shared by the four editorial pages (about, contact, FAQ, policies).
///
/// Every word on these pages is store-authored, so when `SettingsStore` has not loaded the page
/// says so and offers a retry instead of falling back to tokenised brand copy that reads like fact.
final class StaticPage extends StatelessWidget {
  const StaticPage({
    super.key,
    required this.title,
    required this.currentRoute,
    required this.content,
    this.subtitle,
    this.showWhenUnlive = false,
  });

  final String title;
  final String? subtitle;
  final String currentRoute;

  /// Called inside the `Obx` that watches the settings read, so a late-arriving settings document
  /// repaints the page instead of leaving a snapshot taken before the load.
  final Widget Function(BuildContext context, StoreSettings? settings) content;

  /// Pages whose body is app-owned (the about page's "how buying here works" explainer) can keep
  /// showing it while the settings read has failed; policy and FAQ pages must not.
  final bool showWhenUnlive;

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmSectionHeader(title: title, subtitle: subtitle),
            const SizedBox(height: OmSpacing.lg),
            Obx(() {
              final store = Get.find<SettingsStore>();
              if (store.loading.value && !store.isLive) {
                return const OmLoading(message: 'Loading the store’s own words…');
              }
              if (!store.isLive && !showWhenUnlive) {
                return OmErrorState(
                  compact: true,
                  failure: store.failure.value ??
                      const ServerFailure(
                        'These store details have not been published yet.',
                      ),
                  onRetry: store.load,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!store.isLive && showWhenUnlive) ...<Widget>[
                    OmCard(
                      borderColor: OmColors.warning,
                      padding: const EdgeInsets.all(OmSpacing.sm),
                      child: Row(
                        children: <Widget>[
                          const Expanded(
                            child: OmText(
                              'Shop address and timings could not be loaded from the store '
                              'settings, so they are not shown below.',
                              variant: OmTextVariant.caption,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                          const SizedBox(width: OmSpacing.sm),
                          OmButton(
                            label: 'Retry',
                            size: OmButtonSize.small,
                            variant: OmButtonVariant.secondary,
                            onPressed: store.load,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: OmSpacing.md),
                  ],
                  content(context, store.settings.value),
                ],
              );
            }),
            const SizedBox(height: OmSpacing.xl),
            StaticPageLinks(current: currentRoute),
            const SizedBox(height: OmSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Cross-links between the editorial pages, so a buyer who landed on a deep link can still reach
/// the policy they actually wanted.
final class StaticPageLinks extends StatelessWidget {
  const StaticPageLinks({super.key, this.current});

  final String? current;

  static const List<(String, String)> _pages = <(String, String)>[
    (OmRoutes.about, 'About'),
    (OmRoutes.contact, 'Contact'),
    (OmRoutes.faq, 'FAQ'),
    (OmRoutes.forPolicy('shipping'), 'Shipping'),
    (OmRoutes.forPolicy('refund'), 'Returns'),
    (OmRoutes.forPolicy('privacy'), 'Privacy'),
    (OmRoutes.forPolicy('terms'), 'Terms'),
  ];

  @override
  Widget build(BuildContext context) => OmCard(
        padding: const EdgeInsets.all(OmSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OmText('MORE FROM THIS STORE'.toUpperCase(), style: context.omText.label),
            const SizedBox(height: OmSpacing.sm),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                for (final (route, label) in _pages)
                  OmButton(
                    label: label,
                    size: OmButtonSize.small,
                    variant: route == current ? OmButtonVariant.primary : OmButtonVariant.ghost,
                    onPressed: () => Get.toNamed<dynamic>(route),
                  ),
              ],
            ),
          ],
        ),
      );
}

/// A headed block of store-authored prose. New lines in the authored text become paragraphs, so
/// the store's own formatting survives without a rich-text renderer.
final class StaticProse extends StatelessWidget {
  const StaticProse({super.key, required this.text, this.title, this.emptyMessage});

  final String text;
  final String? title;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return OmEmptyState(
        compact: true,
        title: title ?? 'Not published yet',
        message: emptyMessage ??
            'The store has not written this page yet. Ask the support desk and they will answer '
                'in your own thread.',
        icon: Icons.description_outlined,
      );
    }
    final paragraphs = trimmed
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            OmText(title!, variant: OmTextVariant.h3),
            const SizedBox(height: OmSpacing.sm),
          ],
          for (final paragraph in paragraphs) ...<Widget>[
            OmText(
              paragraph,
              variant: OmTextVariant.body,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: OmSpacing.sm),
          ],
        ],
      ),
    );
  }
}
