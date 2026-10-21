import 'package:om_events/data/om_doc.dart';

/// What a product line needs to know about a file that physically lives in Supabase Storage.
/// Firestore holds this reference only; bytes never do.
final class MediaRef {
  const MediaRef({
    required this.id,
    required this.url,
    this.storagePath = '',
    this.bucket = '',
    this.altText = '',
    this.order = 0,
    this.kind = MediaKind.product,
    this.isPrimary = false,
    this.width,
    this.height,
    this.sizeBytes,
  });

  final String id;

  /// What was stored: a permanent public object URL, or empty on a private bucket. Never a signed
  /// URL — see [storableUrl]. Treat it as possibly stale; the render-time URL comes from
  /// `MediaRefResolver`, which is the only place a sized or signed URL is produced.
  final String url;
  final String storagePath;
  final String bucket;
  final String altText;
  final int order;
  final MediaKind kind;
  final bool isPrimary;
  final int? width;
  final int? height;
  final int? sizeBytes;

  /// The stored URL, unchanged.
  ///
  /// It deliberately does **not** append `?width=480`: Supabase only resizes on its `/render/image/`
  /// endpoint, so a query string on a `/object/public/…` URL is ignored and a grid silently
  /// downloads every original at full resolution. A sized variant needs the bucket's base URL and the
  /// transform parameters, which live in `SupabaseStorageService.thumbnailUrl` / `MediaRenderSize`,
  /// and `OmMediaImage` asks for one through `MediaRefResolver`.
  String get thumbnailUrl => url;

  /// The only URL form this model may serialise.
  ///
  /// A signed URL's `token=` *is* read access until it expires, so persisting one writes a secret into
  /// a publicly readable document and produces an image that breaks on its own. A reference carrying
  /// one is display-only: it stores as empty and the resolver re-signs it at render time, which is
  /// exactly what a private bucket stores anyway.
  static String storableUrl(String url) => url.contains('token=') ? '' : url;

  factory MediaRef.fromMap(Map<String, dynamic> m) => MediaRef(
        id: readStringOrEmpty(m, 'id'),
        url: readStringOrEmpty(m, 'url'),
        storagePath: readStringOrEmpty(m, 'storagePath'),
        bucket: readStringOrEmpty(m, 'bucket'),
        altText: readStringOrEmpty(m, 'altText'),
        order: readIntOrZero(m, 'order'),
        kind: mediaKindFromCode(readStringOrEmpty(m, 'kind')),
        isPrimary: readBool(m, 'isPrimary'),
        width: readInt(m, 'width'),
        height: readInt(m, 'height'),
        sizeBytes: readInt(m, 'sizeBytes'),
      );

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'id': id,
        'url': storableUrl(url),
        'storagePath': storagePath,
        'bucket': bucket,
        'altText': altText,
        'order': order,
        'kind': kind.code,
        'isPrimary': isPrimary,
        'width': width,
        'height': height,
        'sizeBytes': sizeBytes,
      });

  MediaRef copyWith({String? url, String? altText, int? order, bool? isPrimary}) => MediaRef(
        id: id,
        url: url ?? this.url,
        storagePath: storagePath,
        bucket: bucket,
        altText: altText ?? this.altText,
        order: order ?? this.order,
        kind: kind,
        isPrimary: isPrimary ?? this.isPrimary,
        width: width,
        height: height,
        sizeBytes: sizeBytes,
      );
}

enum MediaKind {
  product('product'),
  category('category'),
  banner('banner'),
  review('review'),
  other('other');

  const MediaKind(this.code);
  final String code;
}

MediaKind mediaKindFromCode(String code) =>
    MediaKind.values.firstWhere((k) => k.code == code, orElse: () => MediaKind.other);
