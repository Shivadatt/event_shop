import 'package:flutter/material.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/widgets/media/media_editor_state.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

/// One row of an admin media editor: preview, alt text, live status and the actions that are legal
/// for that status.
///
/// Both media fields compose from this tile, so a single-image picker and a ten-image gallery can
/// not disagree about what "uploading" looks like or which button appears next to a failed upload.
final class OmMediaItemTile extends StatefulWidget {
  const OmMediaItemTile({
    super.key,
    required this.item,
    required this.controller,
    this.index = 0,
    this.count = 1,
    this.showReorder = false,
  });

  final MediaItem item;
  final MediaEditorController controller;
  final int index;
  final int count;
  final bool showReorder;

  @override
  State<OmMediaItemTile> createState() => _OmMediaItemTileState();
}

class _OmMediaItemTileState extends State<OmMediaItemTile> {
  late final TextEditingController _alt;
  final FocusNode _altFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _alt = TextEditingController(text: widget.item.altText);
  }

  @override
  void didUpdateWidget(covariant OmMediaItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final item = widget.item;
    // A recycled row (list reorder) must show its own alt text; an untouched field must not have its
    // caret reset by a progress tick arriving from the upload stream.
    if (oldWidget.item.id != item.id) {
      if (_alt.text != item.altText) _alt.text = item.altText;
      return;
    }
    if (!_altFocus.hasFocus && _alt.text != item.altText) _alt.text = item.altText;
  }

  @override
  void dispose() {
    _alt.dispose();
    _altFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final styles = context.omText;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OmSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Preview(item: item, controller: widget.controller),
              const SizedBox(width: OmSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.fileName.isEmpty ? item.id : item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodyStrong,
                    ),
                    const SizedBox(height: OmSpacing.xs),
                    Wrap(
                      spacing: OmSpacing.sm,
                      runSpacing: OmSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        OmBadge(label: _statusLabel(item), tone: _tone(item)),
                        if (widget.showReorder && widget.count > 1)
                          Text(
                            'Position ${widget.index + 1} of ${widget.count}',
                            style: styles.caption,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _Actions(item: item, controller: widget.controller, index: widget.index, count: widget.count, showReorder: widget.showReorder),
            ],
          ),
          if (item.isBusy) ...[
            const SizedBox(height: OmSpacing.sm),
            ClipRRect(
              borderRadius: OmRadius.smAll,
              child: LinearProgressIndicator(
                value: item.progress <= 0 ? null : item.progress,
                minHeight: 5,
              ),
            ),
            const SizedBox(height: OmSpacing.xs),
            Text(
              item.message.isEmpty
                  ? 'Uploading — this client cannot report byte-level progress, only the stage.'
                  : item.message,
              style: styles.caption,
            ),
          ] else if (item.message.isNotEmpty) ...[
            const SizedBox(height: OmSpacing.sm),
            Text(item.message, style: styles.caption, textAlign: TextAlign.start),
          ],
          const SizedBox(height: OmSpacing.sm),
          OmTextField(
            label: 'Alt text',
            controller: _alt,
            focusNode: _altFocus,
            required: true,
            maxLength: MediaLimits.altTextMaxLength,
            hint: 'e.g. Gold balloon arch with LED fairy lights',
            helper: 'Describes the picture for screen readers and image search. '
                '${MediaLimits.altTextMinLength}–${MediaLimits.altTextMaxLength} characters.',
            onChanged: (value) => widget.controller.setAltText(item, value),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(MediaItem item) => switch (item.status) {
        MediaItemStatus.staged => 'Ready to upload',
        MediaItemStatus.rejected => 'Rejected',
        MediaItemStatus.uploading => 'Uploading',
        MediaItemStatus.published => 'Published',
        MediaItemStatus.failed => 'Failed',
        MediaItemStatus.cancelled => 'Cancelled',
      };

  static OmTone _tone(MediaItem item) => switch (item.status) {
        MediaItemStatus.staged => OmTone.gold,
        MediaItemStatus.rejected => OmTone.warning,
        MediaItemStatus.uploading => OmTone.info,
        MediaItemStatus.published => OmTone.success,
        MediaItemStatus.failed => OmTone.danger,
        MediaItemStatus.cancelled => OmTone.neutral,
      };
}

/// 88x88 preview: the picked bytes before upload, the CDN variant after.
final class _Preview extends StatelessWidget {
  const _Preview({required this.item, required this.controller});

  final MediaItem item;
  final MediaEditorController controller;

  @override
  Widget build(BuildContext context) {
    final bytes = item.bytes;
    final url = item.displayUrl;

    return Container(
      height: 88,
      width: 88,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: OmRadius.smAll,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              isComplex: false,
              filterQuality: FilterQuality.low,
              semanticLabel: item.altText.isEmpty ? item.fileName : item.altText,
              errorBuilder: (context, error, stack) =>
                  const _Fallback(label: 'No preview'),
            )
          : url.isEmpty
              ? const _Fallback(label: 'No image')
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: MediaLimits.thumbnailWidth,
                  gaplessPlayback: true,
                  semanticLabel: item.altText.isEmpty ? item.fileName : item.altText,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const _Fallback(label: 'Loading'),
                  errorBuilder: (context, error, stack) =>
                      const _Fallback(label: 'Preview failed'),
                ),
    );
  }
}

final class _Fallback extends StatelessWidget {
  const _Fallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(OmSpacing.xs),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
}

final class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.controller,
    required this.index,
    required this.count,
    required this.showReorder,
  });

  final MediaItem item;
  final MediaEditorController controller;
  final int index;
  final int count;
  final bool showReorder;

  @override
  Widget build(BuildContext context) {
    final busy = item.isBusy;
    return Wrap(
      spacing: OmSpacing.xs,
      runSpacing: OmSpacing.xs,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (showReorder && count > 1) ...<Widget>[
          OmIconButton(
            icon: Icons.arrow_upward,
            tooltip: 'Move earlier',
            size: 44,
            onPressed: index == 0 ? null : () => controller.move(index, index - 1),
          ),
          OmIconButton(
            icon: Icons.arrow_downward,
            tooltip: 'Move later',
            size: 44,
            onPressed: index >= count - 1 ? null : () => controller.move(index, index + 1),
          ),
        ],
        if (item.isPublished)
          OmIconButton(
            icon: controller.isPrimary(item) ? Icons.star : Icons.star_border,
            tooltip: controller.isPrimary(item) ? 'Primary image' : 'Make primary',
            size: 44,
            selected: controller.isPrimary(item),
            onPressed: busy ? null : () => controller.setPrimary(item),
          ),
        if (item.isPublished && !busy)
          OmIconButton(
            icon: Icons.swap_horiz,
            tooltip: 'Replace this image, keeping its address',
            size: 44,
            onPressed: () => controller.replaceFromPicker(item),
          ),
        if (item.status == MediaItemStatus.staged && !busy)
          OmButton(
            label: 'Upload',
            size: OmButtonSize.small,
            variant: OmButtonVariant.outline,
            onPressed: () => controller.upload(item),
          ),
        if (item.canRetry)
          OmButton(
            label: 'Retry',
            size: OmButtonSize.small,
            variant: OmButtonVariant.outline,
            onPressed: () => controller.retry(item),
          ),
        if (busy)
          OmButton(
            label: 'Cancel',
            size: OmButtonSize.small,
            variant: OmButtonVariant.ghost,
            onPressed: () => controller.cancel(item),
          ),
        if (!busy)
          OmIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove from this ${item.ref == null ? 'upload' : 'product'}',
            size: 44,
            onPressed: () => controller.remove(item),
          ),
      ],
    );
  }
}
