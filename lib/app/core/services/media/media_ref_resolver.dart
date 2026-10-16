import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/services/media/media_path_policy.dart';
import 'package:om_events/app/core/services/media/supabase_storage_service.dart';
import 'package:om_events/data/models/media_ref.dart';

/// Which rendering size a URL is being produced for.
enum MediaRenderSize {
  /// Grid/card size: the CDN shrinks and recompresses, so a listing never decodes an original.
  thumbnail,

  /// Detail-page hero: the largest size worth shipping.
  hero,

  /// The stored bytes themselves. Only for downloads and the admin "replace" preview.
  original;

  int? get width => switch (this) {
        MediaRenderSize.thumbnail => MediaLimits.thumbnailWidth,
        MediaRenderSize.hero => MediaLimits.heroWidth,
        MediaRenderSize.original => null,
      };
}

/// Turns a stored [MediaRef] into something renderable *right now*.
///
/// This exists because the two bucket settings produce two different stored values, and only one of
/// them is safe to keep:
///  * public bucket — `MediaRef.url` is a permanent `/object/public/…` URL, so it can live in
///    Firestore; a sized variant is still derived from `storagePath` at render time rather than
///    trusting whatever query string happens to be attached.
///  * private bucket — `MediaRef.url` is empty by design (a signed URL written into a document dies
///    silently mid-session and looks like deleted media), so every render asks for a fresh, cached,
///    expiring link.
///
/// A URL that already carries a `token=` is never reused as if it were permanent: it is re-signed,
/// because a document saved by an older build may contain one.
final class MediaRefResolver {
  MediaRefResolver({required this.service, this.paths = const MediaPathPolicy()});

  final SupabaseStorageService service;
  final MediaPathPolicy paths;

  /// Whether this deployment's stored `url` values may be trusted across sessions. The admin media
  /// panel shows the answer so an operator knows why links change.
  bool get storesPermanentUrls => service.servesPublicUrls && MediaConfigVisibility.isPublic(service);

  /// True when nothing about this reference can be resolved (no path and no URL).
  static bool isResolvable(MediaRef ref) => ref.storagePath.isNotEmpty || ref.url.isNotEmpty;

  Future<String> urlFor(
    MediaRef ref, {
    MediaRenderSize size = MediaRenderSize.thumbnail,
  }) async {
    final path = ref.storagePath;
    if (path.isEmpty || !paths.isManagedPath(path)) {
      // A reference with no managed key is an external/legacy image: render what it says.
      return _stripExpiringSignature(ref.url);
    }

    final visibility = await service.resolveVisibility();
    if (visibility == MediaBucketVisibility.private) {
      return size == MediaRenderSize.thumbnail
          ? service.signedThumbnailUrl(path)
          : service.signedUrl(path);
    }

    if (size == MediaRenderSize.original) return service.publicUrl(path);
    return size == MediaRenderSize.hero
        ? service.heroUrl(path)
        : service.thumbnailUrl(path);
  }

  Future<MediaRef> resolve(
    MediaRef ref, {
    MediaRenderSize size = MediaRenderSize.thumbnail,
  }) async {
    if (ref.storagePath.isEmpty && ref.url.isNotEmpty && size == MediaRenderSize.original) {
      return ref;
    }
    final url = await urlFor(ref, size: size);
    if (url == ref.url) return ref;
    return ref.copyWith(url: url);
  }

  /// Batch resolve for a gallery. Public buckets cost nothing (URLs are derived locally); a private
  /// one signs every distinct path once and the TTL cache absorbs the rest of the page.
  Future<List<MediaRef>> resolveAll(
    List<MediaRef> refs, {
    MediaRenderSize size = MediaRenderSize.thumbnail,
  }) async {
    if (refs.isEmpty) return const <MediaRef>[];
    final resolved = <MediaRef>[];
    for (final ref in refs) {
      resolved.add(await resolve(ref, size: size));
    }
    return resolved;
  }

  /// A signature is a secret that grants read access until it expires, so it is stripped from any
  /// URL this layer hands back for a public bucket rather than passed through.
  static String _stripExpiringSignature(String url) {
    if (!url.contains('token=')) return url;
    final base = url.split('?').first;
    return base;
  }
}

/// Small indirection so [MediaRefResolver.storesPermanentUrls] cannot claim permanence on a bucket
/// whose visibility has not been read yet.
abstract final class MediaConfigVisibility {
  static bool isPublic(SupabaseStorageService service) {
    final visibility = service.knownVisibility;
    return visibility == MediaBucketVisibility.public ||
        visibility == MediaBucketVisibility.assumedPublic;
  }
}
