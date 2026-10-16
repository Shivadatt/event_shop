import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/features/storefront/account/account_data_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';

/// `/account/support`. Tickets are written through `AccountRepository`; a reply never edits the
/// stored status locally — the store's answer decides when a thread is resolved.
final class SupportView extends GetView<SupportController> {
  const SupportView({super.key});

  static const Map<SupportTopic, String> _labels = <SupportTopic, String>{
    SupportTopic.orderIssue: 'Problem with an order',
    SupportTopic.returnRequest: 'Return or replacement',
    SupportTopic.wholesaleQuery: 'Wholesale / quotation',
    SupportTopic.pricingQuery: 'Pricing question',
    SupportTopic.productQuestion: 'Question about a product',
    SupportTopic.other: 'Something else',
  };

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'Support desk',
      subtitle: 'One place for order, return and wholesale questions. Nothing here changes an '
          'order by itself — the store acts, and you see the result.',
      currentRoute: OmRoutes.accountSupport,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Obx(() {
            final failure = controller.failure.value;
            return OmCard(
              elevated: true,
              child: Form(
                key: controller.formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const OmSectionHeader(
                      title: 'Open a ticket',
                      subtitle: 'Include your order number if you have one — it saves a round trip.',
                    ),
                    const SizedBox(height: OmSpacing.md),
                    if (controller.orderId.value != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: OmSpacing.sm),
                        child: OmBadge(
                          label: 'Linked to order ${controller.orderId.value}',
                          tone: OmTone.gold,
                          icon: Icons.receipt_long,
                        ),
                      ),
                    OmDropdown<SupportTopic>(
                      label: 'Topic',
                      value: controller.topic.value,
                      items: SupportTopic.values,
                      itemLabel: (topic) => _labels[topic] ?? topic.code,
                      onChanged: (topic) {
                        if (topic != null) controller.topic.value = topic;
                      },
                    ),
                    const SizedBox(height: OmSpacing.md),
                    OmTextField(
                      label: 'Subject',
                      controller: controller.subject,
                      validator: controller.validateSubject,
                      required: true,
                      maxLength: 120,
                    ),
                    const SizedBox(height: OmSpacing.md),
                    OmTextField(
                      label: 'What happened?',
                      controller: controller.message,
                      maxLines: 6,
                      minLines: 3,
                      validator: controller.validateMessage,
                      required: true,
                    ),
                    const SizedBox(height: OmSpacing.lg),
                    Wrap(
                      spacing: OmSpacing.sm,
                      runSpacing: OmSpacing.sm,
                      children: <Widget>[
                        OmButton(
                          label: 'Send to the store',
                          loading: controller.busy.value,
                          busyLabel: 'Sending…',
                          onPressed: controller.submit,
                        ),
                        OmButton(
                          label: 'Message about a product',
                          variant: OmButtonVariant.secondary,
                          onPressed: () => Get.toNamed<dynamic>(OmRoutes.search),
                        ),
                      ],
                    ),
                    if (controller.opened.value) ...<Widget>[
                      const SizedBox(height: OmSpacing.md),
                      OmText(
                        'Ticket created. It appears in your list below and the store answers here '
                        'or on the contact channel you prefer.',
                        variant: OmTextVariant.caption,
                        color: OmColors.success,
                        overflow: TextOverflow.visible,
                      ),
                    ],
                    if (failure != null) ...<Widget>[
                      const SizedBox(height: OmSpacing.md),
                      OmText(failure.message, variant: OmTextVariant.caption,
                          color: OmColors.danger),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: OmSpacing.lg),
          const OmSectionHeader(title: 'Your tickets'),
          const SizedBox(height: OmSpacing.sm),
          Obx(() {
            if (controller.loading.value) return const OmLoading(message: 'Loading tickets…');
            if (controller.tickets.isEmpty) {
              return const OmEmptyState(
                title: 'No tickets yet',
                message: 'Anything you send the store shows up here with its replies.',
                icon: Icons.support_agent_outlined,
                compact: true,
              );
            }
            return Column(
              children: <Widget>[
                for (final ticket in controller.tickets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: OmSpacing.md),
                    child: _TicketCard(ticket: ticket, controller: controller),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.controller});

  final SupportRequest ticket;
  final SupportController controller;

  (String, OmTone) get _status => switch (ticket.status) {
        SupportStatus.open => ('Open', OmTone.info),
        SupportStatus.inProgress => ('In progress', OmTone.gold),
        SupportStatus.awaitingCustomer => ('Waiting on you', OmTone.warning),
        SupportStatus.resolved => ('Resolved', OmTone.success),
        SupportStatus.closed => ('Closed', OmTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusTone) = _status;
    final replyFailure = controller.replyFailure.value;
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: OmText(ticket.subject, variant: OmTextVariant.bodyStrong)),
              OmBadge(label: statusLabel, tone: statusTone, dense: true),
            ],
          ),
          const SizedBox(height: OmSpacing.xs),
          OmText(
            '${ticket.topic.code} · opened ${OmDates.date(ticket.createdAt)}'
            '${ticket.orderId.isEmpty ? '' : ' · order ${ticket.orderId}'}',
            variant: OmTextVariant.caption,
          ),
          const SizedBox(height: OmSpacing.sm),
          for (final message in ticket.messages.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    message.isStaff ? Icons.support_agent : Icons.person_outline,
                    size: 15,
                    color: context.omText.muted.color,
                  ),
                  const SizedBox(width: OmSpacing.sm),
                  Expanded(
                    child: OmText(
                      '${message.from}: ${message.body}',
                      variant: OmTextVariant.muted,
                      overflow: TextOverflow.visible,
                      maxLines: 4,
                    ),
                  ),
                ],
              ),
            ),
          if (ticket.messages.length > 4)
            OmText('+${ticket.messages.length - 4} older replies',
                variant: OmTextVariant.caption),
          if (ticket.isOpen || ticket.status == SupportStatus.awaitingCustomer) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'Reply',
              controller: controller.reply,
              maxLines: 3,
              minLines: 2,
            ),
            if (replyFailure != null)
              OmText(replyFailure.message,
                  variant: OmTextVariant.caption, color: OmColors.danger),
            const SizedBox(height: OmSpacing.sm),
            OmButton(
              label: 'Send reply',
              variant: OmButtonVariant.secondary,
              size: OmButtonSize.small,
              loading: controller.busy.value,
              onPressed: () => controller.replyTo(ticket),
            ),
          ],
        ],
      ),
    );
  }
}
