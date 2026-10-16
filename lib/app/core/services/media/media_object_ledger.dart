import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/media/media_byte_guard.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/om_doc.dart';

/// Lifecycle of a bucket object as the ledger sees it.
enum MediaObjectState {
  /// Uploaded to `tmp/{writerUid}/` and not attached to any document yet. Swept by the TTL job.
  staging('staging'),

  /// Referenced by an entity document (or by a pipeline that is about to reference it).
  attached('attached'),

  /// Unlinked from its document but the object may still exist — the orphan scan's worklist.
  detached('detached');

  const MediaObjectState(this.code);

  final String code;

  static MediaObjectState fromCode(String code) => MediaObjectState.values.firstWhere(
        (state) => state.code == code,
        orElse: () => MediaObjectState.detached,
      );
}

/// What an object is attached to, so a refusal to delete can name the owner.
final class MediaAttachment {
  const MediaAttachment({required this.collection, required this.docId});

  final String collection;
  final String docId;

  bool get isEmpty => collection.isEmpty || docId.isEmpty;

  String describe() => isEmpty ? '' : '$collection/$docId';

  Map<String, Object?> toMap() =>
      isEmpty ? <String, Object?>{} : <String, Object?>{'collection': collection, 'docId': docId};

  static MediaAttachment fromMap(Map<String, dynamic> map) => MediaAttachment(
        collection: readStringOrEmpty(map, 'collection'),
        docId: readStringOrEmpty(map, 'docId'),
      );
}

