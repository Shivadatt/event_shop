import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/orders/order_list_controller.dart';
import 'package:om_events/features/storefront/orders/widgets/order_card.dart';
import 'package:om_events/features/storefront/orders/widgets/order_status_timeline.dart';

/// `/account/orders`. Reuses the shared `OrderListController` (cursor-paged) and the order list
/// widgets, so the history table and the order card can never disagree.
final class OrdersView extends GetView<OrderListController> {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'Order history',
      subtitle: 'The pages you have loaded are searchable here; the full history stays on the '
          'store’s servers.',
      currentRoute: OmRoutes.accountOrders,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Obx(() {
            final failure = controller.failure.value;
            if (failure != null && controller.orders.isEmpty) {
              return OmErrorState(failure: failure, onRetry: controller.load);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmTextField(
                  label: 'Find an order',
                  hint: 'Order number or product name',
                  prefixIcon: Icons.search,
                  initialValue: '',
                  onChanged: (value) => controller.term.value = value,
                ),
                const SizedBox(height: OmSpacing.md),
                if (controller.availableStatuses.isNotEmpty)
                  Wrap(
                    spacing: OmSpacing.sm,
                    runSpacing: OmSpacing.sm,
                    children: <Widget>[
                      OmFilterChip(
                        label: 'All',
                        selected: controller.statusFilter.value == null,
                        onTap: () => controller.setStatusFilter(null),
                        trailingCount: controller.orders.length,
                      ),
                      for (final status in controller.availableStatuses)
                        OmFilterChip(
                          label: orderStatusLabel(status),
                          selected: controller.statusFilter.value == status,
                          onTap: () => controller.setStatusFilter(status),
                        ),
                    ],
                  ),
                if (controller.isFiltering) ...<Widget>[
                  const SizedBox(height: OmSpacing.sm),
                  OmText(
                    'Filtering the ${controller.orders.length} loaded orders only.',
                    variant: OmTextVariant.caption,
                  ),
                  OmButton(
                    label: 'Clear filters',
                    variant: OmButtonVariant.ghost,
                    size: OmButtonSize.small,
                    onPressed: controller.clearFilters,
                  ),
                ],
              ],
            );
          }),
          const SizedBox(height: OmSpacing.lg),
          Obx(() {
            if (controller.loading.value) {
              return const Column(
                children: <Widget>[
                  OmProductCardSkeleton(),
                  SizedBox(height: OmSpacing.md),
                  OmProductCardSkeleton(),
                ],
              );
            }
            final visible = controller.visible;
            if (visible.isEmpty) {
              return controller.orders.isEmpty
                  ? OmEmptyState.noOrders(
                      onBrowse: () => Get.offAllNamed<dynamic>(OmRoutes.home),
                    )
                  : OmEmptyState.noProducts(onReset: controller.clearFilters);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OrderListBody(orders: visible, actions: controller),
                const SizedBox(height: OmSpacing.md),
                Obx(() {
                  if (!controller.hasMore.value) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: OmButton(
                      label: 'Load older orders',
                      variant: OmButtonVariant.secondary,
                      loading: controller.loadingMore.value,
                      busyLabel: 'Loading…',
                      onPressed: controller.loadMore,
                    ),
                  );
                }),
                const SizedBox(height: OmSpacing.md),
                Obx(() => OrderActionError(failure: controller.actionFailure.value)),
              ],
            );
          }),
        ],
      ),
    );
  }
}
