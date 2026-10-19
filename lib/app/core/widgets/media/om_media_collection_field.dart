import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/widgets/media/media_editor_state.dart';
import 'package:om_events/app/core/widgets/media/om_media_item_tile.dart';
import 'package:om_events/app/core/widgets/media/om_media_storage_notice.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/repositories/media_repository.dart';

/// Multi-image field with reordering, one primary marker, per-image alt text and live upload
/// progress — the product gallery editor.
///
/// The widget is stateful only about the editor: the owning form reads [onChanged] and decides when
/// to commit, so a save can never happen while an upload is mid-flight (see [MediaEditorController
/// .blockReason]).
final class OmMediaCollectionField extends StatefulWidget {
  const OmMediaCollectionField({
    super.key,
    required this.label,
    required this.kind,
    required this.ownerId,
    required this.existing,
    this.entityKey,
    this.attachmentCollection = '',
    this.defaultAltText = '',
    this.repository,
    this.onChanged,
  });

  final String label;
  final MediaKind kind;
  final String ownerId;
  final List<MediaRef> existing;
  final String? entityKey;
  final String attachmentCollection;
  final String defaultAltText;
  final MediaRepository? repository;

  /// The ordered gallery plus everything the admin removed since the field was built.
  final void Function(List<MediaRef> refs, List<MediaRef> removed)? onChanged;

  @override
  State<OmMediaCollectionField> createState() => _OmMediaCollectionFieldState();
}

class _OmMediaCollectionFieldState extends State<OmMediaCollectionField> {
  MediaEditorController? _editor;

  @override
  void initState() {
    super.initState();
    _editor = _create();
  }

  @override
  void didUpdateWidget(covariant OmMediaCollectionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId == widget.ownerId &&
        oldWidget.entityKey == widget.entityKey &&
        _sameGallery(oldWidget.existing, widget.existing)) {
      return;
    }
    // The document was reloaded from elsewhere (a save round-trip, a route re-entry). Rebuild the
    // editor rather than merging, because a merged gallery can silently duplicate object paths.
    _editor?.dispose();
    _editor = _create();
  }

  static bool _sameGallery(List<MediaRef> a, List<MediaRef> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id || a[index].storagePath != b[index].storagePath) return false;
    }
    return true;
  }

  MediaEditorController? _create() {
    final repository = widget.repository;
    if (repository == null && !Get.isRegistered<MediaRepository>()) return null;
    return MediaEditorController(
      kind: widget.kind,
      ownerId: widget.ownerId,
      existing: widget.existing,
      entityKey: widget.entityKey,
      attachmentCollection: widget.attachmentCollection,
      defaultAltText: widget.defaultAltText,
      repository: repository,
    )..addListener(_emit);
  }

  void _emit() {
    final editor = _editor;
    if (editor == null) return;
    widget.onChanged?.call(editor.publishableRefs, editor.removedRefs);
  }

  @override
  void dispose() {
    _editor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    final styles = context.omText;

    if (editor == null) {
      return OmMediaStorageNotice(
        title: widget.label,
        message: 'The media repository is not bound for this route, so no image can be uploaded. '
            '${MediaConfig.statusMessage}',
      );
    }

    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) => OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${widget.label} (${editor.itemCount}/${editor.maxItems})',
                    style: styles.bodyStrong,
                  ),
                ),
                if (editor.isBusy)
                  const OmBadge(label: 'Uploading', tone: OmTone.info, dense: true)
                else if (editor.hasBlocked)
                  const OmBadge(label: 'Needs attention', tone: OmTone.warning, dense: true),
              ],
            ),
            const SizedBox(height: OmSpacing.xs),
            Text(
              '${editor.rulesSummary}. Formats: JPEG, PNG, WebP, AVIF. Alt text is mandatory. '
              'First image is the one buyers see on cards.',
              style: styles.caption,
            ),
            // Unconfigured media is a deployment state, not a form error: rows the document already
            // has stay visible, and only the add control is switched off.
            if (!editor.isConfigured) ...<Widget>[
              const SizedBox(height: OmSpacing.md),
              OmMediaStorageNotice(compact: true, message: editor.statusMessage),
            ],
            if (editor.notice != null) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              Text(editor.notice!, style: styles.muted),
            ],
            const SizedBox(height: OmSpacing.sm),
            if (editor.items.isEmpty)
              const OmEmptyState(
                compact: true,
                title: 'No images yet',
                message: 'Products without a picture are skipped by buyers.',
                icon: Icons.add_photo_alternate_outlined,
              )
            else
              for (var index = 0; index < editor.items.length; index++)
                OmMediaItemTile(
                  item: editor.items[index],
                  controller: editor,
                  index: index,
                  count: editor.items.length,
                  showReorder: true,
                ),
            const SizedBox(height: OmSpacing.md),
            OmButton(
              label: 'Add images',
              icon: Icons.add_photo_alternate_outlined,
              variant: OmButtonVariant.outline,
              onPressed:
                  editor.canAddMore && editor.isConfigured ? editor.addFromPicker : null,
            ),
            if (!editor.canAddMore) ...<Widget>[
              const SizedBox(height: OmSpacing.xs),
              Text(
                'Limit reached: this ${widget.kind.code} takes ${editor.maxItems} images.',
                style: styles.caption,
              ),
            ],
            if (editor.blockReason != null) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              Text(editor.blockReason!, style: styles.muted),
            ],
          ],
        ),
      ),
    );
  }
}
