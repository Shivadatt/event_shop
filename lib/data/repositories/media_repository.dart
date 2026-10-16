import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';

/// Agent 4 owns the Supabase implementation; everyone else depends only on this shape, so the
/// storefront can render media even while the bucket is unconfigured.
abstract interface class MediaRepository {
  /// False until `SUPABASE_URL` / `SUPABASE_ANON_KEY` are supplied. UI must surface this as a
  /// disabled upload control with an explanation, not a button that fails on click.
  bool get isConfigured;

  Future<MediaRef> upload({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required MediaKind kind,
    required String ownerId,
    String altText = '',
    int order = 0,
    void Function(double fraction)? onProgress,
  });

  /// Replaces the object at [storagePath] with new bytes, keeping the reference id stable so no
  /// product document ever points at a deleted object.
  Future<MediaRef> replace({
    required MediaRef existing,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    void Function(double fraction)? onProgress,
  });

  Future<void> delete(MediaRef ref);

  Future<void> deleteMany(List<MediaRef> refs);

  /// Removes objects referenced by no live document. Runs from the admin panel, server-gated.
  Future<OrphanScan> scanOrphans();

  /// Signed URL for private assets. Callers must treat the result as expiring and re-request it
  /// rather than persisting it into Firestore.
  Future<String> signedUrl(String storagePath, {Duration ttl = const Duration(minutes: 15)});

  /// Client-side gate: size, MIME and magic-byte checks before a byte leaves the browser.
  MediaValidation validate({
    required int byteLength,
    required String mimeType,
    required List<int> leadingBytes,
  });

  /// Rewrites every image reference on a product, deleting what is no longer used.
  Future<Product> commitProductImages({
    required Product product,
    required List<MediaRef> nextImages,
  });
}

final class MediaValidation {
  const MediaValidation({required this.isValid, this.error, this.maximumBytes});

  final bool isValid;
  final String? error;
  final int? maximumBytes;

  bool get isRejected => !isValid;
}

final class OrphanScan {
  const OrphanScan({
    required this.objects,
    required this.referencedPaths,
    this.canDelete = false,
  });

  final List<String> objects;
  final Set<String> referencedPaths;

  /// Deletion of found orphans is an explicit, staff-only action; a scan never removes data.
  final bool canDelete;

  List<String> get candidates =>
      objects.where((path) => !referencedPaths.contains(path)).toList(growable: false);
}
