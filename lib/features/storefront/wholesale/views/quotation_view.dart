import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/wholesale/wholesale_controller.dart';

/// `/wholesale/quotation`.
///
/// NEEDS OWNER: there is no quotation document yet, so a request is filed as a `wholesaleQuery`
/// support ticket — a real record the trade desk can answer, carrying the ticket id back to the
/// buyer. No quote number is invented here.
final class WholesaleQuotationView extends GetView<WholesaleQuotationController> {
  const WholesaleQuotationView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Request a quotation',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const OmSectionHeader(
              title: 'Ask the trade desk',
              subtitle:
                  'Bulk lots, custom carton mixes, event-date delivery and freight to your pincode: '
                  'describe it and the store replies with a firm price. Nothing here reserves stock.',
            ),
            const SizedBox(height: OmSpacing.lg),
            Obx(() {
              final profile = Get.find<SessionStore>().changes.value;
              if (profile == null) {
                return OmEmptyState(
                  title: 'Sign in first',
                  message: 'The trade desk answers quotations in your account thread.',
                  icon: Icons.person_outline,
                  actionLabel: 'Sign in',
                  onAction: () => Get.toNamed<dynamic>(OmRoutes.login),
                );
              }
              if (profile.wholesaleStatus != WholesaleStatus.approved) {
                return OmCard(
                  borderColor: OmColors.warning,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      OmText(
                        'Quotations are handled for approved trade accounts. Your status is '
                        '${profile.wholesaleStatus.code}.',
                        variant: OmTextVariant.caption,
                        overflow: TextOverflow.visible,
                      ),
                      const SizedBox(height: OmSpacing.md),
                      OmButton(
                        label: 'Open the trade application',
                        size: OmButtonSize.small,
                        onPressed: () => Get.toNamed<dynamic>(OmRoutes.wholesaleApply),
                      ),
                    ],
                  ),
                );
              }
              return controller.ticket.value == null
                  ? _QuotationForm(controller: controller)
                  : _FiledCard(ticket: controller.ticket.value!);
            }),
            const SizedBox(height: OmSpacing.xl),
            const _HistorySection(),
            const SizedBox(height: OmSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _QuotationForm extends StatelessWidget {
  const _QuotationForm({required this.controller});

  final WholesaleQuotationController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
        final busy = controller.busy.value;
        final failure = controller.failure.value;
        final fields = <Widget>[
          OmTextField(
            label: 'What do you need quoted?',
            controller: controller.heading,
            required: true,
            validator: controller.validateHeading,
            hint: '500 11" latex balloons, 40 carton mixes',
          ),
          OmTextField(
            label: 'Needed by (optional)',
            controller: controller.neededBy,
            hint: 'Event on 14 Nov 2026',
            helper: 'Write the date in words — the desk confirms lead time in their reply.',
          ),
          OmTextField(
            label: 'Delivery pincode (optional)',
            controller: controller.pincode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: OmValidators.pincode,
            helper: 'Freight is zone-based, so the pincode decides the quote.',
          ),
          OmTextField(
            label: 'Items',
            controller: controller.items,
            required: true,
            maxLines: 10,
            minLines: 6,
            counterText: '',
            validator: controller.validateItems,
            hint: 'One SKU or product name per line, with the quantity you want.',
          ),
        ];

        return OmCard(
          elevated: true,
          child: Form(
            key: controller.formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OmCompactSwitch(
                  compact: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final field in fields) ...<Widget>[
                        field,
                        const SizedBox(height: OmSpacing.md),
                      ],
                    ],
                  ),
                  // Three short fields share a row on a laptop so the form reads like the
                  // purchase-order sheet buyers already use.
                  wide: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: fields[0]),
                          const SizedBox(width: OmSpacing.md),
                          Expanded(child: fields[1]),
                          const SizedBox(width: OmSpacing.md),
                          Expanded(child: fields[2]),
                        ],
                      ),
                      const SizedBox(height: OmSpacing.md),
                      fields[3],
                      const SizedBox(height: OmSpacing.md),
                    ],
                  ),
                ),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  children: <Widget>[
                    OmButton(
                      label: 'Send the request',
                      icon: Icons.local_postoffice_outlined,
                      loading: busy,
                      busyLabel: 'Sending…',
                      onPressed: controller.submit,
                    ),
                    OmButton(
                      label: 'Copy my bulk list',
                      variant: OmButtonVariant.secondary,
                      onPressed: () => controller.items.text = controller.prefillItems(),
                    ),
                    OmButton(
                      label: 'Bulk-order grid',
                      variant: OmButtonVariant.ghost,
                      onPressed: () => Get.toNamed<dynamic>(OmRoutes.wholesaleBulkOrder),
                    ),
                  ],
                ),
                if (failure != null) ...<Widget>[
                  const SizedBox(height: OmSpacing.md),
                  OmCard(
                    borderColor: OmColors.danger,
                    padding: const EdgeInsets.all(OmSpacing.sm),
                    child: OmText(failure.message,
                        variant: OmTextVariant.caption, overflow: TextOverflow.visible),
                  ),
                ],
                const SizedBox(height: OmSpacing.md),
                OmText(
                  'Prices, stock and freight in a quotation are the store\'s to confirm, and they '
                  'hold only for the window the desk states in its reply.',
                  variant: OmTextVariant.caption,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),
        );
      });
}

