import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';
import 'package:om_events/features/admin/wholesale/wholesale_controller.dart';

/// Wholesale applications: the queue, a detail view, and approve / reject.
final class WholesaleView extends StatelessWidget {
  const WholesaleView({super.key});

  @override
  Widget build(BuildContext context) => AdminScaffold(
        title: 'Wholesale',
        child: Obx(() {
          final controller = Get.find<WholesaleController>();
          final rows = controller.applications;
          return OmAdminPanel<WholesaleApplication>(
            isLoading: controller.isLoading.value,
            hasLoaded: controller.hasLoaded.value,
            failure: controller.failure.value,
            isEmpty: rows.isEmpty,
            onRetry: controller.load,
            empty: OmEmptyState(
              icon: Icons.groups_outlined,
              title: controller.openOnly.value
                  ? 'No pending applications'
                  : 'No applications to show',
              message: 'New wholesale requests land here for review.',
            ),
            builder: (context) => OmAdminPage(
              title: 'Wholesale applications',
              eyebrow: 'Trade',
              actions: <Widget>[
                OmButton(
                  label: 'Reload',
                  variant: OmButtonVariant.ghost,
                  size: OmButtonSize.small,
                  icon: Icons.refresh,
                  onPressed: controller.load,
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const OmAdminNotice(
                    tone: OmTone.gold,
                    icon: Icons.workspace_premium_outlined,
                    title: 'Approval here is the only path to wholesale pricing',
                    message: 'A customer cannot grant themselves trade prices, and no form on this '
                        'site sets a user role. Only an APPROVE decision below — executed by the '
                        'wholesale-decision function, which re-checks your staff role server-side — '
                        'turns on wholesale pricing for an account.',
                  ),
                  const SizedBox(height: OmSpacing.lg),
                  OmAdminFilterBar(
                    children: <Widget>[
                      Wrap(
                        spacing: OmSpacing.xs,
                        children: <Widget>[
                          OmFilterChip(
                            label: 'Open only',
                            selected: controller.openOnly.value,
                            onTap: () => controller.applyOpenOnly(true),
                          ),
                          OmFilterChip(
                            label: 'All',
                            selected: !controller.openOnly.value,
                            onTap: () => controller.applyOpenOnly(false),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: OmSpacing.lg),
                  for (final application in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: OmSpacing.md),
                      child: _ApplicationCard(controller: controller, application: application),
                    ),
                ],
              ),
            ),
          );
        }),
      );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.controller, required this.application});

  final WholesaleController controller;
  final WholesaleApplication application;

  Future<void> _approve(BuildContext context) async {
    final confirmed = await omConfirmAdminAction(
      context: context,
      title: 'Approve ${application.companyName}?',
      message: 'This grants wholesale pricing to the account. The decision function re-checks your '
          'role and records the audit row; nothing here sets the price or the role directly.',
      confirmLabel: 'Approve',
    );
    if (!confirmed || !context.mounted) return;
    final note = await omPromptForReason(
          context: context,
          label: 'Note to the applicant (optional)',
          title: 'Approval note',
          required: false,
        ) ??
        '';
    await controller.decide(application, true, note);
  }

  Future<void> _reject(BuildContext context) async {
    final note = await omPromptForReason(
      context: context,
      label: 'Reason for rejecting (required — stored and audited)',
      title: 'Reject ${application.companyName}?',
    );
    if (note == null) return;
    await controller.decide(application, false, note);
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      OmAdminMeta(label: 'COMPANY', value: application.companyName, emphasise: true),
      OmAdminMeta(label: 'CONTACT', value: application.contactName),
      OmAdminMeta(label: 'PHONE', value: application.phone),
      OmAdminMeta(label: 'EMAIL', value: AdminFormat.missing(application.email)),
      OmAdminMeta(label: 'GST', value: AdminFormat.missing(application.gstNumber)),
      OmAdminMeta(
        label: 'ADDRESS',
        value: AdminFormat.missing(
          <String>[
            application.address,
            application.city,
            application.state,
            application.pincode,
          ].where((s) => s.trim().isNotEmpty).join(', '),
        ),
      ),
      OmAdminMeta(label: 'EXPECTED VOLUME', value: AdminFormat.missing(application.expectedMonthlyVolume)),
      OmAdminMeta(label: 'UID', value: application.uid, selectable: true),
      if (application.reason.trim().isNotEmpty)
        OmAdminMeta(label: 'STATED REASON', value: application.reason),
      if (application.reviewNote.trim().isNotEmpty)
        OmAdminMeta(label: 'REVIEW NOTE', value: application.reviewNote),
    ];
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OmText(
                  application.companyName,
                  variant: OmTextVariant.h3,
                  maxLines: 2,
                ),
              ),
              wholesaleBadge(application.status),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          OmText(
            'Applied ${AdminFormat.dateTime(application.createdAt)}'
            '${application.reviewedAt == null ? '' : ' · reviewed ${AdminFormat.dateTime(application.reviewedAt)}'}',
            variant: OmTextVariant.caption,
          ),
          const SizedBox(height: OmSpacing.md),
          OmAdminMetaRow(entries: fields),
          if (application.isOpen) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                OmButton(
                  label: 'Approve',
                  icon: Icons.check,
                  size: OmButtonSize.small,
                  onPressed: () => _approve(context),
                ),
                OmButton(
                  label: 'Reject',
                  variant: OmButtonVariant.danger,
                  icon: Icons.close,
                  size: OmButtonSize.small,
                  onPressed: () => _reject(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
