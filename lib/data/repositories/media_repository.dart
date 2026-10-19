import 'package:om_events/app/core/services/media/media_object_ledger.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';

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

  /// Paged, filtered read of the `media_objects` ledger — the admin media library.
  ///
  /// Parameters:
  ///  * [kind] is a [MediaKind] `code` (`product`, `category`, `banner`, `review`, `other`). Null
  ///    or empty means every kind; an unrecognised code is rejected with a `ValidationFailure`
  ///    rather than silently narrowed to `other`.
  ///  * [state] narrows to one lifecycle state. Null means all of them, which is what a library
  ///    wants: a `detached` row is exactly the thing staff should be able to see.
  ///  * [missingAltOnly] keeps only rows whose trimmed alt text is shorter than
  ///    `MediaLimits.altTextMinLength` — the same gate `commitProductImages` enforces on write, so
  ///    the audit and the save never disagree about what counts as "has alt text".
  ///  * [pageSize] is clamped to 1..`MediaLimits.ledgerPageSize`.
  ///  * [cursor] is the opaque token from a previous [PagedResult.nextCursor]; null for page one.
  ///
  /// Paging follows this layer's convention: rows come back in `media_objects` document-id order,
  /// the filters are applied in Dart after each document-id-ordered batch (the same trick
  /// `MediaObjectLedger.referencedPaths` uses to avoid demanding an undeclared composite index), so
  /// one page may read more ledger rows than it returns. `nextCursor` is null only once the
  /// collection was read to the end — a page stopped by the read budget still hands back a cursor
  /// and reports `hasMore`, rather than letting a partial sweep look complete.
  ///
  /// Rows are the ledger's own values, with two honest limits. `holders` names the documents that
  /// embed the reference (`products/abc`) but not their display names — resolving a name means
  /// reading that document, which is the caller's job. And `url` is only whatever was stored (empty
  /// on a private bucket); display goes through [signedUrl] / `resolveForRender`, and a caller that
  /// wants to act on `storagePath` must still pass it through `MediaPathPolicy.isManagedPath`.
  Future<PagedResult<MediaObjectRecord>> listMedia({
    String? kind,
    MediaObjectState? state,
    bool missingAltOnly = false,
    int pageSize = 24,
    String? cursor,
  });

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
