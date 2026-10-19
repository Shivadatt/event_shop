import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/payment.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/storefront/static/widgets/static_page.dart';

/// `/about` — the store's own description plus the mechanical facts a trade buyer needs: minimum
/// order, freight bands and lead times, all read from `store_settings`.
final class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    return StaticPage(
      title: 'About the store',
      subtitle: 'Who ships to you, and how buying works here.',
      currentRoute: OmRoutes.about,
      showWhenUnlive: true,
      content: (context, settings) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StaticProse(
            text: settings?.description ?? '',
            title: settings?.shopName,
            emptyMessage: 'The store has not written its about page yet, so only the trading terms '
                'below are shown.',
          ),
          const SizedBox(height: OmSpacing.lg),
          const _HowToBuy(),
          const SizedBox(height: OmSpacing.lg),
          if (settings != null) ..._aboutBlocks(context, settings) else const SizedBox.shrink(),
        ],
      ),
    );
  }

  List<Widget> _aboutBlocks(BuildContext context, StoreSettings settings) {
    final styles = context.omText;
    final freeAbove = settings.freeShippingAbovePaise;
    return <Widget>[
      OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OmSectionHeader(title: 'Trading terms', eyebrow: 'Wholesale'),
            const SizedBox(height: OmSpacing.sm),
            _SpecLine(
              label: 'Minimum order',
              value: settings.minOrderValuePaise <= 0
                  ? Text('None published', style: styles.body)
                  : OmMoneyText(settings.minOrderValuePaise, decimals: false, style: styles.price),
            ),
            _SpecLine(
              label: 'Free freight above',
              value: freeAbove == null
                  ? Text('Not offered', style: styles.body)
                  : Row(
                      children: <Widget>[
                        Text('Orders above ', style: styles.caption),
                        OmMoneyText(freeAbove, decimals: false, style: styles.price),
                      ],
                    ),
            ),
            _SpecLine(
              label: 'Prices include tax',
              value: Text(
                settings.taxInclusive
                    ? 'Yes — the listed rate is what you pay per unit'
                    : 'No — tax is added at checkout by the server',
                style: styles.caption,
              ),
            ),
            if (settings.gstNumber.isNotEmpty)
              _SpecLine(
                label: 'GSTIN',
                value: SelectableText(settings.gstNumber, style: styles.body),
              ),
            if (settings.isPickupEnabled && settings.pickupNotes.isNotEmpty) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              OmText(
                'Store pickup: ${settings.pickupNotes}',
                variant: OmTextVariant.caption,
                overflow: TextOverflow.visible,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: OmSpacing.lg),
      _ShippingZones(zones: settings.shippingZones),
      const SizedBox(height: OmSpacing.lg),
      _PaymentMethods(methods: settings.paymentMethods),
    ];
  }
}

/// A label over a value that may itself be a widget, so money always renders through
/// `OmMoneyText` instead of a hand-formatted string.
final class _SpecLine extends StatelessWidget {
  const _SpecLine({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label.toUpperCase(), style: context.omText.label),
            const SizedBox(height: 2),
            value,
          ],
        ),
      );
}

class _HowToBuy extends StatelessWidget {
  const _HowToBuy();

  static const List<(String, String, IconData)> _steps = <(String, String, IconData)>[
    (
      'Fill your cart by the carton',
      'Every product lists its quantity slabs. The rate that matches your quantity is applied '
          'automatically — no code to remember.',
      Icons.inventory_2_outlined,
    ),
    (
      'Freight follows your pincode',
      'Delivery zones and lead times are set by the store. Enter the pincode at checkout and the '
          'applicable zone, fee and ETA are shown before you pay.',
      Icons.local_shipping_outlined,
    ),
    (
      'The server confirms the amount',
      'Stock, pricing and payment success are answered by the backend when the order is created. If '
          'anything moved, you are asked to confirm the new total rather than being charged silently.',
      Icons.receipt_long_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) => OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OmSectionHeader(title: 'How buying works'),
            const SizedBox(height: OmSpacing.md),
            for (final (title, body, icon) in _steps)
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(icon, size: 20, color: OmColors.gold),
                    const SizedBox(width: OmSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          OmText(title, variant: OmTextVariant.bodyStrong),
                          OmText(body, variant: OmTextVariant.muted, overflow: TextOverflow.visible),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            OmButton(
              label: 'Browse the catalogue',
              icon: Icons.storefront_outlined,
              size: OmButtonSize.small,
              onPressed: () => Get.toNamed<dynamic>(OmRoutes.home),
            ),
          ],
        ),
      );
}

