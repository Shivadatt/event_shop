import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_price.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/storefront/common/external_links.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';
import 'package:om_events/features/storefront/common/print_bridge.dart';

/// The line snapshots of a placed order, exactly as the server stored them. Later catalogue edits
/// cannot rewrite these rows — that immutability is the point of `OrderItem`.
final class OrderItemsCard extends StatelessWidget {
  const OrderItemsCard({super.key, required this.items, this.title = 'Items in this order'});

  final List<OrderItem> items;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OmSectionHeader(title: title),
        const SizedBox(height: OmSpacing.sm),
        OmResponsiveTable(
          table: _ItemsTable(items: items),
          asCards: Column(
            children: <Widget>[
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: OmSpacing.sm),
                  child: OrderItemRow(item: item),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items});

  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) => DataTable(
        headingRowHeight: 40,
        columnSpacing: OmSpacing.xl,
        columns: const <DataColumn>[
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Qty')),
          DataColumn(label: Text('Unit price')),
          DataColumn(label: Text('Line total')),
          DataColumn(label: Text('Slab')),
        ],
        rows: <DataRow>[
          for (final item in items)
            DataRow(
              onSelectChanged: item.slug.isEmpty
                  ? null
                  : (_) => Get.toNamed<dynamic>(OmRoutes.forProduct(item.slug)),
              cells: <DataCell>[
                DataCell(_ItemIdentity(item: item, compact: false)),
                DataCell(Text('${item.qty} ${item.unit}')),
                DataCell(Text(OmMoney.format(item.unitPricePaise))),
                DataCell(Text(OmMoney.format(item.lineTotalPaise))),
                DataCell(
                  Text(
                    item.slabLabel ?? (item.slabMinQty == null ? 'Standard' : '${item.slabMinQty}+'),
                    style: context.omText.caption,
                  ),
                ),
              ],
            ),
        ],
      );
}

/// Narrow-width form of the same snapshot row.
final class OrderItemRow extends StatelessWidget {
  const OrderItemRow({super.key, required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) => OmCard(
        padding: const EdgeInsets.all(OmSpacing.sm),
        onTap: item.slug.isEmpty
            ? null
            : () => Get.toNamed<dynamic>(OmRoutes.forProduct(item.slug)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 46,
              width: 46,
              child: OmMediaImage(
                ref: item.imageUrl.isEmpty
                    ? null
                    : MediaRef(id: item.productId, url: item.imageUrl, altText: item.name),
              ),
            ),
            const SizedBox(width: OmSpacing.sm),
            Expanded(child: _ItemIdentity(item: item, compact: true)),
            const SizedBox(width: OmSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                OmMoneyText(item.lineTotalPaise, style: context.omText.price),
                OmText('${item.qty} ${item.unit}', variant: OmTextVariant.caption),
              ],
            ),
          ],
        ),
      );
}

class _ItemIdentity extends StatelessWidget {
  const _ItemIdentity({required this.item, required this.compact});

  final OrderItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(item.name, style: styles.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          <String>[
            if (item.sku.isNotEmpty) item.sku,
            if (item.variantId != null) 'option',
            if (compact) '${item.qty} ${item.unit} @ ${OmMoney.format(item.unitPricePaise)}',
            if (item.savedPaise > 0) 'saved ${OmMoney.format(item.savedPaise)}',
          ].where((s) => s.isNotEmpty).join(' · '),
          style: styles.caption,
        ),
      ],
    );
  }
}

/// Everything factual about an order that is not money or a line: numbers, contact, delivery,
/// invoice and tracking.
final class OrderMetaCard extends StatelessWidget {
  const OrderMetaCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Order number', order.orderNumber.isEmpty ? '—' : order.orderNumber),
      ('Placed', OmDates.dateTime(order.createdAt)),
      ('Last update', OmDates.dateTime(order.updatedAt)),
      ('Contact', order.contactEmail.isEmpty && order.contactPhone.isEmpty
          ? '—'
          : '${order.contactEmail} ${order.contactPhone}'.trim()),
      ('Delivery mode', order.deliveryMode == DeliveryMode.pickup ? 'Store pickup' : 'Courier'),
      if (order.shipping != null) ('Shipping to', order.shipping!.singleLine),
      ('Payment method', order.paymentMethod.isEmpty ? '—' : order.paymentMethod),
      ('Reference', order.transactionReference.isEmpty ? '—' : order.transactionReference),
      if (order.couponCode.isNotEmpty) ('Coupon', order.couponCode),
      if (order.invoiceNumber.isNotEmpty) ('Invoice', order.invoiceNumber),
      if (order.source.isNotEmpty) ('Placed via', order.source),
      if (order.customerNote.isNotEmpty) ('Your note', order.customerNote),
    ];

    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(title: 'Order details'),
          const SizedBox(height: OmSpacing.sm),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: context.isCompactLayout ? 110 : 150,
                    child: Text(label.toUpperCase(), style: context.omText.label),
                  ),
                  Expanded(
                    child: SelectableText(
                      value,
                      style: context.omText.body,
                    ),
                  ),
                ],
              ),
            ),
          if (order.trackingUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            OmButton(
              label: 'Track this parcel',
              icon: Icons.open_in_new,
              variant: OmButtonVariant.outline,
              size: OmButtonSize.small,
              onPressed: () => OmExternalLink.open(
                context,
                order.trackingUrl,
                label: order.carrier.isEmpty ? 'Tracking' : order.carrier,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Invoice reprint. There is no printable HTML endpoint for a customer invoice yet, so this drives
/// the browser's own print of the rendered order page and says so rather than pretending to fetch
/// a PDF. NEEDS OWNER: an invoice document/endpoint the storefront can open.
final class InvoicePrintActions extends StatelessWidget {
  const InvoicePrintActions({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const OmButton(
          label: 'Print this invoice view',
          icon: Icons.print_outlined,
          variant: OmButtonVariant.secondary,
          size: OmButtonSize.small,
          onPressed: OmPrint.printCurrentPage,
        ),
        const SizedBox(height: OmSpacing.xs),
        OmText(
          order.invoiceNumber.isEmpty
              ? 'The invoice number is issued by the store once billing finalises this order; '
                    'printing now shows the order as it stands.'
              : 'Invoice ${order.invoiceNumber}. Printing renders this page — the store can also '
                    'email the invoice.',
          variant: OmTextVariant.caption,
        ),
      ],
    );
  }
}