/// One row of the `media_objects` collection: the index that says which bucket keys are live.
///
/// The orphan scan trusts this collection, so an object that was uploaded without a row looks
/// orphaned even when a product points at it. That is why the pipeline writes the row as part of
/// the upload and never reports success without it.
final class MediaObjectRecord {
  const MediaObjectRecord({
    required this.id,
    required this.storagePath,
    required this.bucket,
    required this.kind,
    required this.ownerId,
    required this.state,
    this.url = '',
    this.altText = '',
    this.order = 0,
    this.isPrimary = false,
    this.attachment,
    this.holders = const <String>[],
    this.width,
    this.height,
    this.sizeBytes,
    this.contentType = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String storagePath;
  final String bucket;
  final MediaKind kind;
  final String ownerId;
  final MediaObjectState state;
  final String url;
  final String altText;
  final int order;
  final bool isPrimary;
  final MediaAttachment? attachment;

  /// Every document that currently embeds a reference to this object (`products/abc`,
  /// `categories/xyz`).
  ///
  /// A row has exactly one `attachedTo` because it is the *last* writer, but a duplicated product
  /// copies its `images` array verbatim and then two documents legitimately point at the same
  /// bytes. This list is what makes that visible: an object with more than one live holder may not
  /// be deleted just because one of them dropped it.
  final List<String> holders;
  final int? width;
  final int? height;
  final int? sizeBytes;
  final String contentType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory MediaObjectRecord.fromRef(
    MediaRef ref, {
    required String ownerId,
    required MediaObjectState state,
    MediaAttachment? attachment,
    String contentType = '',
    DateTime? now,
  }) =>
      MediaObjectRecord(
        id: ref.id,
        storagePath: ref.storagePath,
        bucket: ref.bucket,
        kind: ref.kind,
        ownerId: ownerId,
        state: state,
        url: ref.url,
        altText: ref.altText,
        order: ref.order,
        isPrimary: ref.isPrimary,
        attachment: attachment,
        width: ref.width,
        height: ref.height,
        sizeBytes: ref.sizeBytes,
        contentType: contentType,
        createdAt: now,
        updatedAt: now,
      );

  MediaRef toRef() => MediaRef(
        id: id,
        url: url,
        storagePath: storagePath,
        bucket: bucket,
        altText: altText,
        order: order,
        kind: kind,
        isPrimary: isPrimary,
        width: width,
        height: height,
        sizeBytes: sizeBytes,
      );

  MediaObjectRecord copyWith({
    MediaObjectState? state,
    String? url,
    String? altText,
    int? order,
    bool? isPrimary,
    MediaAttachment? attachment,
    DateTime? updatedAt,
  }) =>
      MediaObjectRecord(
        id: id,
        storagePath: storagePath,
        bucket: bucket,
        kind: kind,
        ownerId: ownerId,
        state: state ?? this.state,
        url: url ?? this.url,
        altText: altText ?? this.altText,
        order: order ?? this.order,
        isPrimary: isPrimary ?? this.isPrimary,
        attachment: attachment ?? this.attachment,
        holders: holders,
        width: width,
        height: height,
        sizeBytes: sizeBytes,
        contentType: contentType,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() {
    final attach = attachment;
    return compact(<String, Object?>{
      'id': id,
      'storagePath': storagePath,
      'bucket': bucket,
      'kind': kind.code,
      'ownerId': ownerId,
      'state': state.code,
      'url': url,
      'altText': altText,
      'order': order,
      'isPrimary': isPrimary,
      'attachedTo': attach == null || attach.isEmpty ? null : attach.toMap(),
      // Only written when non-empty: `upsert` merges, and a re-upsert from the replace flow must not
      // erase the holder list that documents (not this row's writer) built up.
      'holders': holders.isEmpty ? null : holders,
      'width': width,
      'height': height,
      'sizeBytes': sizeBytes,
      'contentType': contentType,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    });
  }

  factory MediaObjectRecord.fromMap(Map<String, dynamic> map, {String? id}) => MediaObjectRecord(
        id: id ?? readStringOrEmpty(map, 'id'),
        storagePath: readStringOrEmpty(map, 'storagePath'),
        bucket: readStringOrEmpty(map, 'bucket'),
        kind: mediaKindFromCode(readStringOrEmpty(map, 'kind')),
        ownerId: readStringOrEmpty(map, 'ownerId'),
        state: MediaObjectState.fromCode(readStringOrEmpty(map, 'state')),
        url: readStringOrEmpty(map, 'url'),
        altText: readStringOrEmpty(map, 'altText'),
        order: readIntOrZero(map, 'order'),
        isPrimary: readBool(map, 'isPrimary'),
        attachment: map['attachedTo'] is Map
            ? MediaAttachment.fromMap(readMap(map, 'attachedTo'))
            : null,
        holders: readStringList(map, 'holders'),
        width: readInt(map, 'width'),
        height: readInt(map, 'height'),
        sizeBytes: readInt(map, 'sizeBytes'),
        contentType: readStringOrEmpty(map, 'contentType'),
        createdAt: readDate(map, 'createdAt'),
        updatedAt: readDate(map, 'updatedAt'),
      );
}

/// Bookkeeping port for the pipeline. Kept behind an interface so the repository, the orphan scan
/// and the tests all speak to the same contract and no screen imports Firestore.
abstract interface class MediaObjectLedger {
  bool get isAvailable;

  /// What to show when [isAvailable] is false: an unbookkept upload is an unfindable object.
  String get unavailableReason;

  /// Idempotent write keyed on [MediaObjectRecord.id]; a retried upload merges into the same row
  /// instead of creating a twin.
  Future<void> upsert(MediaObjectRecord record);

  Future<void> setState(
    List<String> ids,
    MediaObjectState state, {
    MediaAttachment? attachment,
  });

  Future<MediaObjectRecord?> byId(String id);

  Future<List<MediaObjectRecord>> liveRecordsSharingPath(
    String storagePath, {
    required String exceptId,
  });

  /// Documents other than [exceptHolder] that still claim this object.
  ///
  /// The delete path asks this before removing bytes: an object a duplicated product also embeds is
  /// live data for that other copy, whatever the calling form believes it is detaching.
  Future<List<String>> otherHolders(String id, {String? exceptHolder});

  /// Drops [holder] from an object's holder list. When nothing claims it any more the row goes to
  /// `detached`, which is what lets a later orphan scan propose it.
  Future<void> releaseHolder(List<String> ids, String holder);

  /// Every path a live row claims. `staging` counts as live: the orphan scan must not offer to
  /// delete an upload that is mid-flight in someone else's admin form.
  Future<Set<String>> referencedPaths({int maxDocs = MediaLimits.ledgerMaxDocs});

  Future<void> remove(List<String> ids);
}

/// Firestore-backed ledger.
///
/// Writes go through [FirestoreMediaGuard] so a ledger row can never become a second home for the
/// bytes it is meant to point at.
final class FirestoreMediaObjectLedger implements MediaObjectLedger {
  FirestoreMediaObjectLedger({FirebaseFirestore? database})
      : _databaseOverride = database;

  final FirebaseFirestore? _databaseOverride;

  static const String collectionPath = 'media_objects';

  FirebaseFirestore get _db => _databaseOverride ?? AppBootstrap.db;

  @override
  bool get isAvailable => Env.hasFirebase || _databaseOverride != null;

  @override
  String get unavailableReason => FirestoreUnavailableReason.text;

  @override
  Future<void> upsert(MediaObjectRecord record) async {
    _assertAvailable();
    final payload = record.toMap();
    FirestoreMediaGuard.ensureNoImageBytes(payload, where: '$collectionPath/${record.id}');
    // A merge keeps `createdAt` from the first write: retries and replacements must not move a
    // row's creation date, or the TTL sweep would keep resurrecting stale objects.
    final data = Map<String, Object?>.of(payload)
      ..['updatedAt'] = Timestamp.fromDate(record.updatedAt ?? DateTime.now());
    await _db.collection(collectionPath).doc(record.id).set(
          data.cast<String, dynamic>(),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> setState(
    List<String> ids,
    MediaObjectState state, {
    MediaAttachment? attachment,
  }) async {
    _assertAvailable();
    if (ids.isEmpty) return;
    final batch = _db.batch();
    final now = Timestamp.fromDate(DateTime.now());
    final attach = attachment;
    for (final id in ids) {
      final update = <String, Object?>{
        'state': state.code,
        'updatedAt': now,
        // Detaching must clear the owner, otherwise a later delete cannot tell whether the object
        // is still pointed at by something.
        'attachedTo': state == MediaObjectState.attached && attach != null && !attach.isEmpty
            ? attach.toMap()
            : null,
      };
      if (state == MediaObjectState.attached && attach != null && !attach.isEmpty) {
        // A second document claiming the same object (a duplicated product) *adds* to the list
        // instead of replacing it, which is the only way the shared-bytes case stays visible.
        update['holders'] = FieldValue.arrayUnion(<Object?>[attach.describe()]);
      }
      batch.set(
        _db.collection(collectionPath).doc(id),
        update.cast<String, Object?>(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  @override
  Future<MediaObjectRecord?> byId(String id) async {
    _assertAvailable();
    if (id.isEmpty) return null;
    final snapshot = await _db.collection(collectionPath).doc(id).get();
    final data = snapshot.data();
    if (data == null || !snapshot.exists) return null;
    return MediaObjectRecord.fromMap(data, id: snapshot.id);
  }

  @override
  Future<List<MediaObjectRecord>> liveRecordsSharingPath(
    String storagePath, {
    required String exceptId,
  }) async {
    _assertAvailable();
    if (storagePath.isEmpty) return const <MediaObjectRecord>[];
    final snapshot = await _db
        .collection(collectionPath)
        .where('storagePath', isEqualTo: storagePath)
        .limit(MediaLimits.deleteBatchSize)
        .get();
    return snapshot.docs
        .where((doc) => doc.id != exceptId)
        .map((doc) => MediaObjectRecord.fromMap(doc.data(), id: doc.id))
        .where((record) => record.state != MediaObjectState.detached)
        .toList(growable: false);
  }

  @override
  Future<List<String>> otherHolders(String id, {String? exceptHolder}) async {
    _assertAvailable();
    if (id.isEmpty) return const <String>[];
    final record = await byId(id);
    if (record == null) return const <String>[];
    final ignore = exceptHolder == null || exceptHolder.isEmpty
        ? const <String>{}
        : <String>{exceptHolder};
    return record.holders
        .where((holder) => holder.isNotEmpty && !ignore.contains(holder))
        .toList(growable: false);
  }

  @override
  Future<void> releaseHolder(List<String> ids, String holder) async {
    _assertAvailable();
    if (ids.isEmpty || holder.isEmpty) return;
    for (final id in ids) {
      final record = await byId(id);
      if (record == null) continue;
      final remaining =
          record.holders.where((value) => value.isNotEmpty && value != holder).toList(growable: false);
      final update = <String, Object?>{
        'holders': remaining,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        // The registered owner leaving must not stay on the row: `attachedTo` would then name a
        // document that no longer lists this image, and the next delete would excuse the wrong one.
        if (record.attachment?.describe() == holder) 'attachedTo': null,
      };
      if (remaining.isEmpty && record.state == MediaObjectState.attached) {
        update['state'] = MediaObjectState.detached.code;
      }
      await _db.collection(collectionPath).doc(id).update(update.cast<String, dynamic>());
    }
  }

  @override
  Future<Set<String>> referencedPaths({int maxDocs = MediaLimits.ledgerMaxDocs}) async {
    _assertAvailable();
    final paths = <String>{};
    DocumentSnapshot<Map<String, dynamic>>? after;
    var read = 0;
    while (read < maxDocs) {
      // Ordering by document id needs no composite index; the state filter is applied in Dart so a
      // stray `detached` row cannot make this query demand an index that was never declared.
      final query = _db
          .collection(collectionPath)
          .orderBy(FieldPath.documentId)
          .limit(MediaLimits.ledgerPageSize);
      final results = await (after == null ? query : query.startAfterDocument(after)).get();
      if (results.docs.isEmpty) break;
      for (final doc in results.docs) {
        final record = MediaObjectRecord.fromMap(doc.data(), id: doc.id);
        if (record.state != MediaObjectState.detached && record.storagePath.isNotEmpty) {
          paths.add(record.storagePath);
        }
      }
      read += results.docs.length;
      after = results.docs.last;
      if (results.docs.length < MediaLimits.ledgerPageSize) break;
    }
    return paths;
  }

  @override
  Future<void> remove(List<String> ids) async {
    _assertAvailable();
    if (ids.isEmpty) return;
    for (var start = 0; start < ids.length; start += MediaLimits.deleteBatchSize) {
      final batch = _db.batch();
      final slice = ids.sublist(
        start,
        start + MediaLimits.deleteBatchSize > ids.length ? ids.length : start + MediaLimits.deleteBatchSize,
      );
      for (final id in slice) {
        batch.delete(_db.collection(collectionPath).doc(id));
      }
      await batch.commit();
    }
  }

  void _assertAvailable() {
    if (isAvailable) return;
    throw MediaFailure(
      'Cannot record the upload in Firestore — ${Env.missingKeys().join(' and ')} are not '
      'configured, so media_objects would drift out of sync with the bucket.',
    );
  }
}

/// Ledger used when Firebase is not configured. Fails loudly: an object with no row is invisible
/// to the orphan scan and undeletable by the replace flow, which is precisely the silent-corruption
/// state the contract forbids.
final class UnavailableMediaObjectLedger implements MediaObjectLedger {
  const UnavailableMediaObjectLedger();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => FirestoreUnavailableReason.text;

  @override
  Future<void> upsert(MediaObjectRecord record) async =>
      throw MediaFailure('Cannot record media upload — $unavailableReason');

  @override
  Future<void> setState(List<String> ids, MediaObjectState state, {MediaAttachment? attachment}) async =>
      throw MediaFailure('Cannot update media state — $unavailableReason');

  @override
  Future<MediaObjectRecord?> byId(String id) async =>
      throw MediaFailure('Cannot read media records — $unavailableReason');

  @override
  Future<List<MediaObjectRecord>> liveRecordsSharingPath(
    String storagePath, {
    required String exceptId,
  }) async =>
      throw MediaFailure('Cannot read media records — $unavailableReason');

  @override
  Future<List<String>> otherHolders(String id, {String? exceptHolder}) async =>
      throw MediaFailure('Cannot read media records — $unavailableReason');

  @override
  Future<void> releaseHolder(List<String> ids, String holder) async =>
      throw MediaFailure('Cannot update media records — $unavailableReason');

  @override
  Future<Set<String>> referencedPaths({int maxDocs = MediaLimits.ledgerMaxDocs}) async =>
      throw MediaFailure('Cannot scan media references — $unavailableReason');

  @override
  Future<void> remove(List<String> ids) async =>
      throw MediaFailure('Cannot delete media records — $unavailableReason');
}

abstract final class FirestoreUnavailableReason {
  static String get text {
    final missing = Env.missingKeys().where((key) => key.startsWith('FIREBASE')).toList();
    if (missing.isEmpty) return 'Firestore is not initialised in this build.';
    return '${missing.join(' and ')} must be supplied with --dart-define.';
  }
}
