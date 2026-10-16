import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/features/storefront/account/account_data_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';

/// `/account/notifications`. Live stream from the store; a read marker is written back rather
/// than assumed.
final class NotificationsView extends GetView<NotificationController> {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'Notifications',
      subtitle: 'Order updates, back-in-stock alerts and wholesale decisions the store sent you.',
      currentRoute: OmRoutes.accountNotifications,
      actions: <Widget>[
        Obx(
          () => OmButton(
            label: controller.unreadCount == 0
                ? 'All caught up'
                : 'Mark ${controller.unreadCount} as read',
            variant: OmButtonVariant.secondary,
            size: OmButtonSize.small,
            onPressed: controller.unreadCount == 0 ? null : controller.markAllRead,
          ),
        ),
      ],
      body: Obx(() {
        if (controller.loading.value && controller.items.isEmpty) {
          return const OmLoading(message: 'Loading notifications…');
        }
        final failure = controller.failure.value;
        if (failure != null && controller.items.isEmpty) {
          return OmErrorState(failure: failure, onRetry: controller.retry);
        }
        if (controller.items.isEmpty) {
          return const OmEmptyState(
            title: 'No notifications',
            message: 'When the store updates an order or restocks something you saved, it shows '
                'up here.',
            icon: Icons.notifications_none,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final item in controller.items)
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.sm),
                child: _NotificationCard(item: item, controller: controller),
              ),
          ],
        );
      }),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.controller});

  final AppNotification item;
  final NotificationController controller;

  (String, OmTone, IconData) get _kind => switch (item.kind) {
        NotificationKind.orderPlaced => ('Order placed', OmTone.success, Icons.receipt_long),
        NotificationKind.orderUpdate => ('Order update', OmTone.info, Icons.local_shipping),
        NotificationKind.paymentUpdate => ('Payment', OmTone.gold, Icons.account_balance_wallet),
        NotificationKind.backInStock => ('Back in stock', OmTone.success, Icons.inventory_2),
        NotificationKind.wholesaleDecision => ('Wholesale', OmTone.gold, Icons.business),
        NotificationKind.reviewResponse => ('Review reply', OmTone.neutral, Icons.rate_review),
        NotificationKind.promo => ('Offer', OmTone.warning, Icons.local_offer),
      };

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = _kind;
    return OmCard(
      onTap: item.route.isEmpty ? null : () => controller.open(item),
      borderColor: item.isRead ? null : OmColors.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: context.omText.muted.color),
              const SizedBox(width: OmSpacing.sm),
              Expanded(child: OmText(item.title, variant: OmTextVariant.bodyStrong)),
              OmBadge(label: label, tone: tone, dense: true),
            ],
          ),
          const SizedBox(height: OmSpacing.xs),
          OmText(
            item.body,
            variant: OmTextVariant.muted,
            overflow: TextOverflow.visible,
            maxLines: 6,
          ),
          const SizedBox(height: OmSpacing.sm),
          Row(
            children: <Widget>[
              OmText(OmDates.dateTime(item.createdAt), variant: OmTextVariant.caption),
              const Spacer(),
              if (!item.isRead)
                const OmBadge(label: 'Unread', tone: OmTone.gold, dense: true, icon: Icons.fiber_new),
              if (item.route.isNotEmpty) ...<Widget>[
                const SizedBox(width: OmSpacing.sm),
                OmButton(
                  label: 'Open',
                  variant: OmButtonVariant.ghost,
                  size: OmButtonSize.small,
                  onPressed: () => controller.open(item),
                ),
              ] else if (!item.isRead)
                OmButton(
                  label: 'Mark read',
                  variant: OmButtonVariant.ghost,
                  size: OmButtonSize.small,
                  onPressed: () => controller.markRead(item),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
