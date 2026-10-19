import 'package:flutter/material.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';

/// The forward fulfilment pipeline, in the order the status enum defines it.
const List<OrderStatus> _pipeline = <OrderStatus>[
  OrderStatus.placed,
  OrderStatus.confirmed,
  OrderStatus.processing,
  OrderStatus.packed,
  OrderStatus.shipped,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

/// Plain-language label for a status. Kept here so an order card, a timeline and a notification
/// never describe the same state with three different words.
String orderStatusLabel(OrderStatus status) => switch (status) {
      OrderStatus.placed => 'Placed',
      OrderStatus.confirmed => 'Confirmed',
      OrderStatus.processing => 'Being prepared',
      OrderStatus.packed => 'Packed',
      OrderStatus.shipped => 'Shipped',
      OrderStatus.outForDelivery => 'Out for delivery',
      OrderStatus.delivered => 'Delivered',
      OrderStatus.cancelled => 'Cancelled',
      OrderStatus.returned => 'Returned',
      OrderStatus.refunded => 'Refunded',
    };

OmTone orderStatusTone(OrderStatus status) => switch (status) {
      OrderStatus.delivered => OmTone.success,
      OrderStatus.cancelled || OrderStatus.returned => OmTone.warning,
      OrderStatus.refunded => OmTone.info,
      _ => OmTone.gold,
    };

OmTone paymentStatusTone(PaymentStatus status) => switch (status) {
      PaymentStatus.paid || PaymentStatus.notRequired => OmTone.success,
      PaymentStatus.failed => OmTone.danger,
      PaymentStatus.refunded || PaymentStatus.partiallyRefunded => OmTone.info,
      _ => OmTone.warning,
    };

String paymentStatusLabel(PaymentStatus status) => switch (status) {
      PaymentStatus.notRequired => 'No payment needed',
      PaymentStatus.pending => 'Payment pending',
      PaymentStatus.codPending => 'Pay on delivery',
      PaymentStatus.paid => 'Paid',
      PaymentStatus.failed => 'Payment failed',
      PaymentStatus.refunded => 'Refunded',
      PaymentStatus.partiallyRefunded => 'Partly refunded',
    };

final class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status, this.dense = false});

  final OrderStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => OmBadge(
        label: orderStatusLabel(status),
        tone: orderStatusTone(status),
        dense: dense,
        icon: Icons.insights_outlined,
      );
}

final class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.status, this.dense = false});

  final PaymentStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => OmBadge(
        label: paymentStatusLabel(status),
        tone: paymentStatusTone(status),
        dense: dense,
        icon: Icons.account_balance_wallet_outlined,
      );
}

/// Status timeline built from `OrderStatus` itself: the pipeline it walked and, via
/// [OrderStatus.nextSteps], the moves the store can still make. Only the two dates that actually
/// exist on the order record are shown — inventing a timestamp per step would be fake data.
final class OrderStatusTimeline extends StatelessWidget {
  const OrderStatusTimeline({super.key, required this.order});

  final Order order;

  bool _reached(OrderStatus status) {
    if (status == order.status) return true;
    final current = order.status;
    final currentIndex = _pipeline.indexOf(current);
    if (currentIndex < 0) {
      // Cancelled / returned / refunded: the order did get placed before it turned.
      return status == OrderStatus.placed;
    }
    return _pipeline.indexOf(status) <= currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final terminal = order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.returned ||
        order.status == OrderStatus.refunded;
    final steps = <OrderStatus>[
      ..._pipeline,
      if (terminal) order.status,
    ];
    final next = order.status.nextSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const OmText('Order progress', variant: OmTextVariant.h3),
        const SizedBox(height: OmSpacing.md),
        for (final status in steps)
          _TimelineRow(
            label: orderStatusLabel(status),
            reached: _reached(status),
            current: status == order.status,
            isLast: status == steps.last,
            note: status == steps.first && order.createdAt != null
                ? OmDates.dateTime(order.createdAt)
                : (status == order.status && terminal && order.updatedAt != null
                    ? OmDates.dateTime(order.updatedAt)
                    : null),
          ),
        const SizedBox(height: OmSpacing.sm),
        Text(
          next.isEmpty
              ? 'This order is closed — no further status changes are possible.'
              : 'Next possible updates: ${next.map(orderStatusLabel).join(', ')}. '
                  'The store team moves it forward; you cannot change it yourself.',
          style: styles.caption,
        ),
        if (order.cancelledReason.isNotEmpty) ...<Widget>[
          const SizedBox(height: OmSpacing.sm),
          OmText('Reason recorded: ${order.cancelledReason}', variant: OmTextVariant.caption),
        ],
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.reached,
    required this.current,
    required this.isLast,
    this.note,
  });

  final String label;
  final bool reached;
  final bool current;
  final bool isLast;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Icon(
                reached ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: reached ? (current ? OmColors.gold : OmColors.success) : styles.muted.color,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: reached ? OmColors.line : styles.muted.color,
                  ),
                ),
            ],
          ),
          const SizedBox(width: OmSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : OmSpacing.md, top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: current ? styles.bodyStrong : (reached ? styles.body : styles.muted),
                  ),
                  if (note != null) Text(note!, style: styles.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
