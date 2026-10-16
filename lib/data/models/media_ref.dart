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

  /// Public object URL, or a signed URL whose expiry is tracked by the media service. Never
  /// assume it is permanent.
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

  /// CDN/transform variant used on grid pages so listing never pulls full-resolution images.
  String get thumbnailUrl => url.contains('?') ? url : '$url?width=480';

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
        'url': url,
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
