import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/media/om_image_picker_field.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/reviews/review_controller.dart';

/// `/review/:productId` — write or amend the buyer's own review for one product.
///
/// `Review.isVerifiedPurchase` is displayed, never asserted: the submission carries an optional
/// order id and the Cloud Function decides whether that purchase is verified.
final class ReviewComposeView extends GetView<ReviewComposeController> {
  const ReviewComposeView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Write a review',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.lg),
        child: Obx(() {
          if (controller.loading.value && controller.product.value == null) {
            return const OmLoading(message: 'Loading the product…');
          }
          final product = controller.product.value;
          if (product == null) {
            return OmErrorState(
              failure: controller.failure.value ??
                  const NotFoundFailure('This product is no longer in the catalogue.'),
              onRetry: controller.load,
            );
          }

          return OmContentWidth(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ProductHeader(
                  imageUrl: product.primaryImage,
                  name: product.name,
                  sku: product.sku,
                  slug: product.pathSlug,
                ),
                const SizedBox(height: OmSpacing.lg),
                if (controller.done.value)
                  _SubmittedCard(
                    review: controller.existing.value,
                    autoPublish: Get.isRegistered<SettingsStore>()
                        ? Get.find<SettingsStore>().value.autoPublishReviews
                        : false,
                  )
                else
                  _ComposeForm(controller: controller, productId: product.id),
                const SizedBox(height: OmSpacing.xl),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({
    required this.imageUrl,
    required this.name,
    required this.sku,
    required this.slug,
  });

  final MediaRef? imageUrl;
  final String name;
  final String sku;
  final String slug;

  @override
  Widget build(BuildContext context) => OmCard(
        child: Row(
          children: <Widget>[
            SizedBox(
              height: 64,
              width: 64,
              child: OmMediaImage(ref: imageUrl),
            ),
            const SizedBox(width: OmSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OmText(name, variant: OmTextVariant.h3),
                  if (sku.isNotEmpty)
                    OmText('SKU $sku', variant: OmTextVariant.caption),
                ],
              ),
            ),
            OmButton(
              label: 'Open',
              variant: OmButtonVariant.ghost,
              size: OmButtonSize.small,
              onPressed: () => Get.toNamed<dynamic>(OmRoutes.forProduct(slug)),
            ),
          ],
        ),
      );
}

class _ComposeForm extends StatelessWidget {
  const _ComposeForm({required this.controller, required this.productId});

  final ReviewComposeController controller;
  final String productId;