class _FiledCard extends StatelessWidget {
  const _FiledCard({required this.ticket});

  final SupportRequest ticket;

  @override
  Widget build(BuildContext context) => OmCard(
        elevated: true,
        borderColor: OmColors.success,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OmSectionHeader(
              title: 'Request filed',
              subtitle: 'The trade desk sees it in their wholesale queue and answers in the thread.',
            ),
            const SizedBox(height: OmSpacing.md),
            OmText('Ticket ${ticket.id}', variant: OmTextVariant.bodyStrong, selectable: true),
            OmText(
              '${ticket.subject} · status ${ticket.status.code} · ${OmDates.date(ticket.createdAt)}',
              variant: OmTextVariant.caption,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: OmSpacing.md),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                OmButton(
                  label: 'Open the support desk',
                  size: OmButtonSize.small,
                  onPressed: () => Get.toNamed<dynamic>(OmRoutes.accountSupport),
                ),
                OmButton(
                  label: 'Ask for another quotation',
                  variant: OmButtonVariant.secondary,
                  size: OmButtonSize.small,
                  onPressed: () => Get.offNamed<dynamic>(OmRoutes.wholesaleQuotation),
                ),
              ],
            ),
          ],
        ),
      );
}

class _HistorySection extends StatelessWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<WholesaleQuotationController>();
    return Obx(() {
      final history = controller.history;
      if (controller.loading.value && history.isEmpty) {
        return const OmLoading(message: 'Loading your quotation requests…');
      }
      final failure = controller.failure.value;
      if (failure != null && history.isEmpty) {
        return OmErrorState(failure: failure, onRetry: controller.loadHistory, compact: true);
      }
      if (history.isEmpty) {
        return const OmEmptyState(
          compact: true,
          title: 'No quotation requests yet',
          message: 'Requests you send are listed here with the ticket the store replies to.',
          icon: Icons.local_postoffice_outlined,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const OmSectionHeader(title: 'Your quotation requests'),
          const SizedBox(height: OmSpacing.md),
          for (final ticket in history) ...<Widget>[
            OmCard(
              padding: const EdgeInsets.all(OmSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        OmText(ticket.subject, variant: OmTextVariant.bodyStrong),
                        OmText(
                          '${OmDates.date(ticket.createdAt)} · ${ticket.messages.length} message(s)',
                          variant: OmTextVariant.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: OmSpacing.sm),
                  OmBadge(
                    dense: true,
                    label: ticket.status.code,
                    tone: switch (ticket.status) {
                      SupportStatus.open => OmTone.info,
                      SupportStatus.inProgress => OmTone.gold,
                      SupportStatus.awaitingCustomer => OmTone.warning,
                      SupportStatus.resolved => OmTone.success,
                      SupportStatus.closed => OmTone.neutral,
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: OmSpacing.sm),
          ],
        ],
      );
    });
  }
}
