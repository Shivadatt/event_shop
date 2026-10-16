import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/media/media_id.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/services/media/media_object_ledger.dart';
import 'package:om_events/app/core/services/media/media_optimise_gateway.dart';
import 'package:om_events/app/core/services/media/media_path_policy.dart';
import 'package:om_events/app/core/services/media/media_validator.dart';
import 'package:om_events/app/core/services/media/supabase_storage_service.dart';
import 'package:om_events/data/models/media_ref.dart';
// `storage_client` is a transitive dependency; `supabase_flutter` re-exports it, so the retry
// controller is taken from the direct dependency and the `depend_on_referenced_packages` lint stays
// clean (importing the transitive package directly would work but hides the coupling).
import 'package:supabase_flutter/supabase_flutter.dart' show StorageRetryController;

/// Where an upload has reached. Drives both the progress bar and which recovery is possible.
enum MediaUploadStage {
  queued,
  validating,
  preparing,
  staging,
  optimising,
  promoting,
  recording,
  completed,
  failed,
  cancelled;

  bool get isTerminal =>
      this == MediaUploadStage.completed ||
      this == MediaUploadStage.failed ||
      this == MediaUploadStage.cancelled;

  bool get isInFlight => !isTerminal;

  /// Phase milestones, not a byte count.
  ///
  /// `storage_client` 2.8.1 exposes no upload-progress callback on `uploadBinary`, so a percentage
  /// of bytes transferred cannot be reported honestly from this layer. What can be reported is
  /// which stage the object has reached, which is what an admin actually needs to know when an
  /// upload stalls. The bytes-still-arriving case shows as "Uploading…" and stays there.
  double get fraction => switch (this) {
        MediaUploadStage.queued => 0,
        MediaUploadStage.validating => 0.05,
        MediaUploadStage.preparing => 0.12,
        MediaUploadStage.staging => 0.45,
        MediaUploadStage.optimising => 0.6,
        MediaUploadStage.promoting => 0.78,
        MediaUploadStage.recording => 0.92,
        MediaUploadStage.completed => 1,
        MediaUploadStage.failed => 1,
        MediaUploadStage.cancelled => 1,
      };

  String get label => switch (this) {
        MediaUploadStage.queued => 'Queued',
        MediaUploadStage.validating => 'Checking the file',
        MediaUploadStage.preparing => 'Preparing the upload',
        MediaUploadStage.staging => 'Uploading',
        MediaUploadStage.optimising => 'Optimising on the server',
        MediaUploadStage.promoting => 'Publishing',
        MediaUploadStage.recording => 'Recording the reference',
        MediaUploadStage.completed => 'Done',
        MediaUploadStage.failed => 'Failed',
        MediaUploadStage.cancelled => 'Cancelled',
      };
}

final class MediaUploadProgress {
  const MediaUploadProgress({
    required this.stage,
    required this.message,
    this.taskId = '',
    this.storagePath = '',
  });

  final MediaUploadStage stage;
  final String message;
  final String taskId;

  /// The object key this attempt is writing to. Exposed because a stuck upload is only
  /// debuggable if the admin can see which key the bucket should contain.
  final String storagePath;

  double get fraction => stage.fraction;

  bool get isDone => stage == MediaUploadStage.completed;
}

/// The fixed coordinates of one upload. Decided once and reused by every retry, which is what
/// makes "retry" mean "overwrite my own key" instead of "put a second copy in the bucket".
final class MediaUploadPlan {
  MediaUploadPlan({
    required this.mediaId,
    required this.stagingPath,
    required this.finalPath,
    required this.contentType,
    required this.extension,
    this.width,
    this.height,
    this.note,
  });

  final String mediaId;
  final String stagingPath;
  String finalPath;
  final String contentType;
  final String extension;
  int? width;
  int? height;
  final String? note;
}

