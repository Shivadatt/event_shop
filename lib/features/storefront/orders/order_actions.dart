import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/repositories/order_repository.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';

/// Cancellation, return and reorder for an order. Shared by the order list, the order detail page
/// and the order-success page so a buyer gets identical affordances everywhere.
///
/// Every move is a repository call: this code never mutates `Order.status` locally, because the
/// status is the store's answer, not the browser's.
mixin OrderActionsMixin on GetxController {
  final RxBool acting = false.obs;
  final Rxn<OmFailure> actionFailure = Rxn<OmFailure>();

  Future<void> cancelOrder(Order order, {required String reason}) async {
    acting.value = true;
    actionFailure.value = null;
    final ok = await tryCall(
      () => Get.find<OrderRepository>().requestCancellation(order.id, reason: reason),
      onFailure: (f) => actionFailure.value = f,
    );
    acting.value = false;
    if (ok) {
      Get.snackbar(
        'Cancellation requested',
        'The store has been told to release order ${order.orderNumber}. Its status updates when '
            'they confirm.',
        snackDuration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> returnOrder(Order order, {required String reason}) async {
    acting.value = true;
    actionFailure.value = null;
    final ok = await tryCall(
      () => Get.find<OrderRepository>().requestReturn(order.id, reason: reason),
      onFailure: (f) => actionFailure.value = f,
    );
    acting.value = false;
    if (ok) {
      Get.snackbar(
        'Return requested',
        'The store will contact you about returning ${order.orderNumber}.',
        snackDuration: const Duration(seconds: 5),
      );
    }
  }

  /// Reorder asks the server to expand the old lines into a draft and puts that intent in the
  /// cart. Prices are re-derived from the live catalogue afterwards, and the total is still the
  /// order server's to decide.
  Future<void> reorder(Order order) async {
    acting.value = true;
    actionFailure.value = null;
    final lines = await safeCall<List<DraftLine>>(
      () => Get.find<OrderRepository>().expandReorder(order.id),
      onFailure: (f) => actionFailure.value = f,
    );
    acting.value = false;
    if (lines == null || lines.isEmpty) return;
    final cart = Get.find<CartStore>();
    for (final line in lines) {
      cart.add(
        CartLine(productId: line.productId, variantId: line.variantId, qty: line.qty),
      );
    }
    Get.toNamed<dynamic>(OmRoutes.cart);
  }
}

/// The action row for one order. Buttons appear only when the order's own status allows the move;
/// the server still has to accept the request.
final class OrderActionButtons extends StatelessWidget {
  const OrderActionButtons({
    super.key,
    required this.order,
    required this.actions,
  });

  final Order order;
  final OrderActionsMixin actions;

  Future<void> _askAndAct({
    required BuildContext context,
    required String title,
    required String hint,
    required Future<void> Function(String reason) act,
  }) async {
    final styles = context.omText;
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              OmTextField(
                label: 'Reason',
                controller: controller,
                hint: hint,
                maxLines: 3,
                minLines: 2,
                validator: (value) => OmValidators.required(value, label: 'Reason'),
              ),
              const SizedBox(height: OmSpacing.sm),
              Text(
                'This sends a request to the store. Nothing changes until they act on it.',
                style: styles.caption,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Never mind', style: styles.body),
          ),
          TextButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: Text('Send request', style: styles.bodyStrong),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    await act(reason);
  }

  List<Widget> _buttons(BuildContext context) {
    final buttons = <Widget>[];
    if (order.canCancel) {
      buttons.add(
        OmButton(
          label: 'Request cancellation',
          variant: OmButtonVariant.danger,
          size: OmButtonSize.small,
          loading: actions.acting.value,
          onPressed: () => _askAndAct(
            context: context,
            title: 'Cancel ${order.orderNumber}?',
            hint: 'Why do you need to cancel? (planning changed, wrong item…)',
            act: (reason) => actions.cancelOrder(order, reason: reason),
          ),
        ),
      );
    }
    if (order.status == OrderStatus.delivered) {
      buttons.add(
        OmButton(
          label: 'Request a return',
          variant: OmButtonVariant.outline,
          size: OmButtonSize.small,
          loading: actions.acting.value,
          onPressed: () => _askAndAct(
            context: context,
            title: 'Return ${order.orderNumber}?',
            hint: 'Which item, and what is wrong with it?',
            act: (reason) => actions.returnOrder(order, reason: reason),
          ),
        ),
      );
    }
    if (order.canReorder) {
      buttons.add(
        OmButton(
          label: 'Buy these again',
          variant: OmButtonVariant.secondary,
          size: OmButtonSize.small,
          icon: Icons.replay,
          loading: actions.acting.value,
          onPressed: () => actions.reorder(order),
        ),
      );
    }
    buttons.add(
      OmButton(
        label: 'Support with this order',
        variant: OmButtonVariant.ghost,
        size: OmButtonSize.small,
        onPressed: () => Get.toNamed<dynamic>(
          OmRoutes.accountSupport,
          parameters: <String, String>{OmRouteArgs.orderId: order.id},
        ),
      ),
    );

    return buttons;
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final wrapped = _buttons(context);
        if (wrapped.isEmpty) return const SizedBox.shrink();
        // Wrap, never a fixed Row: four action buttons overflow a phone and would push the page
        // sideways.
        return Wrap(
          spacing: OmSpacing.sm,
          runSpacing: OmSpacing.sm,
          children: wrapped,
        );
      });
}

/// Small helper card used above the action buttons when a request failed.
final class OrderActionError extends StatelessWidget {
  const OrderActionError({super.key, required this.failure});

  final OmFailure? failure;

  @override
  Widget build(BuildContext context) {
    final error = failure;
    if (error == null) return const SizedBox.shrink();
    return OmCard(
      borderColor: OmColors.danger,
      child: OmText(error.message, variant: OmTextVariant.caption),
    );
  }
}
