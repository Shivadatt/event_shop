import 'package:om_events/app/core/utils/om_slug.dart';
import 'package:om_events/data/models/media_ref.dart';

/// The lifecycle stage an object key belongs to.
///
/// `staging` objects are uploaded under `tmp/{writerUid}/` and are only reachable by their owner;
/// an object is promoted to `attached` by a server-side move once it has been written into an
/// entity document. Keeping the stage in the *path* (not only in the ledger) is what lets one RLS
/// policy per prefix do the whole authorisation job.
enum MediaObjectStage {
  staging('tmp'),
  attached('attached');

  const MediaObjectStage(this.code);

  final String code;
}

/// Deterministic, collision-free object keys.
///
/// Shape: `{folder}/{entityKey}/{order}-{mediaId}.{ext}`, with not-yet-attached uploads at
/// `tmp/{writerUid}/{mediaId}.{ext}`.
///
/// Two invariants make this safe:
///  * the `mediaId` segment is a fresh 16-character secure token, so two uploads for the same
///    product can never overwrite each other and a retry can reuse the exact key it was given;
///  * the leading `{order}-` keeps an object listing alphabetically sorted the way the gallery is
///    displayed, which makes a bucket browsed in the dashboard match the storefront.
final class MediaPathPolicy {
  const MediaPathPolicy();

  /// Prefix per kind. Unknown kinds land in `misc`, never in a customer-owned prefix.
  String folderFor(MediaKind kind) => switch (kind) {
        MediaKind.product => 'products',
        MediaKind.category => 'categories',
        MediaKind.banner => 'banners',
        MediaKind.review => 'reviews',
        MediaKind.other => 'misc',
      };

  /// Object key for a file that has been validated but not attached to any document yet.
  String stagingPath({
    required String writerUid,
    required String mediaId,
    required String extension,
  }) =>
      'tmp/${_keyPart(writerUid, fallback: 'anonymous')}/$mediaId.${_ext(extension)}';

  /// Final object key. [entityKey] is the product/category slug when one exists (SEO-legible
  /// object keys) and the document id otherwise; for reviews it is the author's uid.
  String entityPath({
    required MediaKind kind,
    required String entityKey,
    required String mediaId,
    required String extension,
    int order = 0,
  }) {
    final safeOrder = order < 0 ? 0 : order;
    return '${folderFor(kind)}/'
        '${_keyPart(entityKey, fallback: 'unsorted')}/'
        '${_orderPrefix(safeOrder)}$mediaId.${_ext(extension)}';
  }

  /// Recomputes the key a `MediaRef` should have, used by the reference-consistency check in the
  /// admin media panel.
  String pathFor(MediaRef ref, {required String entityKey}) => entityPath(
        kind: ref.kind,
        entityKey: entityKey,
        mediaId: ref.id,
        extension: extensionFromPath(ref.storagePath),
        order: ref.order,
      );

  /// Strips the `{order}-` prefix back out of the file stem.
  String mediaIdFromPath(String path) {
    final stem = fileNameFromPath(path).split('.').first;
    final dash = stem.lastIndexOf('-');
    if (dash <= 0) return stem;
    final candidate = stem.substring(dash + 1);
    return _looksLikeMediaId(candidate) ? candidate : stem;
  }

  static bool _looksLikeMediaId(String value) => value.length >= 8 && value.length <= 32;

  bool isStaging(String path) => path.startsWith('tmp/');

  bool isInsideFolder(String path, MediaKind kind) =>
      path.startsWith('${folderFor(kind)}/');

  /// Every prefix an entity-scoped delete may live in. Used as a guard rail so a bad ledger row
  /// cannot make the pipeline delete outside the media bucket's known folders.
  bool isManagedPath(String path) {
    if (path.isEmpty || path.startsWith('/')) return false;
    final first = path.split('/').first;
    return const <String>{'tmp', 'products', 'categories', 'banners', 'reviews', 'misc'}
        .contains(first);
  }

  String folderFromPath(String path) => path.contains('/') ? path.split('/').first : '';

  String fileNameFromPath(String path) =>
      path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

  String extensionFromPath(String path) {
    final name = fileNameFromPath(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? 'bin' : name.substring(dot + 1).toLowerCase();
  }

  /// Slug-safe single path segment. `OmSlug` already folds a name to `[a-z0-9-]`; ids additionally
  /// keep their case and underscores, so both are whitelisted and everything else is dropped
  /// rather than escaped — an object key that needs escaping is an object key waiting to break a
  /// CDN rule.
  String _keyPart(String raw, {required String fallback}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;
    final slugified = OmSlug.from(trimmed);
    final candidate = slugified.replaceAll('_', '-');
    if (candidate.length > 72) {
      return candidate.substring(0, 72).replaceAll(RegExp(r'-+$'), '');
    }
    return candidate == 'item' && !OmSlug.isValid(trimmed) ? fallback : candidate;
  }

  /// Zero-padded so `products/xyz/10-...` sorts after `products/xyz/09-...` in a bucket listing.
  String _orderPrefix(int order) => order.toString().padLeft(3, '0');

  /// Extension whitelist. Callers reach this with a value derived from a file name or a stored key,
  /// so it is validated rather than trusted: `/`, `\`, `..` and non-ASCII must never be able to
  /// concatenate into an object key. Anything that is not a short alphanumeric token becomes `bin`,
  /// which still uploads (the `Content-Type` comes from the sniffed header, not the extension).
  String _ext(String extension) {
    final clean = extension.replaceFirst('.', '').toLowerCase();
    if (clean.isEmpty || clean.length > 5) return 'bin';
    return _validExtension.hasMatch(clean) ? clean : 'bin';
  }

  static final RegExp _validExtension = RegExp(r'^[a-z0-9]+$');
}
