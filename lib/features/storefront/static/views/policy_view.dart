import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/static/widgets/static_page.dart';

/// `/policy/:kind` — shipping, cancellation, refund, privacy and terms all live in the same
/// `store_settings` document, so one page serves them and the route decides which field to show.
final class PolicyView extends StatelessWidget {
  const PolicyView({super.key});

  static const Map<String, (String, String)> _kinds = <String, (String, String)>{
    'shipping': ('Shipping policy', 'How cartons travel, lead times and freight zones.'),
    'cancellation': ('Cancellation policy', 'When an order can still be cancelled and what happens '
        'to the money.'),
    'refund': ('Returns & refunds', 'What can be returned, in what condition, and how a refund is '
        'issued.'),
    'privacy': ('Privacy policy', 'What this store records about you and who sees it.'),
    'terms': ('Terms of sale', 'The contract between the store and a trade buyer.'),
  };

  @override
  Widget build(BuildContext context) {
    final kind = (Get.parameters['kind'] ?? '').trim().toLowerCase();
    final meta = _kinds[kind];
    final title = meta == null ? 'Policy' : meta.$1;

    return StaticPage(
      title: title,
      subtitle: meta?.$2,
      currentRoute: OmRoutes.forPolicy(kind),
      content: (context, settings) {
        if (settings == null) {
          return const OmLoading(message: 'Loading the published policy…');
        }
        if (meta == null) {
          return OmEmptyState(
            compact: true,
            title: 'No such policy page',
            message: 'This store publishes shipping, cancellation, returns, privacy and terms. '
                'Pick one of those or ask the support desk.',
            icon: Icons.description_outlined,
            actionLabel: 'All store pages',
            onAction: () => Get.toNamed<dynamic>(OmRoutes.about),
          );
        }
        return _PolicyBody(kind: kind, settings: settings);
      },
    );
  }
}

class _PolicyBody extends StatelessWidget {
  const _PolicyBody({required this.kind, required this.settings});

  final String kind;
  final StoreSettings settings;

  String get _text => switch (kind) {
        'shipping' => settings.shippingPolicy,
        'cancellation' => settings.cancellationPolicy,
        'refund' => settings.refundPolicy,
        'privacy' => settings.privacyPolicy,
        _ => settings.termsPolicy,
      };

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StaticProse(
          text: _text,
          title: PolicyView._kinds[kind]?.$1,
          emptyMessage: 'The store has not written this policy yet. Nothing here is invented to '
              'fill the gap — ask the support desk and they will answer in writing.',
        ),
        if (_text.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: OmSpacing.md),
          OmCard(
            padding: const EdgeInsets.all(OmSpacing.sm),
            child: Row(
              children: <Widget>[
                const Icon(Icons.verified_outlined, size: 18, color: OmColors.textMuted),
                const SizedBox(width: OmSpacing.sm),
                Expanded(
                  child: Text(
                    'Published by the store in its settings'
                    '${settings.updatedAt == null ? '' : ', last updated ${OmDates.date(settings.updatedAt)}'}',
                    style: styles.caption,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: OmSpacing.lg),
        _FreightFacts(settings: settings, kind: kind),
        const SizedBox(height: OmSpacing.lg),
        Wrap(
          spacing: OmSpacing.sm,
          runSpacing: OmSpacing.sm,
          children: <Widget>[
            OmButton(
              label: 'Ask about this policy',
              size: OmButtonSize.small,
              variant: OmButtonVariant.secondary,
              onPressed: () => Get.toNamed<dynamic>(OmRoutes.accountSupport),
            ),
            OmButton(
              label: 'Contact the store',
              size: OmButtonSize.small,
              variant: OmButtonVariant.ghost,
              onPressed: () => Get.toNamed<dynamic>(OmRoutes.contact),
            ),
          ],
        ),
        Obx(() => Get.find<SettingsStore>().isLive
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: OmSpacing.md),
                child: Text(
                  'The settings read has since failed, so this copy may be out of date.',
                  style: styles.caption,
                ),
              )),
      ],
    );
  }
}

/// The mechanical numbers a buyer actually needs next to the prose: tax handling, minimum order and
/// whether store pickup exists. Values come straight from settings; nothing is calculated here.
class _FreightFacts extends StatelessWidget {
  const _FreightFacts({required this.settings, required this.kind});

  final StoreSettings settings;
  final String kind;

  @override
  Widget build(BuildContext context) {
    if (kind != 'shipping' && kind != 'refund' && kind != 'cancellation') {
      return const SizedBox.shrink();
    }
    final styles = context.omText;
    final zones = settings.shippingZones.where((zone) => zone.isActive).length;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(title: 'The numbers behind it'),
          const SizedBox(height: OmSpacing.sm),
          Text(
            'Delivery zones published: $zones',
            style: styles.body,
            overflow: TextOverflow.visible,
          ),
          Text(
            settings.isPickupEnabled
                ? 'Store pickup is offered; the notes are on the contact page.'
                : 'Store pickup is not enabled right now.',
            style: styles.body,
            overflow: TextOverflow.visible,
          ),
          Text(
            settings.taxInclusive
                ? 'Listed unit rates include tax.'
                : 'Tax is added at checkout by the server, never by this app.',
            style: styles.body,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }
}
