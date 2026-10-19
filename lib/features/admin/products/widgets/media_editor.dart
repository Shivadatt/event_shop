import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/features/admin/products/products_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_files.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Image list for one product: upload, reorder, mark primary, and the alt text that must exist
/// before the list can be committed.
///
/// Alt text is a field, not a hint, because `MediaRef.altText` is what an screen reader announces
/// and `commitProductImages` is expected to refuse a list containing an empty one. The whole panel
/// degrades to a disabled state with an explanation when the media repository reports
/// `isConfigured == false` — a button that throws a `MediaFailure` on click would look like an
/// operator error rather than an unconfigured deployment.
final class OmProductMediaEditor extends StatelessWidget {
  const OmProductMediaEditor({super.key, required this.controller, required this.product});

  final ProductEditController controller;
  final Product product;

  Future<void> _pick(BuildContext context) async {
    final files = await AdminFiles.pickImages();
    if (files.isEmpty || !context.mounted) return;
    final alt = await omPromptForAltText(context, count: files.length);
    if (alt == null || !context.mounted) return;
    await controller.uploadImages(files: files, altText: alt);
  }

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Images',
        subtitle: 'The first position is the card image on the shop front. Alt text is required on '
            'every image before the list can be saved.',
        spaceAbove: 0,
        child: Obx(() {
          final images = product.images;
          final missingAlt = images.where((i) => i.altText.trim().isEmpty).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!controller.mediaConfigured)
                const OmAdminNotice(
                  tone: OmTone.warning,
                  icon: Icons.cloud_off,
                  title: 'Media storage is not configured',
                  message: 'Uploads are disabled because the storage bucket has no credentials in '
                      'this build. Names, prices and slabs can still be saved, and the existing '
                      'image references below stay intact.',
                )
              else if (images.isEmpty)
                const OmCard(
                  child: OmEmptyState(
                    compact: true,
                    icon: Icons.add_photo_alternate_outlined,
                    title: 'No images yet',
                    message: 'A product without an image shows the "no image" placeholder on the '
                        'shop front.',
                  ),
                )
              else
                for (var index = 0; index < images.length; index++)
                  _MediaRow(
                    key: ValueKey<int>(index),
                    index: index,
                    total: images.length,
                    ref: images[index],
                    controller: controller,
                  ),
              const SizedBox(height: OmSpacing.md),
              Wrap(
                spacing: OmSpacing.sm,
                runSpacing: OmSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  OmButton(
                    label: 'Upload images',
                    icon: Icons.upload_outlined,
                    variant: OmButtonVariant.secondary,
                    loading: controller.uploading.value,
                    onPressed: controller.mediaConfigured && !controller.uploading.value
                        ? () => _pick(context)
                        : null,
                  ),
                  OmButton(
                    label: 'Save image list',
                    icon: Icons.playlist_add_check,
                    // The controller refuses this too; disabling the button is what keeps the
                    // explanation from arriving only after a click.
                    onPressed: images.isEmpty || product.id.isEmpty
                        ? null
                        : controller.commitImages,
                  ),
                  if (missingAlt > 0)
                    OmBadge(
                      tone: OmTone.warning,
                      icon: Icons.accessibility_new,
                      label: '$missingAlt image(s) without alt text',
                    ),
                ],
              ),
              const SizedBox(height: OmSpacing.sm),
              if (product.id.isEmpty)
                const OmText(
                  'This product has no document yet: save it once, then images can be attached to '
                  'its id.',
                  variant: OmTextVariant.caption,
                  maxLines: 2,
                ),
              const SizedBox(height: OmSpacing.sm),
              const OmAdminNotice(
                message: 'Uploads and deletions go through the media repository, which owns the '
                    'object in storage. "Save image list" rewrites the product\'s references and '
                    'lets the same service drop objects that are no longer used; the two steps are '
                    'separate because they have different authorities.',
              ),
            ],
          );
        }),
      );
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    super.key,
    required this.index,
    required this.total,
    required this.ref,
    required this.controller,
  });

  final int index;
  final int total;
  final MediaRef ref;
  final ProductEditController controller;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return OmCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 92,
            width: 92,
            child: ClipRRect(
              borderRadius: OmRadius.smAll,
              child: OmMediaImage(ref: ref),
            ),
          ),
          const SizedBox(width: OmSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    OmText(
                      'Position ${index + 1}',
                      variant: OmTextVariant.label,
                    ),
                    const SizedBox(width: OmSpacing.sm),
                    if (ref.isPrimary)
                      const OmBadge(tone: OmTone.gold, dense: true, label: 'Card image'),
                    const Spacer(),
                    Text(AdminFormat.bytes(ref.sizeBytes), style: styles.caption),
                  ],
                ),
                const SizedBox(height: OmSpacing.sm),
                _AltTextField(
                  key: ValueKey<String>('alt-${ref.id}'),
                  index: index,
                  value: ref.altText,
                  onChanged: (text) => controller.setImageAlt(index, text),
                ),
                const SizedBox(height: OmSpacing.sm),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.xs,
                  children: <Widget>[
                    OmIconButton(
                      icon: Icons.arrow_upward,
                      tooltip: 'Move up',
                      size: 34,
                      onPressed: index == 0 ? null : () => controller.moveImage(index, index - 1),
                    ),
                    OmIconButton(
                      icon: Icons.arrow_downward,
                      tooltip: 'Move down',
                      size: 34,
                      onPressed:
                          index >= total - 1 ? null : () => controller.moveImage(index, index + 1),
                    ),
                    OmButton(
                      label: 'Make card image',
                      size: OmButtonSize.small,
                      variant: OmButtonVariant.ghost,
                      onPressed: ref.isPrimary
                          ? null
                          : () => controller.setPrimary(index),
                    ),
                    OmButton(
                      label: 'Delete',
                      size: OmButtonSize.small,
                      variant: OmButtonVariant.danger,
                      onPressed: () => _confirmDelete(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await omConfirmAdminAction(
      context: context,
      title: 'Delete this image?',
      message: 'The object is removed from storage now. The product keeps its remaining images and '
          'renumbers them, so nothing can point at a deleted object.',
      confirmLabel: 'Delete image',
      destructive: true,
    );
    if (ok) await controller.deleteImage(ref);
  }
}

/// Alt text is stored on the reference, so the field must not hold a second copy of it.
class _AltTextField extends StatefulWidget {
  const _AltTextField({
    super.key,
    required this.index,
    required this.value,
    required this.onChanged,
  });

  final int index;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_AltTextField> createState() => _AltTextFieldState();
}

class _AltTextFieldState extends State<_AltTextField> {
  late final TextEditingController _text = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _AltTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OmTextField(
        label: 'Alt text for position ${widget.index + 1}',
        controller: _text,
        required: true,
        maxLines: 2,
        hint: 'What the image shows, in one sentence',
        helper: 'Required before the image list can be saved.',
        validator: (value) => (value ?? '').trim().isEmpty
            ? 'Alt text is required for screen readers'
            : null,
        onChanged: widget.onChanged,
      );
}

/// Asks for the alt text a batch of uploads shares, and refuses to start the upload without it.
Future<String?> omPromptForAltText(BuildContext context, {required int count}) async {
  final controller = TextEditingController();
  final key = GlobalKey<FormState>();
  var accepted = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(count == 1 ? 'Image alt text' : 'Alt text for $count images'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (dialogContext.screenWidth - 96).clamp(240.0, 460.0)),
        child: Form(
          key: key,
          child: OmTextField(
            label: 'Describe what the images show',
            controller: controller,
            maxLines: 3,
            required: true,
            helper: count == 1
                ? 'Each image can be re-worded after it uploads.'
                : 'Applied to every file in this batch; edit any of them after upload.',
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Alt text is required before an image is stored'
                : null,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        OmButton(
          label: 'Upload',
          onPressed: () {
            if (key.currentState?.validate() ?? false) {
              accepted = true;
              Navigator.of(dialogContext).pop();
            }
          },
        ),
      ],
    ),
  );
  final text = controller.text.trim();
  controller.dispose();
  return accepted ? text : null;
}
