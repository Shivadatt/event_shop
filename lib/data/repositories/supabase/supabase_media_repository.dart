import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/media/media_byte_guard.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/services/media/media_object_ledger.dart';
import 'package:om_events/app/core/services/media/media_optimise_gateway.dart';
import 'package:om_events/app/core/services/media/media_path_policy.dart';
import 'package:om_events/app/core/services/media/media_ref_resolver.dart';
import 'package:om_events/app/core/services/media/media_uploader.dart';
import 'package:om_events/app/core/services/media/media_validator.dart';
import 'package:om_events/app/core/services/media/supabase_storage_service.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/om_doc.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/media_repository.dart';

/// The admin-facing half of the media repository: the same pipeline, but watchable.
///
/// [MediaRepository] is deliberately minimal (upload/replace/delete) so the storefront never has to
/// reason about uploads. Admin forms need queueing, per-file progress, cancel and retry, so those
/// live here. Widgets reach it with `if (repository is MediaUploadPipeline)` and fall back to
/// `upload()` when they are not bound to a pipeline implementation — nothing outside the admin panel
/// has to know this port exists.
abstract interface class MediaUploadPipeline {
  /// Starts an upload and returns immediately; the task carries progress, cancel and retry.
  MediaUploadTask enqueueUpload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required MediaKind kind,
    required String ownerId,
    required String altText,
    int order,
    int alreadyAttached,
    String? entityKey,
    MediaAttachment? attachment,
    void Function(double fraction)? onProgress,
  });

  Future<MediaRef> retryUpload(MediaUploadTask task);

  void cancelUpload(MediaUploadTask task);

  List<MediaUploadTask> get uploadTasks;

  /// The path rules, so a form can show where a file will land without importing the service layer.
  String describeRules(MediaKind kind);

  /// Human-readable bucket state: ready, or exactly which `--dart-define` key is missing.
  String get mediaStatusMessage;

  /// Turn stored references into renderable ones for the current bucket setting. On a public
  /// bucket this only appends the CDN transform; on a private one it returns fresh signed URLs that
  /// must never be written back to Firestore.
  Future<List<MediaRef>> resolveForRender(
    List<MediaRef> refs, {
    MediaRenderSize size,
  });
}

/// Bucket cleanup, as its own port.
///
/// Orphan management is not an upload concern and not every screen that can upload should be able to
/// delete, so the admin media panel opts in explicitly with `if (repository is MediaOrphanControl)`.
abstract interface class MediaOrphanControl {
  Future<OrphanScan> scanOrphans();

  /// Why deletion is off the table even though a scan ran, or null when it is available.
  String? get orphanScanNote;

  /// Whether this device may confirm a deletion at all (the storage policy still has the last word).
  bool get canManageMedia;

  /// Deletes exactly the paths the last scan reported as orphans. Requires an explicit
  /// confirmation from the caller: a scan alone never removes data.
  Future<List<String>> deleteConfirmed(List<String> storagePaths);
}