/// One upload the admin UI can watch, cancel and retry.
final class MediaUploadTask {
  MediaUploadTask({
    required this.id,
    required Uint8List bytes,
    required this.fileName,
    required this.mimeType,
    required this.kind,
    required this.ownerId,
    required this.altText,
    required this.order,
    required this.alreadyAttached,
    this.entityKey,
    this.attachment,
    this.onProgress,
  }) : _bytes = bytes;

  final String id;
  final String fileName;
  final String mimeType;
  final MediaKind kind;
  final String ownerId;
  final String altText;
  final int order;
  final int alreadyAttached;
  final String? entityKey;
  final MediaAttachment? attachment;
  final void Function(double fraction)? onProgress;

  Uint8List? _bytes;
  MediaUploadPlan? _plan;
  MediaUploadStage _stage = MediaUploadStage.queued;
  String _message = 'Waiting to start';
  bool _cancelRequested = false;
  bool _touchedStaging = false;
  bool _promoted = false;
  StorageRetryController? _retryController;
  Completer<MediaRef>? _completer;
  Future<MediaRef>? _settled;
  final StreamController<MediaUploadProgress> _updates =
      StreamController<MediaUploadProgress>.broadcast();

  /// Bytes are held only while the attempt can still be retried; a completed upload releases them
  /// so a ten-image gallery does not pin eighty megabytes of browser memory.
  Uint8List? get bytes => _bytes;

  MediaUploadPlan? get plan => _plan;
  MediaUploadStage get stage => _stage;
  String get message => _message;
  bool get isTerminal => _stage.isTerminal;
  bool get isInFlight => !_stage.isTerminal;
  bool get canRetry => _stage == MediaUploadStage.failed || _stage == MediaUploadStage.cancelled;
  bool get hasBytes => _bytes != null;
  bool get touchedStaging => _touchedStaging;
  bool get promoted => _promoted;
  bool get cancelRequested => _cancelRequested;
  String? get storagePath => _plan?.finalPath;
  MediaRef? result;

  /// The outcome of the *current* attempt. A late reader gets the settled result instead of a
  /// future that hangs forever, while a retry resets it to the new attempt.
  Future<MediaRef> get future {
    final settled = _settled;
    if (settled != null) return settled;
    return _pendingCompleter().future;
  }

  Stream<MediaUploadProgress> get updates => _updates.stream;

  StorageRetryController ensureRetryController() => _retryController ??= StorageRetryController();

  /// Stops the SDK's own retry loop so an in-flight transfer aborts instead of silently resuming
  /// after the admin pressed Cancel.
  void markCancelled() {
    _cancelRequested = true;
    _retryController?.cancel();
  }

  void releaseBytes() => _bytes = null;

  void _beginAttempt() {
    _settled = null;
    _pendingCompleter();
  }

  /// A completed completer cannot be reused, so the next attempt gets a fresh one. The attached
  /// no-op listener exists only so a failure nobody awaits (the gallery listens to [updates]) does
  /// not surface as an uncaught zone error; awaiting [future] still receives the same error.
  Completer<MediaRef> _pendingCompleter() {
    final existing = _completer;
    if (existing != null && !existing.isCompleted) return existing;
    final next = Completer<MediaRef>();
    next.future.then<void>((_) {}, onError: (_) {});
    _completer = next;
    return next;
  }

  void _settleSuccess(Completer<MediaRef> completer, MediaRef ref) {
    if (completer.isCompleted) return;
    completer.complete(ref);
    _settled = completer.future;
  }

  void _settleError(Completer<MediaRef> completer, MediaFailure failure) {
    if (completer.isCompleted) return;
    completer.completeError(failure);
    _settled = completer.future;
  }

  void closeStreams() {
    if (!_updates.isClosed) unawaited(_updates.close());
  }
}

/// Runs the upload pipeline: validate -> ledger staging row -> tmp upload -> (optional server
/// optimisation) -> promote -> ledger attach -> [MediaRef].
///
/// Failure at any point stops before the publishable path is ever referenced by a document, so a
/// half-done upload can only ever look like an orphan, never like a product with a broken image.
final class MediaUploader {
  MediaUploader({
    required this.service,
    required this.validator,
    required this.paths,
    required this.ledger,
    MediaOptimiseGateway optimiseGateway = const PassthroughOptimiseGateway(),
  }) : gateway = optimiseGateway;