  @override
  Widget build(BuildContext context) => Obx(() {
    final failure = controller.failure.value;
    final existing = controller.existing.value;
    return OmCard(
      elevated: true,
      child: Form(
        key: controller.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmSectionHeader(
              title: existing == null ? 'How was it?' : 'Update your review',
              subtitle: 'Other wholesale buyers rely on specifics: pack quality, count accuracy, '
                  'how it travelled.',
            ),
            const SizedBox(height: OmSpacing.md),
            if (existing != null) ...<Widget>[
              OmCard(
                padding: const EdgeInsets.all(OmSpacing.sm),
                borderColor: OmColors.info,
                child: OmText(
                  'Your existing review is shown here with status '
                  '${existing.status.code}. Saving replaces it.',
                  variant: OmTextVariant.caption,
                  overflow: TextOverflow.visible,
                ),
              ),
              const SizedBox(height: OmSpacing.md),
            ],
            OmStarInput(
              rating: controller.rating.value,
              onChanged: controller.setRating,
            ),
            const SizedBox(height: OmSpacing.md),
            if (controller.deliveredOrders.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: OmSpacing.sm),
                child: OmBadge(
                  label: 'Delivered order found — the store can mark this verified',
                  tone: OmTone.success,
                  icon: Icons.verified,
                ),
              ),
            OmTextField(
              label: 'Headline (optional)',
              controller: controller.title,
              maxLength: 80,
              hint: 'Balloon pack held up all night',
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'Your review',
              controller: controller.body,
              maxLines: 6,
              minLines: 3,
              maxLength: Review.maxBodyLength,
              validator: controller.validateBody,
              helper: 'Up to ${Review.maxBodyLength} characters.',
            ),
            const SizedBox(height: OmSpacing.md),
            if (controller.deliveredOrders.isNotEmpty) ...<Widget>[
              OmDropdown<String>(
                label: 'Attach one of your delivered orders',
                value: controller.linkedOrderId.value,
                items: controller.deliveredOrders.map((order) => order.id).toList(),
                itemLabel: (id) {
                  final order = controller.deliveredOrders.firstWhere((o) => o.id == id);
                  return '${order.orderNumber} · ${order.items.length} line(s)';
                },
                hint: 'None — leave the review unverified',
                onChanged: controller.pickOrder,
              ),
              const SizedBox(height: OmSpacing.md),
            ],
            OmImagePickerField(
              label: 'Photo of what you received (optional)',
              kind: MediaKind.review,
              ownerId: controller.profile?.uid ?? 'guest',
              entityKey: productId,
              existing: controller.photo.value,
              defaultAltText: 'Customer photo for this product',
              onChanged: (ref, _) => controller.setPhoto(ref),
            ),
            const SizedBox(height: OmSpacing.lg),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                OmButton(
                  label: existing == null ? 'Submit review' : 'Save changes',
                  loading: controller.busy.value,
                  busyLabel: 'Sending…',
                  onPressed: controller.canSubmit ? controller.submit : null,
                ),
                OmButton(
                  label: 'Back to the product',
                  variant: OmButtonVariant.secondary,
                  onPressed: () => Get.back<dynamic>(),
                ),
              ],
            ),
            if (!controller.canSubmit && !controller.busy.value)
              const Padding(
                padding: EdgeInsets.only(top: OmSpacing.sm),
                child: OmText('Pick a star rating to enable the submit button.',
                    variant: OmTextVariant.caption),
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
            const OmText(
              'Reviews are read by the store before they go public, and the purchase check is '
              'theirs to make — this page only records what you write.',
              variant: OmTextVariant.caption,
              overflow: TextOverflow.visible,
            ),
          ],
        ),
      ),
    );
      });
}

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({required this.review, required this.autoPublish});

  final Review? review;
  final bool autoPublish;

  @override
  Widget build(BuildContext context) {
    final status = review?.status ?? ReviewStatus.pending;
    final note = review?.moderatorNote ?? '';
    return OmCard(
      elevated: true,
      borderColor: OmColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OmText(
            status == ReviewStatus.published ? 'Your review is live' : 'Thanks — review received',
            variant: OmTextVariant.h3,
          ),
          const SizedBox(height: OmSpacing.sm),
          Row(
            children: <Widget>[
              if (review != null) OmStarDisplay(rating: review!.rating),
              const SizedBox(width: OmSpacing.sm),
              if (review?.isVerifiedPurchase ?? false)
                const OmBadge(
                    label: 'Verified purchase', tone: OmTone.success, icon: Icons.verified),
            ],
          ),
          const SizedBox(height: OmSpacing.md),
          OmText(
            switch (status) {
              ReviewStatus.published => 'It is showing on the product page now.',
              ReviewStatus.pending => autoPublish
                  ? 'This store publishes automatically, so your review should appear within a '
                      'minute or two.'
                  : 'It is waiting in the moderation queue. The store publishes it after a read, '
                      'so nothing you wrote is visible yet.',
              ReviewStatus.rejected => 'The store declined this review'
                  '${note.isEmpty ? ' without leaving a note.' : ' with this note: $note.'}',
              ReviewStatus.hidden => 'This review is hidden from the product page. Contact the '
                  'support desk if you believe that is a mistake.',
            },
            variant: OmTextVariant.muted,
            overflow: TextOverflow.visible,
          ),
          const SizedBox(height: OmSpacing.lg),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              OmButton(
                label: 'Support desk',
                variant: OmButtonVariant.secondary,
                onPressed: () => Get.toNamed<dynamic>(OmRoutes.accountSupport),
              ),
              OmButton(
                label: 'Back to the product',
                variant: OmButtonVariant.ghost,
                onPressed: () => Get.back<dynamic>(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Five stars, keyboard- and screen-reader-labelled. Never colour-only: an unfilled star is a
/// shape, not just a different hue.
final class OmStarInput extends StatelessWidget {
  const OmStarInput({super.key, required this.rating, required this.onChanged, this.size = 34});

  final int rating;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: rating == 0 ? 'Choose a rating out of 5 stars' : 'Rated $rating out of 5 stars',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var star = 1; star <= 5; star++)
              InkWell(
                onTap: () => onChanged(star),
                child: Padding(
                  padding: const EdgeInsets.only(right: OmSpacing.xs),
                  child: Icon(
                    star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: size,
                    color: star <= rating ? OmColors.gold : OmColors.textMuted,
                  ),
                ),
              ),
            const SizedBox(width: OmSpacing.sm),
            OmText(rating == 0 ? 'Tap a star' : '$rating / 5', variant: OmTextVariant.bodyStrong),
          ],
        ),
      );
}

/// Read-only form of the same control.
final class OmStarDisplay extends StatelessWidget {
  const OmStarDisplay({super.key, required this.rating, this.readOnly = true});

  final int rating;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$rating out of 5 stars',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var star = 1; star <= 5; star++)
              Icon(
                star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18,
                color: star <= rating ? OmColors.gold : OmColors.textMuted,
              ),
          ],
        ),
      );
}
