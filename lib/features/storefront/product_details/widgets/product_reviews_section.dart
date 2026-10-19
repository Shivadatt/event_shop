import 'package:flutter/material.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/features/storefront/common/om_dates.dart';

/// Read-only review summary for the product page: rating histogram, verified-purchase list and
/// the moderation notice that explains why a just-submitted review may not appear yet.
final class ProductReviewsSection extends StatelessWidget {
  const ProductReviewsSection({
    super.key,
    required this.reviews,
    required this.breakdown,
    required this.autoPublish,
    this.onWriteReview,
    this.canWrite = false,
  });

  final List<Review> reviews;
  final RatingBreakdown? breakdown;
  final bool autoPublish;
  final VoidCallback? onWriteReview;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summary = breakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OmSectionHeader(
          eyebrow: 'Customer feedback',
          title: 'Reviews',
          action: canWrite ? (onWriteReview == null ? null : 'Write a review') : null,
          onActionTap: onWriteReview,
        ),
        const SizedBox(height: OmSpacing.md),
        if (summary == null || summary.total == 0)
          const OmCard(
            child: OmText(
              'No published reviews yet. Verified buyers can be the first to review this product '
              'after their order is delivered.',
              variant: OmTextVariant.muted,
              maxLines: 3,
              overflow: TextOverflow.visible,
            ),
          )
        else ...<Widget>[
          OmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      summary.average.toStringAsFixed(1),
                      style: styles.h2,
                    ),
                    const SizedBox(width: OmSpacing.sm),
                    _Stars(rating: summary.average),
                    const SizedBox(width: OmSpacing.sm),
                    OmText('${summary.total} reviews', variant: OmTextVariant.caption),
                  ],
                ),
                const SizedBox(height: OmSpacing.md),
                for (var star = 5; star >= 1; star--)
                  Padding(
                    padding: const EdgeInsets.only(bottom: OmSpacing.xs),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 34,
                          child: OmText('$star ★', variant: OmTextVariant.caption),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: OmRadius.pillAll,
                            child: LinearProgressIndicator(
                              value: summary.fractionFor(star),
                              minHeight: 8,
                              backgroundColor: isDark
                                  ? OmColors.surfaceElevated
                                  : OmColors.cream,
                              valueColor: const AlwaysStoppedAnimation<Color>(OmColors.gold),
                            ),
                          ),
                        ),
                        const SizedBox(width: OmSpacing.sm),
                        SizedBox(
                          width: 28,
                          child: OmText(
                            '${summary.countFor(star)}',
                            variant: OmTextVariant.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: OmSpacing.md),
          for (final review in reviews)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.sm),
              child: _ReviewTile(review: review),
            ),
          if (!autoPublish) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            const OmText(
              'New reviews are checked by the store team before they appear here.',
              variant: OmTextVariant.caption,
            ),
          ],
        ],
      ],
    );
  }
}

final class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OmText(
                  review.authorName.isEmpty ? 'Verified buyer' : review.authorName,
                  variant: OmTextVariant.bodyStrong,
                ),
              ),
              if (review.isVerifiedPurchase)
                const OmBadge(label: 'Verified purchase', tone: OmTone.info, dense: true),
            ],
          ),
          const SizedBox(height: OmSpacing.xs),
          Row(
            children: <Widget>[
              _Stars(rating: review.rating.toDouble()),
              if (review.createdAt != null) ...<Widget>[
                const SizedBox(width: OmSpacing.sm),
                OmText(OmDates.date(review.createdAt!), variant: OmTextVariant.caption),
              ],
            ],
          ),
          if (review.title.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            OmText(review.title, variant: OmTextVariant.bodyStrong),
          ],
          if (review.body.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.xs),
            OmText(
              review.body,
              maxLines: 6,
              selectable: true,
            ),
          ],
        ],
      ),
    );
  }
}

final class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rated ${rating.toStringAsFixed(1)} out of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var star = 1; star <= 5; star++)
            Icon(
              rating >= star
                  ? Icons.star
                  : (rating >= star - 0.5 ? Icons.star_half : Icons.star_border),
              size: 16,
              color: OmColors.gold,
            ),
        ],
      ),
    );
  }
}