  /// Finished uploads keep their id, path and error text so an admin can retry or read the reason,
  /// but holding the last hundred gallery uploads alive forever is a browser-memory leak.
  static const int keptFinishedTasks = 40;

  final SupabaseStorageService service;
  final MediaValidator validator;
  final MediaPathPolicy paths;
  final MediaObjectLedger ledger;
  final MediaOptimiseGateway gateway;

  final Map<String, MediaUploadTask> _tasks = <String, MediaUploadTask>{};

  Iterable<MediaUploadTask> get inFlight => _tasks.values.where((task) => task.isInFlight);

  bool get hasInFlight => _tasks.values.any((task) => task.isInFlight);

  MediaUploadTask? byId(String taskId) => _tasks[taskId];

  /// Starts an upload and returns immediately, so the admin gallery can show ten rows progressing
  /// independently rather than blocking on one await.
  MediaUploadTask enqueue({
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
    final task = MediaUploadTask(
      id: 'up-${MediaId.short()}',
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      kind: kind,
      ownerId: ownerId,
      altText: altText,
      order: order,
      alreadyAttached: alreadyAttached,
      entityKey: entityKey,
      attachment: attachment,
      onProgress: onProgress,
    );
    _tasks[task.id] = task;
    _pruneFinished();
    _start(task, reusePlan: false);
    return task;
  }

  /// Awaits an enqueue — the shape [MediaRepository.upload] needs.
  Future<MediaRef> uploadNow({
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
  }) =>
      enqueue(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        kind: kind,
        ownerId: ownerId,
        altText: altText,
        order: order,
        alreadyAttached: alreadyAttached,
        entityKey: entityKey,
        attachment: attachment,
        onProgress: onProgress,
      ).future;

  /// Retries the same task: same media id, same staging key, same final key.
  Future<MediaRef> retry(MediaUploadTask task) {
    if (task.bytes == null) {
      throw const MediaFailure(
        'That upload can no longer be retried — the file was released from memory. '
        'Pick the image again.',
      );
    }
    _tasks[task.id] ??= task;
    task
      .._cancelRequested = false
      .._retryController = null;
    _start(task, reusePlan: true);
    return task.future;
  }

  /// Overwrites the object at an existing reference's path, keeping the id and the path stable so
  /// no document ever points at a deleted object.
  Future<MediaRef> replace({
    required MediaRef existing,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? altText,
    void Function(double fraction)? onProgress,
  }) async {
    if (existing.storagePath.isEmpty) {
      throw const MediaFailure(
        'That image has no storage path, so it cannot be replaced. Remove it and upload again.',
      );
    }
    final analysis = validator.analyse(
      bytes: bytes,
      kind: existing.kind,
      altText: altText ?? existing.altText,
      // A replacement can never push the entity over its cap: the old image is still counted.
      alreadyAttached: 0,
      fileName: fileName,
      declaredMimeType: mimeType,
    );
    if (!analysis.isAccepted) {
      throw MediaFailure(analysis.error ?? 'That file cannot replace this image.');
    }
    final path = existing.storagePath;
    _report(onProgress, MediaUploadStage.staging);
    await service.putBytes(
      path: path,
      bytes: bytes,
      contentType: analysis.contentType,
      cacheControl: MediaLimits.finalObjectCacheControl,
    );
    final visibility = await service.resolveVisibility();
    final url = visibility == MediaBucketVisibility.private
        ? existing.url
        : service.publicUrl(path);
    final replaced = MediaRef(
      id: existing.id,
      url: url,
      storagePath: path,
      bucket: existing.bucket.isEmpty ? service.bucketId : existing.bucket,
      altText: (altText ?? existing.altText).trim(),
      order: existing.order,
      kind: existing.kind,
      isPrimary: existing.isPrimary,
      width: analysis.width,
      height: analysis.height,
      sizeBytes: analysis.byteLength,
    );
    _report(onProgress, MediaUploadStage.recording);
    await ledger.upsert(
      MediaObjectRecord.fromRef(
        replaced,
        ownerId: replaced.id,
        state: MediaObjectState.attached,
        contentType: analysis.contentType,
      ),
    );
    // The CDN caches the old bytes under this exact key. A service-role purge is the real fix
    // (docs/supabase-storage.md); this note is what the admin UI shows so a "my image did not
    // change" ticket is understood rather than chased.
    debugPrint('Replaced $path; the CDN edge may serve the old bytes for up to 24h without a purge.');
    _report(onProgress, MediaUploadStage.completed);
    return replaced;
  }

  /// Requests cancellation.
  ///
  /// The stage flips immediately so the UI has an answer, but the *attempt* stays the single writer
  /// of the future: it aborts the in-flight transfer through the retry controller and then cleans
  /// up its own staged object. If the bytes had already been promoted, the attempt legitimately
  /// completes with a published reference rather than lying about a publish that happened.
  void cancel(MediaUploadTask task) {
    if (task.isTerminal) return;
    task.markCancelled();
    _advance(task, MediaUploadStage.cancelled, 'Cancelled — removing the staged copy',
        path: task.storagePath);
  }

  void dispose() {
    for (final task in _tasks.values) {
      task.closeStreams();
    }
    _tasks.clear();
  }

  void _start(MediaUploadTask task, {required bool reusePlan}) {
    task._beginAttempt();
    unawaited(_attempt(task, reusePlan: reusePlan));
  }

  Future<void> _attempt(MediaUploadTask task, {required bool reusePlan}) async {
    final completer = task._completer;
    if (completer == null) return;
    try {
      final bytes = task.bytes;
      if (bytes == null) {
        throw const MediaFailure('The file is no longer available in memory. Pick it again.');
      }

      _advance(task, MediaUploadStage.validating, 'Checking the file');
      final analysis = validator.analyse(
        bytes: bytes,
        kind: task.kind,
        altText: task.altText,
        alreadyAttached: task.alreadyAttached,
        fileName: task.fileName,
        declaredMimeType: task.mimeType,
      );
      if (!analysis.isAccepted) {
        throw MediaFailure(analysis.error ?? 'That file cannot be uploaded.');
      }
      _assertNotCancelled(task);

      var plan = task.plan;
      if (plan == null || !reusePlan) {
        final writer = await service.writerUid();
        // Review objects are keyed by the writer because that is the only subject the storage
        // policy can verify; the Firebase author id lives in the ledger row.
        final entityKey = task.kind == MediaKind.review
            ? writer
            : (task.entityKey == null || task.entityKey!.isEmpty ? task.ownerId : task.entityKey!);
        final mediaId = MediaId.generate();
        plan = MediaUploadPlan(
          mediaId: mediaId,
          stagingPath: paths.stagingPath(
            writerUid: writer,
            mediaId: mediaId,
            extension: analysis.extension,
          ),
          finalPath: paths.entityPath(
            kind: task.kind,
            entityKey: entityKey,
            mediaId: mediaId,
            extension: analysis.extension,
            order: task.order,
          ),
          contentType: analysis.contentType,
          extension: analysis.extension,
          width: analysis.width,
          height: analysis.height,
          note: analysis.note,
        );
        task._plan = plan;
      }
      _advance(task, MediaUploadStage.preparing, 'Preparing the upload', path: plan.finalPath);

      // The ledger row is written *before* the bytes leave, so an object can never exist without a
      // record — the state the orphan scan would otherwise read as "unreferenced, delete it".
      await _recordStaging(task, plan);
      _assertNotCancelled(task);

      _advance(task, MediaUploadStage.staging, 'Uploading', path: plan.finalPath);
      await service.putBytes(
        path: plan.stagingPath,
        bytes: bytes,
        contentType: plan.contentType,
        cacheControl: MediaLimits.stagingCacheControl,
        cancel: task.ensureRetryController(),
      );
      task._touchedStaging = true;
      _assertNotCancelled(task);

      if (gateway.isEnabled) {
        _advance(task, MediaUploadStage.optimising, 'Optimising on the server',
            path: plan.finalPath);
        final optimised = await gateway.optimise(
          MediaOptimiseRequest(
            stagingPath: plan.stagingPath,
            finalPath: plan.finalPath,
            mediaId: plan.mediaId,
            bucket: service.bucketId,
            kind: task.kind,
            byteLength: bytes.lengthInBytes,
            contentType: plan.contentType,
            width: plan.width,
            height: plan.height,
          ),
        );
        final moved = optimised.finalPath;
        if (moved != null && moved.isNotEmpty) {
          if (!paths.isManagedPath(moved)) {
            throw MediaFailure(
              'The optimisation step returned a path outside the managed prefixes: $moved.',
            );
          }
          plan.finalPath = moved;
        }
        plan.width = optimised.width ?? plan.width;
        plan.height = optimised.height ?? plan.height;
        _assertNotCancelled(task);
      }

      _advance(task, MediaUploadStage.promoting, 'Publishing', path: plan.finalPath);
      final alreadyPublished = await service.exists(plan.finalPath);
      if (alreadyPublished) {
        // A previous attempt moved this exact key and lost its response. Reuse it rather than
        // creating a `(2)` copy: the plan is the idempotency key.
        await _abandonStaging(task, onlyIfUnpublished: true);
      } else {
        await service.moveTo(fromPath: plan.stagingPath, toPath: plan.finalPath);
        task._promoted = true;
      }
      _assertNotCancelled(task);

      _advance(task, MediaUploadStage.recording, 'Recording the reference', path: plan.finalPath);
      final visibility = await service.resolveVisibility();
      final ref = _refFor(task, plan, bytes, private: visibility == MediaBucketVisibility.private);
      await ledger.upsert(
        MediaObjectRecord.fromRef(
          ref,
          ownerId: task.ownerId,
          state: MediaObjectState.attached,
          attachment: task.attachment,
          contentType: plan.contentType,
        ),
      );

      task.result = ref;
      task.releaseBytes();
      _advance(task, MediaUploadStage.completed, 'Published', path: plan.finalPath);
      task._settleSuccess(completer, ref);
    } on MediaFailure catch (failure) {
      await _abandonStaging(task);
      await _rollbackPromoted(task);
      _finishFailure(task, completer, failure);
    } catch (error) {
      final failure = service.failure('upload ${task.fileName}', error);
      await _abandonStaging(task);
      await _rollbackPromoted(task);
      _finishFailure(task, completer, failure);
    }
  }

  MediaRef _refFor(
    MediaUploadTask task,
    MediaUploadPlan plan,
    Uint8List bytes, {
    required bool private,
  }) =>
      MediaRef(
        id: plan.mediaId,
        // A private bucket has no permanent URL to store. `url` stays empty and the resolver fills
        // it at render time; a signed link written into Firestore would expire silently.
        url: private ? '' : service.publicUrl(plan.finalPath),
        storagePath: plan.finalPath,
        bucket: service.bucketId,
        altText: task.altText.trim(),
        order: task.order,
        kind: task.kind,
        isPrimary: task.order == 0,
        width: plan.width,
        height: plan.height,
        sizeBytes: bytes.lengthInBytes,
      );

  Future<void> _recordStaging(MediaUploadTask task, MediaUploadPlan plan) async {
    if (!ledger.isAvailable) {
      throw MediaFailure('Cannot record the upload — ${ledger.unavailableReason}');
    }
    await ledger.upsert(
      MediaObjectRecord(
        id: plan.mediaId,
        storagePath: plan.stagingPath,
        bucket: service.bucketId,
        kind: task.kind,
        ownerId: task.ownerId,
        state: MediaObjectState.staging,
        altText: task.altText.trim(),
        order: task.order,
        contentType: plan.contentType,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Removes the staged object after a cancel or a failed attempt. Best effort: a cleanup failure
  /// must not mask the real error, and the `tmp/` lifecycle rule is the backstop.
  Future<void> _abandonStaging(MediaUploadTask task, {bool onlyIfUnpublished = false}) async {
    final plan = task.plan;
    if (plan == null || !task.touchedStaging || task.promoted) return;
    if (onlyIfUnpublished && await _safeExists(plan.finalPath)) return;
    try {
      await service.remove(<String>[plan.stagingPath]);
    } catch (error) {
      debugPrint('Staged object cleanup failed for ${plan.stagingPath}: ${error.runtimeType}');
    }
    await _detachRow(plan.mediaId);
  }

  /// Removes an object this attempt promoted but never finished recording.
  ///
  /// Promotion is the step immediately before the reference is handed to a document, so an attempt
  /// that fails after it leaves bytes no document can point at — and they are now outside the `tmp/`
  /// lifecycle rule, which is why the rollback deletes them instead of waiting for a scan. A row the
  /// ledger already reports as `attached` is left alone: something has that reference, and deleting
  /// it would break a live page.
  Future<void> _rollbackPromoted(MediaUploadTask task) async {
    final plan = task.plan;
    if (plan == null || !task.promoted) return;
    try {
      final record = await ledger.byId(plan.mediaId);
      if (record != null && record.state == MediaObjectState.attached) return;
      await service.remove(<String>[plan.finalPath]);
    } catch (error) {
      debugPrint(
        'Promoted object rollback failed for ${plan.finalPath}: ${error.runtimeType}',
      );
    }
    await _detachRow(plan.mediaId);
  }

  Future<bool> _safeExists(String path) async {
    try {
      return await service.exists(path);
    } catch (_) {
      return false;
    }
  }

  Future<void> _detachRow(String mediaId) async {
    if (!ledger.isAvailable) return;
    try {
      await ledger.setState(<String>[mediaId], MediaObjectState.detached);
    } catch (error) {
      debugPrint('Ledger detach failed for $mediaId: ${error.runtimeType}');
    }
  }

  void _assertNotCancelled(MediaUploadTask task) {
    if (task.cancelRequested) {
      throw const MediaFailure('The upload was cancelled before it was published.');
    }
  }

  /// A cancelled task stays cancelled; only the cleanup failure text changes. This keeps the
  /// gallery from showing "Failed" for something the admin deliberately stopped, which would
  /// otherwise invite a pointless retry.
  void _finishFailure(MediaUploadTask task, Completer<MediaRef> completer, MediaFailure failure) {
    final cancelled = task.cancelRequested || task.stage == MediaUploadStage.cancelled;
    if (cancelled) {
      if (task.stage != MediaUploadStage.cancelled) {
        _advance(task, MediaUploadStage.cancelled, 'Cancelled', path: task.storagePath);
      }
    } else {
      _advance(task, MediaUploadStage.failed, failure.message, path: task.storagePath);
    }
    task._settleError(completer, failure);
  }

  void _advance(
    MediaUploadTask task,
    MediaUploadStage stage,
    String message, {
    String? path,
  }) {
    task._stage = stage;
    task._message = message;
    final progress = MediaUploadProgress(
      stage: stage,
      message: message,
      taskId: task.id,
      storagePath: path ?? task.storagePath ?? '',
    );
    task.onProgress?.call(stage.fraction);
    if (!task._updates.isClosed) task._updates.add(progress);
  }

  void _report(void Function(double)? onProgress, MediaUploadStage stage) =>
      onProgress?.call(stage.fraction);

  /// Drops the oldest finished uploads once the map exceeds [keptFinishedTasks]. Insertion order is
  /// a `LinkedHashMap` guarantee, so the oldest are always first.
  void _pruneFinished() {
    final excess = _tasks.length - keptFinishedTasks;
    if (excess <= 0) return;
    final doomed = <String>[];
    for (final task in _tasks.values) {
      if (doomed.length >= excess) break;
      if (task.isTerminal) doomed.add(task.id);
    }
    for (final id in doomed) {
      _tasks.remove(id)?.closeStreams();
    }
  }
}