/// Supabase Storage + Firestore bookkeeping implementation of [MediaRepository].
///
/// Responsibilities kept here: the byte-level gate, the object lifecycle, the `media_objects`
/// ledger, and the field-level Firestore write for product galleries. Nothing above this class
/// touches `SupabaseClient` or `FirebaseFirestore`.
final class SupabaseMediaRepository
    implements MediaRepository, MediaUploadPipeline, MediaOrphanControl {
  SupabaseMediaRepository._({
    required this.service,
    required this.ledger,
    required this.validator,
    required this.paths,
    required this.uploader,
    required this.resolver,
  });

  /// Wires the real backends when the build has them, and the loud stubs when it does not — so an
  /// unconfigured bundle still produces a repository whose every call explains itself.
  factory SupabaseMediaRepository({
    SupabaseStorageService? service,
    MediaObjectLedger? ledger,
    MediaValidator? validator,
    MediaPathPolicy? paths,
    MediaOptimiseGateway? optimiseGateway,
  }) {
    final storage = service ?? SupabaseStorageService();
    final bookkeeping = ledger ??
        (Env.hasFirebase
            ? FirestoreMediaObjectLedger()
            : const UnavailableMediaObjectLedger());
    final gate = validator ?? const MediaValidator();
    final policy = paths ?? const MediaPathPolicy();
    final gateway = optimiseGateway ?? const PassthroughOptimiseGateway();
    return SupabaseMediaRepository._(
      service: storage,
      ledger: bookkeeping,
      validator: gate,
      paths: policy,
      resolver: MediaRefResolver(service: storage, paths: policy),
      uploader: MediaUploader(
        service: storage,
        validator: gate,
        paths: policy,
        ledger: bookkeeping,
        optimiseGateway: gateway,
      ),
    );
  }

  final SupabaseStorageService service;
  final MediaObjectLedger ledger;
  final MediaValidator validator;
  final MediaPathPolicy paths;
  final MediaUploader uploader;
  final MediaRefResolver resolver;

  /// The scan the admin last ran. [MediaOrphanControl.deleteConfirmed] only accepts paths this scan
  /// actually reported, so a stale or hand-built list can never reach the bucket.
  OrphanScan? _lastScan;
  String? _lastScanNote;

  @override
  bool get isConfigured => service.isConfigured && MediaConfig.isConfigured;

  @override
  String get mediaStatusMessage => MediaConfig.statusMessage;

  /// Why deletion is not on offer even though a scan found candidates.
  @override
  String? get orphanScanNote => _lastScanNote;

  /// Whether this deployment stores permanent public URLs. Shown in the admin panel so an operator
  /// knows why a private bucket's links change on every render.
  bool get storesPermanentUrls => service.servesPublicUrls;

  @override
  bool get canManageMedia => MediaConfig.canManageMedia;

  // ---------------------------------------------------------------- uploads

  @override
  Future<MediaRef> upload({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required MediaKind kind,
    required String ownerId,
    String altText = '',
    int order = 0,
    void Function(double fraction)? onProgress,
  }) async {
    _requireConfigured('upload ${kind.code} media');
    return uploader.uploadNow(
      bytes: _bytesOf(bytes),
      fileName: fileName,
      mimeType: mimeType,
      kind: kind,
      ownerId: _ownerId(ownerId),
      altText: altText,
      order: order,
      onProgress: onProgress,
    );
  }

  @override
  MediaUploadTask enqueueUpload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required MediaKind kind,
    required String ownerId,
    required String altText,
    int order = 0,
    int alreadyAttached = 0,
    String? entityKey,
    MediaAttachment? attachment,
    void Function(double fraction)? onProgress,
  }) {
    _requireConfigured('upload ${kind.code} media');
    return uploader.enqueue(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      kind: kind,
      ownerId: _ownerId(ownerId),
      altText: altText,
      order: order,
      alreadyAttached: alreadyAttached,
      entityKey: entityKey,
      attachment: attachment,
      onProgress: onProgress,
    );
  }

  @override
  Future<MediaRef> retryUpload(MediaUploadTask task) async {
    _requireConfigured('retry an upload');
    return uploader.retry(task);
  }

  @override
  void cancelUpload(MediaUploadTask task) => uploader.cancel(task);

  @override
  List<MediaUploadTask> get uploadTasks => uploader.inFlight.toList(growable: false);

  @override
  String describeRules(MediaKind kind) => validator.describeRules(kind);

  @override
  Future<MediaRef> replace({
    required MediaRef existing,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    void Function(double fraction)? onProgress,
  }) async {
    _requireConfigured('replace an image');
    final replaced = await uploader.replace(
      existing: existing,
      bytes: _bytesOf(bytes),
      fileName: fileName,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    service.invalidateSigned(existing.storagePath);
    return replaced;
  }

  // ---------------------------------------------------------------- deletion

  @override
  Future<void> delete(MediaRef ref) async {
    _requireConfigured('delete an image');
    final report = await _release(<MediaRef>[ref]);
    final skipped = report.skipped;
    if (skipped.isNotEmpty) {
      throw MediaFailure(skipped.single);
    }
  }

  @override
  Future<void> deleteMany(List<MediaRef> refs) async {
    _requireConfigured('delete images');
    final report = await _release(refs);
    if (report.skipped.isNotEmpty) {
      // Anything safe was already removed, so the message must say so rather than imply the whole
      // batch is untouched.
      throw MediaFailure(
        '${report.deleted.length} image(s) deleted. '
        'Not deleted: ${report.skipped.join(' ')}',
      );
    }
  }

  /// Deletes objects and their ledger rows, refusing any path another live document still claims.
  ///
  /// Two guards run per object. Object keys embed a 16-character secure token (`{order}-{mediaId}`),
  /// so two unrelated images cannot share a path; a shared path only happens when a `MediaRef` was
  /// copied into a second document. And a duplicated product copies its whole `images` array, so one
  /// object legitimately sits in two holder documents while the ledger keeps a single row: the
  /// `holders` list is what stops the first gallery from deleting the other one's bytes.
  Future<_ReleaseReport> _release(List<MediaRef> refs, {String? fromHolder}) async {
    if (refs.isEmpty) return const _ReleaseReport(deleted: <String>[], skipped: <String>[]);
    final deletable = <MediaRef>[];
    final skipped = <String>[];
    final rowIds = <String>{};
    for (final ref in refs) {
      final path = ref.storagePath;
      if (path.isEmpty) {
        skipped.add('${ref.id} has no storage path (it may be an external image); nothing removed.');
        continue;
      }
      if (!paths.isManagedPath(path)) {
        skipped.add('$path is outside the managed media prefixes, so it was left alone.');
        continue;
      }
      if (!ledger.isAvailable) {
        throw MediaFailure('Cannot delete media — ${ledger.unavailableReason}');
      }
      final others = await ledger.liveRecordsSharingPath(path, exceptId: ref.id);
      if (others.isNotEmpty) {
        final owners = others
            .map((record) => record.attachment?.describe() ?? record.ownerId)
            .where((owner) => owner.isNotEmpty)
            .toSet();
        skipped.add(
          '$path is still referenced by ${owners.isEmpty ? 'another media record' : owners.join(', ')}.',
        );
        continue;
      }
      final detaching = fromHolder ?? await _registeredOwner(ref);
      final rivals = await ledger.otherHolders(ref.id, exceptHolder: detaching);
      if (rivals.isNotEmpty) {
        skipped.add(
          '$path is also embedded in ${rivals.join(', ')}, so the file was kept. '
          'Remove it there too before the object can be deleted.',
        );
        // This document really did drop the reference, so its claim is withdrawn even though the
        // bytes survive for the other holder.
        await ledger.releaseHolder(<String>[ref.id], detaching ?? '');
        continue;
      }
      deletable.add(ref);
      rowIds.add(ref.id);
    }

    if (deletable.isEmpty) return _ReleaseReport(deleted: const <String>[], skipped: skipped);

    await service.remove(deletable.map((ref) => ref.storagePath).toList(growable: false));
    for (final ref in deletable) {
      service.invalidateSigned(ref.storagePath);
    }
    await ledger.remove(rowIds.toList(growable: false));
    return _ReleaseReport(
      deleted: deletable.map((ref) => ref.storagePath).toList(growable: false),
      skipped: skipped,
    );
  }

  /// The document the ledger last attached this object to.
  ///
  /// [MediaRepository.delete] carries no document context, so when a gallery removes one image the
  /// registered owner is the only reasonable holder to excuse; every other name on the row belongs
  /// to a different live document and blocks the deletion.
  Future<String?> _registeredOwner(MediaRef ref) async {
    if (ref.id.isEmpty) return null;
    final row = await ledger.byId(ref.id);
    final attach = row?.attachment;
    if (attach == null || attach.isEmpty) return null;
    return attach.describe();
  }

  // ---------------------------------------------------------------- orphans

  @override
  Future<OrphanScan> scanOrphans() async {
    _requireConfigured('scan the media bucket');
    _lastScanNote = null;

    final listing = await service.listObjects();
    final referenced = <String>{};
    if (ledger.isAvailable) {
      referenced.addAll(await ledger.referencedPaths());
    } else {
      // Without the ledger the scan has no authority to call anything unreferenced, so it reports
      // the bucket contents only and offers no deletion.
      _lastScanNote =
          'The media_objects ledger is unavailable (${ledger.unavailableReason}), so this is a '
          'listing, not an orphan report.';
    }

    final sweep = ledger.isAvailable ? await _sweepDocuments() : null;
    if (sweep != null) {
      referenced.addAll(sweep.paths);
      if (!sweep.complete) {
        _lastScanNote = '${_lastScanNote == null ? '' : '$_lastScanNote '}${sweep.note}';
      }
    }

    final managed = listing.paths.where(paths.isManagedPath).toList(growable: false);
    final reasons = <String>[];
    if (listing.isPartial) {
      reasons.add(
        'the sweep stopped at ${MediaLimits.orphanScanMaxObjects} objects '
        '(use the scheduled service-role job instead)',
      );
    }
    if (sweep != null && !sweep.complete) {
      reasons.add('not every document was read');
    }
    if (!MediaConfig.canManageMedia) {
      reasons.add('this device is not signed in as staff');
    }
    final canDelete = reasons.isEmpty;
    if (!canDelete) {
      final note = 'Deletion is disabled because ${reasons.join(', ')}.';
      _lastScanNote = _lastScanNote == null ? note : '$_lastScanNote $note';
    }

    final scan = OrphanScan(
      objects: managed,
      referencedPaths: referenced,
      canDelete: canDelete,
    );
    _lastScan = scan;
    return scan;
  }

  /// Explicit second step of the orphan flow: the admin confirmed this exact list.
  ///
  /// Re-reads the reference set before touching the bucket, because anything can have been attached
  /// between the scan and the click. Refuses the whole batch if one path is now live rather than
  /// deleting the rest and leaving the admin with a partially-applied confirmation.
  @override
  Future<List<String>> deleteConfirmed(List<String> paths) async {
    _requireConfigured('delete unreferenced objects');
    if (!MediaConfig.canManageMedia) {
      throw const MediaFailure(
        'Only a signed-in staff session can delete media objects. The storage policy enforces this '
        'too, so a disabled client is not a way around it.',
      );
    }
    final scan = _lastScan;
    if (scan == null) {
      throw const MediaFailure('Run a scan first: deletion only accepts reported candidates.');
    }
    if (!scan.canDelete) {
      throw MediaFailure(
        _lastScanNote == null
            ? 'This scan does not allow deletion. Run it again.'
            : _lastScanNote!,
      );
    }
    if (paths.isEmpty) return const <String>[];

    final candidates = scan.candidates.toSet();
    final unknown = paths.where((path) => !candidates.contains(path)).toList(growable: false);
    if (unknown.isNotEmpty) {
      throw MediaFailure(
        'Refusing to delete ${unknown.length} path(s) that the last scan did not report as '
        'orphans, including ${unknown.first}. Run the scan again.',
      );
    }

    final fresh = await _currentReferences();
    final nowLive = paths.where(fresh.contains).toList(growable: false);
    if (nowLive.isNotEmpty) {
      throw MediaFailure(
        'Refusing the batch: ${nowLive.first} and ${nowLive.length - 1} other object(s) became '
        'referenced since the scan. Run it again.',
      );
    }

    await service.remove(paths);
    for (final path in paths) {
      service.invalidateSigned(path);
    }
    // `paths` is this method's argument, which shadows the [MediaPathPolicy] field, so the policy is
    // bound to a local before it is used: an object key is `{order}-{mediaId}.{ext}`, and the mediaId
    // it carries is the `media_objects` row id. Only paths the scan reported (and that are still
    // unreferenced) can get here, so a hand-built list can never delete a ledger row.
    final policy = this.paths;
    final ids = paths
        .map(policy.mediaIdFromPath)
        .where((String id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isNotEmpty && ledger.isAvailable) {
      await ledger.remove(ids);
    }
    _lastScan = null;
    return paths;
  }

  Future<Set<String>> _currentReferences() async {
    final paths = <String>{};
    if (!ledger.isAvailable) return paths;
    paths.addAll(await ledger.referencedPaths());
    final sweep = await _sweepDocuments();
    paths.addAll(sweep.paths);
    return paths;
  }

  /// Cross-checks the documents that can hold an image, because an object uploaded by an older
  /// build has no `media_objects` row and would otherwise look orphaned while a live product still
  /// points at it.
  ///
  /// This is a bounded diagnostic sweep, not a janitor: it stops at [MediaLimits.ledgerMaxDocs]
  /// reads per collection and reports `complete: false`, which disables deletion.
  Future<_Sweep> _sweepDocuments() async {
    if (!Env.hasFirebase) {
      return const _Sweep(
        paths: <String>{},
        complete: false,
        note: 'Firestore is not configured, so document references could not be checked.',
      );
    }
    final found = <String>{};
    var complete = true;
    String? note;

    try {
      final settings = await AppBootstrap.db
          .collection(Collections.storeSettings)
          .doc(Collections.storeSettingsDoc)
          .get();
      found.addAll(_pathsFromMap(settings.data(), 'banners'));
    } on FirebaseException catch (error) {
      // Banner rules commonly lag behind product rules; a missing read only means this collection
      // could not be confirmed, which is reported rather than treated as "no references".
      complete = false;
      note = 'store_settings could not be read (${error.code}), so its banners are unconfirmed. ';
    }

    for (final collection in const <String>[
      Collections.products,
      Collections.categories,
      Collections.reviews,
    ]) {
      var read = 0;
      QueryDocumentSnapshot<Map<String, dynamic>>? after;
      while (read < MediaLimits.ledgerMaxDocs) {
        final query = AppBootstrap.db
            .collection(collection)
            .orderBy(FieldPath.documentId)
            .limit(MediaLimits.ledgerPageSize);
        final page = await (after == null ? query : query.startAfterDocument(after)).get();
        if (page.docs.isEmpty) break;
        for (final doc in page.docs) {
          found.addAll(_pathsFromMap(doc.data(), 'images'));
        }
        read += page.docs.length;
        after = page.docs.last;
        if (page.docs.length < MediaLimits.ledgerPageSize) break;
      }
      if (read >= MediaLimits.ledgerMaxDocs) {
        complete = false;
        note = '${note ?? ''}$collection has more than $MediaLimits.ledgerMaxDocs documents, '
            'so its references are only partly confirmed. ';
      }
    }

    return _Sweep(paths: found, complete: complete, note: note ?? '');
  }

  static Iterable<String> _pathsFromMap(Map<String, dynamic>? data, String field) {
    if (data == null) return const <String>[];
    return readMapList(data, field)
        .map((image) => readStringOrEmpty(image, 'storagePath'))
        .where((path) => path.isNotEmpty);
  }

  // ---------------------------------------------------------------- library listing

  /// Reads the `media_objects` ledger, paged by document id, and applies the admin's filters in
  /// Dart.
  ///
  /// Two deliberate choices. Filtering happens client-side after each document-id-ordered batch
  /// because a `kind`/`state` equality combined with an ordering that is not on that field is what
  /// makes Firestore demand a composite index nobody declared — `referencedPaths` already works this
  /// way for the same reason. And the read budget is the ledger's own ceiling: when it stops with
  /// rows probably unread, the page still reports a cursor, because a media library that silently
  /// looks complete is how an admin concludes an image is gone.
  @override
  Future<PagedResult<MediaObjectRecord>> listMedia({
    String? kind,
    MediaObjectState? state,
    bool missingAltOnly = false,
    int pageSize = 24,
    String? cursor,
  }) async {
    _requireConfigured('list the media library');
    final kindFilter = _mediaKindFilter(kind);
    final limit = _pageSize(pageSize);
    if (!ledger.isAvailable) {
      throw MediaFailure('Cannot list media — ${ledger.unavailableReason}');
    }

    var after = _decodeListCursor(cursor);
    final matches = <MediaObjectRecord>[];
    String? lastReadId;
    var read = 0;
    var sweptToEnd = false;

    while (read < MediaLimits.ledgerMaxDocs) {
      final query = AppBootstrap.db
          .collection(FirestoreMediaObjectLedger.collectionPath)
          .orderBy(FieldPath.documentId)
          .limit(MediaLimits.ledgerPageSize);
      final page = await (after == null ? query : query.startAfter(<Object?>[after])).get();
      if (page.docs.isEmpty) {
        sweptToEnd = true;
        break;
      }
      for (final doc in page.docs) {
        final record = MediaObjectRecord.fromMap(doc.data(), id: doc.id);
        if (_isLibraryRow(record, kindFilter, state, missingAltOnly)) {
          if (matches.length >= limit) {
            // The page is full and one more match exists, so the cursor names the last row actually
            // handed over. The next call starts after that document: it re-reads only rows the
            // filters had already rejected, so nothing is shown twice and nothing is skipped.
            return PagedResult<MediaObjectRecord>(
              items: matches.toList(growable: false),
              nextCursor: _encodeListCursor(matches.last.id),
            );
          }
          matches.add(record);
        }
        lastReadId = doc.id;
      }
      read += page.docs.length;
      after = page.docs.last.id;
      if (page.docs.length < MediaLimits.ledgerPageSize) {
        sweptToEnd = true;
        break;
      }
    }

    if (!sweptToEnd && lastReadId != null) {
      return PagedResult<MediaObjectRecord>(
        items: matches.toList(growable: false),
        nextCursor: _encodeListCursor(lastReadId),
      );
    }
    return PagedResult<MediaObjectRecord>(items: matches.toList(growable: false));
  }

  static bool _isLibraryRow(
    MediaObjectRecord record,
    MediaKind? kind,
    MediaObjectState? state,
    bool missingAltOnly,
  ) {
    if (kind != null && record.kind != kind) return false;
    if (state != null && record.state != state) return false;
    if (missingAltOnly && record.altText.trim().length >= MediaLimits.altTextMinLength) {
      return false;
    }
    return true;
  }

  /// A `kind` is accepted as the code a stored row carries, so an unknown value is refused instead
  /// of being mapped to `MediaKind.other` by `mediaKindFromCode` and quietly returning nothing.
  static MediaKind? _mediaKindFilter(String? kind) {
    final code = kind?.trim().toLowerCase() ?? '';
    if (code.isEmpty || code == 'all') return null;
    for (final candidate in MediaKind.values) {
      if (candidate.code == code) return candidate;
    }
    throw ValidationFailure(
      'Unknown media kind "$kind". Use one of '
      '${MediaKind.values.map((candidate) => candidate.code).join(', ')}, or null for all kinds.',
    );
  }

  static int _pageSize(int requested) {
    if (requested < 1) return 1;
    return requested > MediaLimits.ledgerPageSize ? MediaLimits.ledgerPageSize : requested;
  }

  static String _encodeListCursor(String documentId) =>
      base64Url.encode(utf8.encode(jsonEncode(<String, Object?>{'id': documentId})));

  /// A token this library did not issue is an error, not a restart: silently falling back to page
  /// one would show the first rows twice under a "load more" gesture.
  static String? _decodeListCursor(String? cursor) {
    final token = cursor?.trim() ?? '';
    if (token.isEmpty) return null;
    Object? id;
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(token))) as Map<String, dynamic>;
      id = map['id'] as Object?;
    } catch (_) {
      id = null;
    }
    if (id is! String || id.isEmpty) {
      throw const ValidationFailure(
        'That media page token was not issued by this library, so paging cannot continue. Reload '
        'the media library.',
      );
    }
    return id;
  }

  // ---------------------------------------------------------------- urls

  @override
  Future<String> signedUrl(
    String storagePath, {
    Duration ttl = const Duration(minutes: 15),
  }) async {
    _requireConfigured('sign a media URL');
    if (storagePath.isEmpty) throw const MediaFailure('Cannot sign an empty media path.');
    // The path arrives from a caller (and ultimately from a document field), so it is not trusted:
    // the managed prefixes *are* the authorisation boundary (see MediaPathPolicy), and without this
    // guard an anon client could ask this bucket to sign a path outside the media folders.
    if (!paths.isManagedPath(storagePath)) {
      throw MediaFailure(
        'Refusing to sign $storagePath: it is outside the managed media prefixes.',
      );
    }
    return service.signedUrl(storagePath, ttl: ttl);
  }

  /// Render-time URL for a reference: a sized public URL for a public bucket, a cached signed URL
  /// for a private one. Never store the result.
  Future<String> renderUrl(
    MediaRef ref, {
    MediaRenderSize size = MediaRenderSize.thumbnail,
  }) =>
      resolver.urlFor(ref, size: size);

  @override
  Future<List<MediaRef>> resolveForRender(
    List<MediaRef> refs, {
    MediaRenderSize size = MediaRenderSize.thumbnail,
  }) =>
      resolver.resolveAll(refs, size: size);

  // ---------------------------------------------------------------- validation

  @override
  MediaValidation validate({
    required int byteLength,
    required String mimeType,
    required List<int> leadingBytes,
  }) =>
      validator.validate(
        byteLength: byteLength,
        mimeType: mimeType,
        leadingBytes: leadingBytes,
      );

  /// Full gate for admin forms, run on the whole file: the same checks the pipeline will run,
  /// including alt text, pixel bounds and the per-entity cap, so a form can reject a file before
  /// the admin wastes a transfer. Callers get the precise reason out of [MediaAnalysis.error].
  MediaAnalysis analyseUpload({
    required Uint8List bytes,
    required MediaKind kind,
    required String altText,
    required int alreadyAttached,
    String? fileName,
    String? declaredMimeType,
  }) =>
      validator.analyse(
        bytes: bytes,
        kind: kind,
        altText: altText,
        alreadyAttached: alreadyAttached,
        fileName: fileName,
        declaredMimeType: declaredMimeType,
      );

  // ---------------------------------------------------------------- product gallery

  @override
  Future<Product> commitProductImages({
    required Product product,
    required List<MediaRef> nextImages,
  }) async {
    _requireConfigured('save product images');
    final rules = MediaLimits.rulesFor(MediaKind.product);
    if (nextImages.length > rules.maxPerEntity) {
      throw MediaFailure(
        'A product can hold ${rules.maxPerEntity} images; this form submitted '
        '${nextImages.length}. Remove ${nextImages.length - rules.maxPerEntity} before saving.',
      );
    }
    // Alt text is enforced here rather than only in the form: this method is the write path that
    // every caller shares, and a gallery without alt text is a silent accessibility hole on the
    // storefront rather than a visible one in the admin.
    final missingAlt = <String>[];
    for (final ref in nextImages) {
      if (ref.altText.trim().length >= MediaLimits.altTextMinLength) continue;
      missingAlt.add(ref.id.isEmpty ? ref.storagePath : ref.id);
    }
    if (missingAlt.isNotEmpty) {
      throw MediaFailure(
        '${missingAlt.length} image(s) have no alt text (${missingAlt.take(3).join(', ')}'
        '${missingAlt.length > 3 ? ', …' : ''}). '
        'Describe each picture before saving the gallery.',
      );
    }

    final normalized = _normalizedGallery(nextImages);
    final payload = normalized.map((ref) => ref.toMap()).toList(growable: false);
    // The one place a gallery becomes a document field, so this is where the "no bytes in
    // Firestore" rule is enforced rather than assumed.
    FirestoreMediaGuard.ensureNoImageBytes(
      payload,
      where: '${Collections.products}/${product.id}.images',
    );

    try {
      await AppBootstrap.db
          .collection(Collections.products)
          .doc(product.id)
          .update(<String, Object?>{'images': payload});
    } on FirebaseException catch (error) {
      throw MediaFailure(
        error.code == 'not-found'
            ? 'This product does not exist yet, so its images cannot be stored. Save the product '
                'first, then upload its pictures.'
            : 'Firestore refused the image update (${error.code}).',
      );
    }

    final attachment = MediaAttachment(collection: Collections.products, docId: product.id);
    final keptIds = normalized.map((ref) => ref.id).toList(growable: false);
    if (keptIds.isNotEmpty && ledger.isAvailable) {
      await ledger.setState(keptIds, MediaObjectState.attached, attachment: attachment);
    }

    final kept = keptIds.toSet();
    final removed =
        product.images.where((ref) => !kept.contains(ref.id)).toList(growable: false);
    final report = await _release(removed, fromHolder: attachment.describe());
    for (final warning in report.skipped) {
      // The document is already correct, so a refusal here must not fail the save: the object stays
      // in the bucket with its ledger row attached, and the next orphan scan sees the truth.
      debugPrint('Image not removed after saving ${product.id}: $warning');
    }

    return product.copyWith(images: normalized);
  }

  /// Sorts, renumbers and makes exactly one image primary — the first.
  ///
  /// `order` is stored per reference and `isPrimary` drives every card in the catalogue, so both
  /// are normalised on write instead of trusting whatever an admin form happened to send. An
  /// explicit primary chosen at position 3 is hoisted to the front rather than dropped, because
  /// silently falling back to `images.first` would change the storefront without telling anyone.
  List<MediaRef> _normalizedGallery(List<MediaRef> images) {
    if (images.isEmpty) return const <MediaRef>[];
    final sorted = <MediaRef>[...images]..sort((a, b) => a.order.compareTo(b.order));
    final primaryIndex = sorted.indexWhere((ref) => ref.isPrimary);
    if (primaryIndex > 0) {
      sorted.insert(0, sorted.removeAt(primaryIndex));
    }
    return <MediaRef>[
      for (var index = 0; index < sorted.length; index++)
        sorted[index].copyWith(order: index, isPrimary: index == 0),
    ];
  }

  // ---------------------------------------------------------------- helpers

  String _ownerId(String ownerId) => ownerId.trim().isEmpty ? 'unowned' : ownerId.trim();

  static Uint8List _bytesOf(List<int> bytes) =>
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  void _requireConfigured(String action) {
    if (!MediaConfig.isConfigured) MediaConfig.unavailable(action: action);
  }
}

final class _ReleaseReport {
  const _ReleaseReport({required this.deleted, required this.skipped});

  final List<String> deleted;
  final List<String> skipped;
}

final class _Sweep {
  const _Sweep({required this.paths, required this.complete, required this.note});

  final Set<String> paths;
  final bool complete;
  final String note;
}
