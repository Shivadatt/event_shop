import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/storefront/common/external_links.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/static/widgets/static_page.dart';

/// `/contact`. Every channel comes from `store_settings`; an unpublished number is reported as
/// unpublished instead of being turned into a dead button.
final class ContactView extends StatelessWidget {
  const ContactView({super.key});

  @override
  Widget build(BuildContext context) {
    return StaticPage(
      title: 'Contact us',
      subtitle: 'Trade questions, order status and freight quotes all reach the same team.',
      currentRoute: OmRoutes.contact,
      content: (context, settings) {
        if (settings == null) return const OmLoading(message: 'Loading contact details…');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _WhatsAppCard(settings: settings),
            const SizedBox(height: OmSpacing.md),
            _ChannelsCard(settings: settings),
            const SizedBox(height: OmSpacing.md),
            _AddressCard(settings: settings),
            const SizedBox(height: OmSpacing.lg),
            const _SupportCard(),
          ],
        );
      },
    );
  }
}

class _WhatsAppCard extends StatelessWidget {
  const _WhatsAppCard({required this.settings});

  final StoreSettings settings;

  @override
  Widget build(BuildContext context) {
    final link = OmExternalLink.whatsappChat(
      settings.whatsappLink,
      message: 'Hi ${settings.shopName}, I would like to ask about wholesale supply.',
    );
    if (link.isEmpty) {
      return const OmCard(
        borderColor: OmColors.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OmSectionHeader(title: 'WhatsApp'),
            SizedBox(height: OmSpacing.sm),
            OmText(
              'The store has not published a WhatsApp number in its settings yet, so click-to-chat '
              'is unavailable. Phone, email and the support desk below still work.',
              variant: OmTextVariant.caption,
              overflow: TextOverflow.visible,
            ),
          ],
        ),
      );
    }
    return OmCard(
      elevated: true,
      borderColor: OmColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(
            title: 'Fastest reply: WhatsApp',
            subtitle: 'Opens click-to-chat in a new browser context.',
          ),
          const SizedBox(height: OmSpacing.md),
          OmButton(
            label: 'Chat on WhatsApp',
            icon: Icons.chat_bubble_outline,
            onPressed: () => OmExternalLink.open(context, link, label: 'WhatsApp'),
          ),
        ],
      ),
    );
  }
}

class _ChannelsCard extends StatelessWidget {
  const _ChannelsCard({required this.settings});

  final StoreSettings settings;

  @override
  Widget build(BuildContext context) => OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OmSectionHeader(title: 'Other channels'),
            const SizedBox(height: OmSpacing.sm),
            _ChannelRow(
              icon: Icons.call_outlined,
              label: 'Phone',
              value: settings.phone,
              actionLabel: 'Call',
              onAction: settings.phone.isEmpty
                  ? null
                  : () => OmExternalLink.open(
                        context,
                        'tel:${settings.phone.replaceAll(RegExp(r'[^0-9+]'), '')}',
                        label: 'Phone',
                      ),
            ),
            _ChannelRow(
              icon: Icons.mail_outline,
              label: 'Email',
              value: settings.email,
              actionLabel: 'Write',
              onAction: settings.email.isEmpty
                  ? null
                  : () => OmExternalLink.open(
                        context,
                        'mailto:${settings.email}',
                        label: 'Email',
                      ),
            ),
            _ChannelRow(
              icon: Icons.schedule,
              label: 'Opening hours',
              value: settings.openingHours,
            ),
            if (settings.socialLinks.isNotEmpty)
              for (final entry in settings.socialLinks.entries)
                if (_isWebUrl(entry.value))
                  _ChannelRow(
                    icon: Icons.link,
                    label: entry.key,
                    value: entry.value,
                    actionLabel: 'Open',
                    onAction: () =>
                        OmExternalLink.open(context, entry.value, label: entry.key),
                  ),
            if (settings.phone.isEmpty && settings.email.isEmpty)
              const OmText(
                'No phone or email is published yet either — the support desk in your account is '
                'the only written channel until the store fills in its settings.',
                variant: OmTextVariant.caption,
                overflow: TextOverflow.visible,
              ),
          ],
        ),
      );

  static bool _isWebUrl(String value) => value.startsWith('https://') || value.startsWith('http://');
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.icon,
    required this.label,
    required this.value,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OmSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: OmColors.textMuted),
          const SizedBox(width: OmSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label.toUpperCase(), style: styles.label),
                Text(
                  value.isEmpty ? 'Not published' : value,
                  style: styles.body,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),
          if (actionLabel != null)
            OmButton(
              label: actionLabel!,
              size: OmButtonSize.small,
              variant: OmButtonVariant.secondary,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.settings});

  final StoreSettings settings;

  @override
  Widget build(BuildContext context) {
    final address = settings.fullAddress;
    final map = settings.googleMapsUrl;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(title: 'Where we are'),
          const SizedBox(height: OmSpacing.sm),
          OmText(
            address.isEmpty ? 'The shop address is not published in store settings yet.' : address,
            overflow: TextOverflow.visible,
          ),
          const SizedBox(height: OmSpacing.md),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              if (map.isNotEmpty)
                OmButton(
                  label: 'Open in Maps',
                  icon: Icons.map_outlined,
                  size: OmButtonSize.small,
                  onPressed: () => OmExternalLink.open(context, map, label: 'Google Maps'),
                ),
              if (address.isNotEmpty)
                OmButton(
                  label: 'Copy address',
                  variant: OmButtonVariant.secondary,
                  size: OmButtonSize.small,
                  onPressed: () => OmExternalLink.copy(address, note: 'Shop address copied'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context) => OmCard(
        borderColor: OmColors.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OmSectionHeader(
              title: 'About an order you already placed?',
              subtitle: 'Use the support desk: it opens a thread on your account, so the team sees '
                  'the order and the conversation together.',
            ),
            const SizedBox(height: OmSpacing.md),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                OmButton(
                  label: 'Support desk',
                  size: OmButtonSize.small,
                  onPressed: () => Get.toNamed<dynamic>(OmRoutes.accountSupport),
                ),
                OmButton(
                  label: 'My orders',
                  size: OmButtonSize.small,
                  variant: OmButtonVariant.secondary,
                  onPressed: () => Get.toNamed<dynamic>(OmRoutes.accountOrders),
                ),
              ],
            ),
            const SizedBox(height: OmSpacing.sm),
            Obx(() => Get.find<SettingsStore>().isLive
                ? const SizedBox.shrink()
                : Text(
                    'Store settings could not be loaded, so the details above may be out of date.',
                    style: context.omText.caption,
                  )),
          ],
        ),
      );
}
