import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/widgets/media/media_editor_state.dart';
import 'package:om_events/app/core/widgets/media/om_media_item_tile.dart';
import 'package:om_events/app/core/widgets/media/om_media_storage_notice.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/repositories/media_repository.dart';

/// Single-image field: a category tile, a banner, one review photo.
///
/// The field owns its [MediaEditorController] so a form only has to read [onChanged]; it never
/// touches Supabase or Firestore itself. When media is not configured it shows the exact reason and
/// a disabled control instead of a button that fails on click.
final class OmImagePickerField extends StatefulWidget {
  const OmImagePickerField({
    super.key,
    required this.label,
    required this.kind,
    required this.ownerId,
    this.existing,
    this.entityKey,
    this.attachmentCollection = '',
    this.defaultAltText = '',
    this.repository,
    this.onChanged,
  });

  final String label;
  final MediaKind kind;
  final String ownerId;
  final MediaRef? existing;

  /// Slug or document id the object should live under.
  final String? entityKey;
  final String attachmentCollection;
  final String defaultAltText;
  final MediaRepository? repository;

  /// Called with the single reference (or null) and any reference the admin removed.
  final void Function(MediaRef? ref, MediaRef? removed)? onChanged;

  @override
  State<OmImagePickerField> createState() => _OmImagePickerFieldState();
}

class _OmImagePickerFieldState extends State<OmImagePickerField> {
  MediaEditorController? _editor;

  @override
  void initState() {
    super.initState();
    _editor = _create();
  }

  @override
  void didUpdateWidget(covariant OmImagePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameImage = oldWidget.existing?.id == widget.existing?.id &&
        oldWidget.existing?.storagePath == widget.existing?.storagePath;
    if (!sameImage || oldWidget.ownerId != widget.ownerId) {
      _editor?.dispose();
      _editor = _create();
    }
  }

  MediaEditorController? _create() {
    final repository = widget.repository;
    if (repository == null && !Get.isRegistered<MediaRepository>()) return null;
    return MediaEditorController(
      kind: widget.kind,
      ownerId: widget.ownerId,
      existing: widget.existing == null ? const <MediaRef>[] : <MediaRef>[widget.existing!],
      entityKey: widget.entityKey,
      attachmentCollection: widget.attachmentCollection,
      defaultAltText: widget.defaultAltText,
      repository: repository,
    )..addListener(_emit);
  }

  void _emit() {
    final editor = _editor;
    if (editor == null) return;
    final refs = editor.publishableRefs;
    final removed = editor.removedRefs;
    widget.onChanged?.call(
      refs.isEmpty ? null : refs.first,
      removed.isEmpty ? null : removed.first,
    );
  }

  @override
  void dispose() {
    _editor
      ?..removeListener(_emit)
      ..dispose();
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
    if (!editor.isConfigured) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.label, style: styles.bodyStrong),
          const SizedBox(height: OmSpacing.sm),
          OmMediaStorageNotice(compact: true, message: editor.statusMessage),
        ],
      );
    }

    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final items = editor.items;
        final current = items.isEmpty ? null : items.first;
        return OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(widget.label, style: styles.bodyStrong)),
                  OmBadge(
                    label: current == null ? 'Empty' : _statusOf(current),
                    tone: current == null ? OmTone.neutral : _toneOf(current),
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.xs),
              Text(
                '${widget.kind.code}: ${editor.rulesSummary}. '
                'Formats: JPEG, PNG, WebP, AVIF. '
                'Landing under ${editor.entityKey ?? editor.ownerId}.',
                style: styles.caption,
              ),
              if (editor.notice != null) ...<Widget>[
                const SizedBox(height: OmSpacing.sm),
                Text(editor.notice!, style: styles.muted),
              ],
              if (current != null) ...<Widget>[
                const SizedBox(height: OmSpacing.sm),
                // Upload, retry, cancel, replace and remove all live on the tile, so a single field
                // and a gallery cannot offer different affordances for the same state.
                OmMediaItemTile(item: current, controller: editor),
              ] else ...<Widget>[
                const SizedBox(height: OmSpacing.md),
                OmButton(
                  label: 'Choose image',
                  icon: Icons.add_photo_alternate_outlined,
                  variant: OmButtonVariant.outline,
                  onPressed: editor.canAddMore ? () => editor.addFromPicker() : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _statusOf(MediaItem item) => switch (item.status) {
        MediaItemStatus.staged => 'Ready to upload',
        MediaItemStatus.rejected => 'Rejected',
        MediaItemStatus.uploading => 'Uploading',
        MediaItemStatus.published => 'Saved image',
        MediaItemStatus.failed => 'Failed',
        MediaItemStatus.cancelled => 'Cancelled',
      };

  static OmTone _toneOf(MediaItem item) => switch (item.status) {
        MediaItemStatus.staged => OmTone.gold,
        MediaItemStatus.rejected => OmTone.warning,
        MediaItemStatus.uploading => OmTone.info,
        MediaItemStatus.published => OmTone.success,
        MediaItemStatus.failed => OmTone.danger,
        MediaItemStatus.cancelled => OmTone.neutral,
      };
}

/// Small helper for forms that want the limit in their own helper text.
String omMediaLimitHint(MediaKind kind) => MediaLimits.rulesFor(kind).describe();
