import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/reviews/reviews_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// Moderation queue: approve / reject with a note, verified-purchase indicator.
///
/// Rejecting needs a reason because it is stored on the review and lands in the audit log, so the
/// screen routes it through [omPromptForReason] rather than a bare confirm.
final class ReviewsView extends StatelessWidget {
  const ReviewsView({super.key});

  @override
  Widget build(BuildContext context) => AdminScaffold(
        title: 'Reviews',
        child: Obx(() {
          final controller = Get.find<ReviewsController>();
          final rows = controller.queue;
          return OmAdminPanel<Review>(
            isLoading: controller.isLoading.value,
            hasLoaded: controller.hasLoaded.value,
            failure: controller.failure.value,
            isEmpty: rows.isEmpty,
            onRetry: controller.load,
            empty: OmEmptyState(
              icon: Icons.rate_review_outlined,
              title: 'Nothing in the ${reviewStatusLabel(controller.statusFilter.value).toLowerCase()} queue',
              message: 'Switch the status filter to see other reviews.',
            ),
            builder: (context) => OmAdminPage(
              title: 'Review moderation',
              eyebrow: 'Community',
              subtitle: 'A rating is only trusted if the reviewer actually received the product — '
                  'that flag is derived server-side from a delivered order and shown here.',
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
                  OmAdminFilterBar(
                    children: <Widget>[
                      Wrap(
                        spacing: OmSpacing.xs,
                        runSpacing: OmSpacing.xs,
                        children: <Widget>[
                          for (final status in const <ReviewStatus>[
                            ReviewStatus.pending,
                            ReviewStatus.published,
                            ReviewStatus.hidden,
                            ReviewStatus.rejected,
                          ])
                            OmFilterChip(
                              label: reviewStatusLabel(status),
                              selected: controller.statusFilter.value == status,
                              onTap: () => controller.applyStatus(status),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: OmSpacing.lg),
                  for (final review in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: OmSpacing.md),
                      child: _ReviewCard(controller: controller, review: review),
                    ),
                ],
              ),
            ),
          );
        }),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.controller, required this.review});

  final ReviewsController controller;
  final Review review;

  Future<void> _approve(BuildContext context) async {
    final note = await omPromptForReason(
          context: context,
          label: 'Internal note (optional)',
          title: 'Approve this review?',
          required: false,
        ) ??
        '';
    await controller.decide(review, ReviewStatus.published, note);
  }

  Future<void> _reject(BuildContext context) async {
    final note = await omPromptForReason(
      context: context,
      label: 'Reason for rejecting (required — stored and audited)',
      title: 'Reject this review?',
    );
    if (note == null) return;
    await controller.decide(review, ReviewStatus.rejected, note);
  }

  @override
  Widget build(BuildContext context) => OmAdminRowCard(
        title: review.title.trim().isEmpty ? '(no title)' : review.title,
        badges: <Widget>[
          reviewBadge(review.status),
          if (review.isVerifiedPurchase)
            const OmBadge(
              label: 'Verified purchase',
              tone: OmTone.success,
              icon: Icons.verified_outlined,
              dense: true,
            )
          else
            const OmBadge(label: 'Unverified', tone: OmTone.neutral, dense: true),
          if (review.isFlagged)
            OmBadge(
              label: 'Reported ${review.reportCount}×',
              tone: OmTone.danger,
              dense: true,
            ),
        ],
        lines: <String>[
          '${'★' * review.rating}${'☆' * (5 - review.rating)} · '
              '${AdminFormat.missing(review.authorName, placeholder: 'anonymous')}',
          'Product ${AdminFormat.missing(review.productId)}'
              '${review.orderId.isEmpty ? '' : ' · order ${review.orderId}'}',
          if (review.body.trim().isNotEmpty) review.body,
          if (review.moderatorNote.trim().isNotEmpty) 'Note: ${review.moderatorNote}',
          if (review.createdAt != null) AdminFormat.dateTime(review.createdAt),
        ],
        actions: review.status == ReviewStatus.pending
            ? <Widget>[
                OmButton(
                  label: 'Approve',
                  size: OmButtonSize.small,
                  icon: Icons.check,
                  onPressed: () => _approve(context),
                ),
                OmButton(
                  label: 'Reject',
                  size: OmButtonSize.small,
                  variant: OmButtonVariant.danger,
                  icon: Icons.close,
                  onPressed: () => _reject(context),
                ),
              ]
            : <Widget>[
                OmButton(
                  label: 'Publish',
                  size: OmButtonSize.small,
                  variant: OmButtonVariant.secondary,
                  onPressed: () => controller.decide(review, ReviewStatus.published, ''),
                ),
                OmButton(
                  label: 'Hide',
                  size: OmButtonSize.small,
                  variant: OmButtonVariant.ghost,
                  onPressed: () => controller.decide(review, ReviewStatus.hidden, ''),
                ),
              ],
      );
}
