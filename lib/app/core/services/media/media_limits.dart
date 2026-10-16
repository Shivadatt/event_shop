import 'package:om_events/data/models/media_ref.dart';

/// One kind's ceilings. Grouped per kind because a customer review photo and a homepage banner
/// have genuinely different budgets, and a single global limit forces either a loose cap that
/// lets a 40 MB upload through or a tight one that rejects a legitimate hero shot.
final class MediaKindRules {
  const MediaKindRules({
    required this.maxBytes,
    required this.minWidth,
    required this.minHeight,
    required this.maxWidth,
    required this.maxHeight,
    required this.maxPerEntity,
  });

  /// Hard client-side byte cap. The bucket enforces its own cap too — this one exists so a
  /// rejected file never leaves the browser.
  final int maxBytes;

  /// Below these dimensions the picture is unusable at the 480px grid thumbnail and blurry on
  /// the detail hero, so it is refused rather than published.
  final int minWidth;
  final int minHeight;

  /// Above these, a phone pays for megabytes the buyer cannot see. Admins routinely drag in
  /// 8000x6000 camera originals; those must be resized before upload.
  final int maxWidth;
  final int maxHeight;

  /// Products are capped because `images` is an array embedded in the product document and
  /// Firestore has a 1 MiB document limit — a runaway gallery breaks the save, not just the page.
  final int maxPerEntity;

  int get minPixels => minWidth * minHeight;

  int get maxPixels => maxWidth * maxHeight;

  String describe() => 'max ${(maxBytes / 1024 / 1024).toStringAsFixed(1)} MB, '
      '${minWidth}x$minHeight–${maxWidth}x$maxHeight, '
      '$maxPerEntity per item';
}

/// Every number the media pipeline gates on. Constants live here so the docs, the validator and
/// the admin helper text cannot drift apart.
abstract final class MediaLimits {
  static const int _mb = 1024 * 1024;

  /// Only these are accepted. Anything else (GIF, HEIC, SVG, BMP, TIFF) is refused before the
  /// first byte is sent: SVG is an XSS vector when served from the same origin, HEIC does not
  /// decode in Chrome, and animated GIF has no place in a product grid.
  static const Set<String> allowedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/avif',
  };

  static const Map<MediaKind, MediaKindRules> rulesByKind = <MediaKind, MediaKindRules>{
    MediaKind.product: MediaKindRules(
      maxBytes: 8 * _mb,
      minWidth: 600,
      minHeight: 600,
      maxWidth: 5000,
      maxHeight: 5000,
      maxPerEntity: 10,
    ),
    MediaKind.category: MediaKindRules(
      maxBytes: 6 * _mb,
      minWidth: 600,
      minHeight: 400,
      maxWidth: 4000,
      maxHeight: 4000,
      maxPerEntity: 4,
    ),
    MediaKind.banner: MediaKindRules(
      maxBytes: 8 * _mb,
      minWidth: 1200,
      minHeight: 400,
      maxWidth: 5000,
      maxHeight: 2500,
      maxPerEntity: 6,
    ),
    // Customer photos are small by nature (a phone snapshot of a delivered arch), but the same
    // pixel floor applies so a 120px thumbnail cannot become the only picture of a product.
    MediaKind.review: MediaKindRules(
      maxBytes: 5 * _mb,
      minWidth: 400,
      minHeight: 400,
      maxWidth: 4000,
      maxHeight: 4000,
      maxPerEntity: 4,
    ),
    MediaKind.other: MediaKindRules(
      maxBytes: 8 * _mb,
      minWidth: 200,
      minHeight: 200,
      maxWidth: 5000,
      maxHeight: 5000,
      maxPerEntity: 24,
    ),
  };

  static MediaKindRules rulesFor(MediaKind kind) =>
      rulesByKind[kind] ?? rulesByKind[MediaKind.other]!;

  /// The loosest cap across kinds, used by the context-free `validate()` entry point that has no
  /// `MediaKind` in its signature. The upload path always uses [rulesFor].
  static int get maxBytesCeiling =>
      rulesByKind.values.map((r) => r.maxBytes).reduce((a, b) => a > b ? a : b);

  /// Signed URLs are a rendering-time detail, never a stored value. Two pages in flight is enough
  /// headroom for a slow CDN without letting a link outlive a staff session.
  static const Duration signedUrlTtl = Duration(minutes: 15);

  /// Re-sign this far before expiry: a URL that dies while `<img>` is fetching renders as a
  /// broken image, which looks like a deleted product photo.
  static const Duration signedUrlRefreshMargin = Duration(minutes: 3);

  /// `storage.list()` page size for the orphan sweep.
  static const int orphanScanPageSize = 500;

  /// A client-side sweep is a diagnostic, not a janitor. Past this many objects the scan is
  /// reported as partial and the scheduled service-role job is the tool that must be used.
  static const int orphanScanMaxObjects = 2000;

  /// `media_objects` pages read while building the reference set.
  static const int ledgerPageSize = 200;
  static const int ledgerMaxDocs = 5000;

  /// Storage rejects a batch larger than this in one `remove()` call.
  static const int deleteBatchSize = 50;

  /// Bytes the pipeline always inspects before deciding a file is what its name claims.
  static const int sniffWindowBytes = 64;

  /// JPEG puts its start-of-frame marker after EXIF/ICC segments, which can be hundreds of
  /// kilobytes on a camera original; the scan stops at the first frame header.
  static const int jpegHeaderScanBytes = 512 * 1024;

  /// Alt text is required, but an alt of "x" is as useless as none. Upper bound keeps the string
  /// inside the Firestore document budget.
  static const int altTextMinLength = 3;
  static const int altTextMaxLength = 200;

  /// Cache-control written on upload. Final objects are overwritten in place by `replace()`, so
  /// they cannot be marked `immutable`; 24h bounds how long a stale picture is visible when no
  /// CDN purge is available (purge needs the service-role key — see docs/supabase-storage.md).
  static const String finalObjectCacheControl = '86400';

  /// Staged objects are short-lived by design; a long CDN life would keep dead bytes alive.
  static const String stagingCacheControl = '300';

  /// Grid thumbnail width. Matches `MediaRef.thumbnailUrl`'s `width=480` and the decode width in
  /// `OmMediaImage`, so one transform variant serves every listing surface.
  static const int thumbnailWidth = 480;

  /// Detail-hero cap: the largest size worth shipping, not the original.
  static const int heroWidth = 1600;

  /// CDN render quality (percentage). 80 is the Supabase default and visually lossless for
  /// product photography at these widths.
  static const int renderQuality = 80;
}
