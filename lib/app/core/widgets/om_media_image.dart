import 'package:flutter/material.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/data/models/media_ref.dart';

/// Renders a Supabase-hosted product image with a placeholder while it loads and a permanent,
/// labelled fallback when the URL is dead.
///
/// A broken image URL must never collapse a product card into a blank gap: the buyer should be
/// able to tell "this picture failed" from "this product has no picture".
final class OmMediaImage extends StatelessWidget {
  const OmMediaImage({
    super.key,
    required this.ref,
    this.fit = BoxFit.cover,
    this.useThumbnail = true,
    this.alignment = Alignment.center,
  });

  /// Null means the entity has no image at all, which renders the "no image" placeholder rather
  /// than an error state.
  final MediaRef? ref;
  final BoxFit fit;

  /// Listing pages must not pull full resolution; detail pages pass false.
  final bool useThumbnail;
  final Alignment alignment;

  static const double _placeholderDecodeWidth = 480;

  @override
  Widget build(BuildContext context) {
    final media = ref;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? OmColors.surfaceElevated : OmColors.cream;

    if (media == null || media.url.isEmpty) {
      return _frame(
        context,
        placeholderColor,
        child: const _Fallback(label: 'No image', icon: Icons.image_not_supported_outlined),
      );
    }

    final url = useThumbnail ? media.thumbnailUrl : media.url;
    // Grid thumbnails decode at ~480px; a 5000px hero on a phone is a multi-megabyte download
    // the buyer never sees as extra detail.
    final decodeWidth = useThumbnail ? _placeholderDecodeWidth.round() : null;

    return _frame(
      context,
      placeholderColor,
      child: Image.network(
        url,
        fit: fit,
        alignment: alignment,
        cacheWidth: decodeWidth,
        semanticLabel: media.altText.isEmpty ? null : media.altText,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: placeholderColor,
            alignment: Alignment.center,
            child: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stack) => _frame(
          context,
          placeholderColor,
          child: const _Fallback(label: 'Image unavailable', icon: Icons.broken_image_outlined),
        ),
      ),
    );
  }

  Widget _frame(BuildContext context, Color background, {required Widget child}) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: OmRadius.mdAll,
        ),
        child: Center(child: child),
      );
}

final class _Fallback extends StatelessWidget {
  const _Fallback({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: Theme.of(context).disabledColor),
            const SizedBox(height: OmSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