class _ShippingZones extends StatelessWidget {
  const _ShippingZones({required this.zones});

  final List<ShippingZone> zones;

  @override
  Widget build(BuildContext context) {
    if (zones.isEmpty) {
      return const OmEmptyState(
        compact: true,
        title: 'Delivery zones are not published yet',
        message: 'Ask the support desk for a freight quote to your pincode.',
        icon: Icons.local_shipping_outlined,
      );
    }
    final active = zones.where((zone) => zone.isActive).toList(growable: false);
    final styles = context.omText;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(title: 'Delivery zones'),
          const SizedBox(height: OmSpacing.sm),
          OmResponsiveTable(
            minTableWidth: OmBreakpoints.laptop,
            table: Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(4),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                TableRow(
                  children: <Widget>[
                    _cell(Text('Zone', style: styles.label)),
                    _cell(Text('Pincodes', style: styles.label)),
                    _cell(Text('Freight', style: styles.label)),
                    _cell(Text('Lead time', style: styles.label), align: TextAlign.end),
                  ],
                ),
                for (final zone in active)
                  TableRow(
                    children: <Widget>[
                      _cell(Text(zone.name, style: styles.body)),
                      _cell(Text(zone.pincodePrefixes.join(', '), style: styles.caption)),
                      _cell(
                        OmMoneyText(zone.flatRatePaise, decimals: false, style: styles.price),
                      ),
                      _cell(Text(zone.etaLabel, style: styles.body), align: TextAlign.end),
                    ],
                  ),
              ],
            ),
            asCards: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final zone in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: OmSpacing.sm),
                    child: OmCard(
                      padding: const EdgeInsets.all(OmSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          OmText(zone.name, variant: OmTextVariant.bodyStrong),
                          OmText(
                            '${zone.pincodePrefixes.join(', ')} · ${zone.etaLabel}',
                            variant: OmTextVariant.caption,
                            overflow: TextOverflow.visible,
                          ),
                          OmMoneyText(zone.flatRatePaise, decimals: false),
                          if (zone.freeAbovePaise != null)
                            Row(
                              children: <Widget>[
                                Text('Free above ', style: styles.caption),
                                OmMoneyText(zone.freeAbovePaise!, decimals: false),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (active.length != zones.length)
            OmText(
              '${zones.length - active.length} zone(s) the store has switched off are hidden.',
              variant: OmTextVariant.caption,
            ),
        ],
      ),
    );
  }

  static Widget _cell(Widget child, {TextAlign align = TextAlign.start}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm),
        child: switch (align) {
          TextAlign.end => Align(alignment: Alignment.centerRight, child: child),
          _ => child,
        },
      );
}

class _PaymentMethods extends StatelessWidget {
  const _PaymentMethods({required this.methods});

  final List<PaymentMethodOption> methods;

  @override
  Widget build(BuildContext context) {
    final live = methods.where((method) => method.isEnabled).toList(growable: false);
    if (live.isEmpty) {
      return const OmEmptyState(
        compact: true,
        title: 'Payment options are not published yet',
        message: 'The store enables methods in its settings; checkout will show only what is live.',
        icon: Icons.payments_outlined,
      );
    }
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(title: 'Payment methods'),
          const SizedBox(height: OmSpacing.sm),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              for (final method in live)
                OmBadge(label: method.label, tone: OmTone.info, dense: true),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          const OmText(
            'Availability and any surcharge are confirmed at checkout; the prepaid link is issued by '
            'the payment gateway, not by this app.',
            variant: OmTextVariant.caption,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }
}
