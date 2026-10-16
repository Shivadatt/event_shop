import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/services/media/media_object_ledger.dart';
import 'package:om_events/app/core/services/media/media_signature.dart';
import 'package:om_events/app/core/services/media/media_uploader.dart';
import 'package:om_events/app/core/services/media/media_validator.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/repositories/media_repository.dart';
import 'package:om_events/data/repositories/supabase/supabase_media_repository.dart';

/// What one row of an admin media editor is doing.
enum MediaItemStatus {
  /// Picked from disk, waiting for alt text or for the admin to press upload.
  staged,

  /// Rejected by the client-side gate; the bytes never left the browser.
  rejected,

  /// In the pipeline.
  uploading,

  /// Published: [MediaItem.ref] is the reference to write into the document.
  published,

  /// A transfer or policy failure that can be retried.
  failed,

  /// Stopped by the admin. Retryable, and deliberately not shown as a failure.
  cancelled;

  bool get isBusy => this == MediaItemStatus.uploading;

  bool get isBlocked => this == MediaItemStatus.rejected;
}

/// One image row: the file the admin picked (or the document already had), its alt text, its live
/// upload task, and the URL the editor should display.
final class MediaItem {
  MediaItem({
    required this.id,
    required this.fileName,
    this.bytes,
    this.ref,
    this.altText = '',
    this.status = MediaItemStatus.staged,
    this.message = '',
    this.progress = 0,
  });

  /// An image the document already has.
  MediaItem.fromRef(MediaRef ref)
      : this(
          id: ref.id.isEmpty ? 'ref-${ref.storagePath}' : ref.id,
          fileName: ref.storagePath.split('/').last,
          ref: ref,
          altText: ref.altText,
          status: MediaItemStatus.published,
          message: ref.isPrimary ? 'Primary' : '',
        );

  final String id;
  final String fileName;

  /// Held only while the row can still be uploaded or retried. Released once published so a ten
  /// image gallery does not pin ten originals in browser memory.
  Uint8List? bytes;

  /// The *storable* reference. Its `url` is whatever belongs in Firestore: a permanent public URL,
  /// or empty for a private bucket. Never overwritten with a signed link.
  MediaRef? ref;

  /// Display-only URL (a signed one when the bucket is private). Kept off [ref] precisely so a form
  /// that commits its gallery cannot persist an expiring link by accident.
  String renderUrl = '';

  String altText;
  MediaItemStatus status;
  String message;
  double progress;

  MediaUploadTask? task;
  StreamSubscription<MediaUploadProgress>? _updates;

  bool get isPublished => ref != null && status == MediaItemStatus.published;
  bool get isBusy => status.isBusy;
  bool get canRetry =>
      (status == MediaItemStatus.failed || status == MediaItemStatus.cancelled) && bytes != null;
  bool get hasLocalPreview => bytes != null;

  String get displayUrl {
    final local = renderUrl;
    if (local.isNotEmpty) return local;
    final stored = ref;
    if (stored == null) return '';
    return stored.thumbnailUrl;
  }

  void close() {
    final stream = _updates;
    _updates = null;
    if (stream != null) unawaited(stream.cancel());
  }

  void bindUpdates(Stream<MediaUploadProgress> stream, VoidCallback onChange) {
    close();
    _updates = stream.listen((progress) {
      this.progress = progress.fraction;
      message = progress.message;
      onChange();
    }, onError: (Object _) {
      // The same failure is delivered through `task.future`, which the controller awaits; a second
      // unhandled copy on this stream would show up as a spurious zone error.
    });
  }
}

/// Editor state for one media field, so every admin form gets the same rules, the same progress
/// semantics and the same honest "media storage not configured" behaviour.
///
/// The controller owns the lifecycle the contract requires — pick → validate → upload → publish →
/// reference — and never invents an image or reports success without a published object.
final class MediaEditorController extends ChangeNotifier {
  MediaEditorController({
    required this.kind,
    required this.ownerId,
    required List<MediaRef> existing,
    this.entityKey,
    this.attachmentCollection = '',
    this.defaultAltText = '',
    MediaRepository? repository,
  }) : _repository = repository ?? Get.find<MediaRepository>() {
    for (final ref in existing) {
      _items.add(MediaItem.fromRef(ref));
    }
    for (final ref in existing) {
      if (ref.isPrimary) {
        _primaryId = ref.id;
        break;
      }
    }
    unawaited(_hydratePreviews());
  }

  final MediaKind kind;
  final String ownerId;
  final MediaRepository _repository;

  /// Slug or document id the objects live under. Empty makes the pipeline fall back to [ownerId],
  /// which is right for reviews and wrong for a product gallery an admin wants to find in the bucket.
  final String? entityKey;
  final String attachmentCollection;
  final String defaultAltText;

  final List<MediaItem> _items = <MediaItem>[];
  final List<MediaRef> _removed = <MediaRef>[];
  String _primaryId = '';
  String? _notice;
  bool _disposed = false;

  List<MediaItem> get items => List<MediaItem>.unmodifiable(_items);

  /// Images the admin deleted from the row list. The owning form removes them from the document and
  /// only then calls `delete`/`deleteMany`, so a failed save can never leave a product pointing at
  /// bytes that no longer exist.
  List<MediaRef> get removedRefs => List<MediaRef>.unmodifiable(_removed);

  /// A one-shot message that is not attached to a row (picker errors, over-cap rejections).
  String? get notice => _notice;

  bool get isConfigured => _repository.isConfigured;
  String get statusMessage => MediaConfig.statusMessage;
  String get rulesSummary => MediaLimits.rulesFor(kind).describe();
  int get maxItems => MediaLimits.rulesFor(kind).maxPerEntity;
  int get itemCount => _items.length;
  bool get canAddMore => _items.length < maxItems;
  bool get isBusy => _items.any((item) => item.isBusy);
  bool get hasStaged => _items.any((item) => item.status == MediaItemStatus.staged);
  bool get hasBlocked => _items.any((item) => item.status.isBlocked);

  MediaRepository get repository => _repository;

  /// The queue-shaped view of the repository, when the bound implementation offers one.
  MediaUploadPipeline? get pipeline =>
      _repository is MediaUploadPipeline ? _repository as MediaUploadPipeline : null;

  /// Why a save must wait. Null means the gallery is safe to commit.
  String? get blockReason {
    if (isBusy) return 'Uploads are still running — wait for them or cancel them first.';
    var missingAlt = 0;
    for (final item in _items) {
      if (item.ref == null && item.altText.trim().length < MediaLimits.altTextMinLength) missingAlt++;
    }
    if (missingAlt > 0) return 'Alt text is required on $missingAlt image(s) before saving.';
    return null;
  }

  /// The ordered, single-primary gallery to write into the document.
  ///
  /// Rows are renumbered here rather than trusting the UI order, and exactly one image is marked
  /// primary, because `Product.primaryImage` drives every card in the catalogue.
  List<MediaRef> get publishableRefs {
    final refs = <MediaRef>[];
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      final ref = item.ref;
      if (ref == null) continue;
      final alt = item.altText.trim();
      refs.add(
        ref.copyWith(
          altText: alt.isEmpty ? ref.altText : alt,
          order: index,
          isPrimary: _primaryId.isEmpty ? index == 0 : ref.id == _primaryId,
        ),
      );
    }
    return refs;
  }

  // ------------------------------------------------------------- picking

  /// Opens the file picker. Returns how many rows were added, or null when nothing was picked.
  Future<int?> addFromPicker() async {
    if (!isConfigured) {
      _notice = statusMessage;
      _notify();
      return null;
    }
    if (!canAddMore) {
      _notice = 'This ${kind.code} already holds the maximum of $maxItems images.';
      _notify();
      return 0;
    }

    final List<PlatformFile> picked;
    try {
      // file_picker 13 exposes static pickers and returns an empty list on cancel; the old
      // `FilePicker.platform.pickFiles(...)`/`FilePickerResult` shape no longer exists.
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp', 'avif'],
        dialogTitle: 'Choose ${kind.code} images',
      );
    } catch (error) {
      // `PlatformException` on a browser that refuses the input, a cancelled dialog that threw, or a
      // missing plugin on a desktop build: all of them are "the picker did not work here".
      _notice = 'The file picker could not run in this browser (${error.runtimeType}).';
      _notify();
      return null;
    }
    if (picked.isEmpty) return 0;

    final room = maxItems - _items.length;
    var added = 0;
    for (final file in picked.take(room)) {
      if (await _addOne(file)) added++;
    }
    if (picked.length > room) {
      _notice = 'Only $room of ${picked.length} picked image(s) fit: this ${kind.code} takes '
          '$maxItems at most.';
    }
    _notify();
    return added;
  }

  Future<bool> _addOne(PlatformFile file) async {
    final id = 'pick-${DateTime.now().microsecondsSinceEpoch}-${file.name}';
    final rules = MediaLimits.rulesFor(kind);
    final declaredLength = file.lengthSync();
    if (declaredLength != null && declaredLength > rules.maxBytes) {
      _items.add(
        MediaItem(
          id: id,
          fileName: file.name,
          status: MediaItemStatus.rejected,
          message: '${file.name} is ${(declaredLength / 1024 / 1024).toStringAsFixed(1)} MB; '
              'the limit is ${(rules.maxBytes / 1024 / 1024).toStringAsFixed(0)} MB.',
        ),
      );
      return false;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      _items.add(
        MediaItem(
          id: id,
          fileName: file.name,
          status: MediaItemStatus.rejected,
          message: 'That file could not be read (${error.runtimeType}).',
        ),
      );
      return false;
    }

    final item = MediaItem(
      id: id,
      fileName: file.name,
      bytes: bytes,
      altText: defaultAltText.trim(),
    );
    _items.add(item);

    final analysis = _analyse(item);
    if (!analysis.isAccepted) {
      item.status = MediaItemStatus.rejected;
      item.message = analysis.error ?? 'That file cannot be uploaded.';
      return false;
    }
    if (analysis.note != null) item.message = analysis.note!;

    // Alt text is a hard rule, so a row is only auto-uploaded when it already satisfies it. Starting
    // an upload that is certain to be refused wastes the admin's transfer and their patience.
    if (item.altText.trim().length >= MediaLimits.altTextMinLength) {
      await upload(item);
    } else {
      item.message = 'Add alt text, then upload.';
    }
    return true;
  }

  MediaAnalysis _analyse(MediaItem item, {int? alreadyAttached}) {
    final bytes = item.bytes;
    final repo = _repository;
    if (bytes != null && repo is SupabaseMediaRepository) {
      return repo.analyseUpload(
        bytes: bytes,
        kind: kind,
        altText: item.altText,
        alreadyAttached: alreadyAttached ?? _publishedCount,
        fileName: item.fileName,
      );
    }
    final validation = repo.validate(
      byteLength: bytes?.length ?? 0,
      mimeType: '',
      leadingBytes: bytes == null
          ? const <int>[]
          : bytes.sublist(0, bytes.lengthInBytes < MediaLimits.sniffWindowBytes
              ? bytes.lengthInBytes
              : MediaLimits.sniffWindowBytes),
    );
    return MediaAnalysis(
      format: MediaFormat.unsupported,
      rules: MediaLimits.rulesFor(kind),
      bytes: bytes ?? Uint8List(0),
      error: validation.error,
    );
  }

  int get _publishedCount => _items.where((item) => item.ref != null).length;

  // ------------------------------------------------------------- upload

  /// Uploads one staged row. Failures are recorded on the row rather than thrown, because one
  /// rejected file must not lose the nine good uploads beside it.
  Future<void> upload(MediaItem item) async {
    if (!isConfigured) {
      item.status = MediaItemStatus.rejected;
      item.message = statusMessage;
      _notify();
      return;
    }
    final bytes = item.bytes;
    if (bytes == null) {
      item.status = MediaItemStatus.rejected;
      item.message = 'The file is no longer in memory — pick it again.';
      _notify();
      return;
    }
    final existing = item.ref;
    if (existing != null && existing.storagePath.isNotEmpty) {
      await _replaceInPlace(item, existing, bytes);
      return;
    }
    final queue = pipeline;
    if (queue == null) {
      await _uploadThroughInterface(item, bytes);
      return;
    }

    item
      ..status = MediaItemStatus.uploading
      ..progress = 0
      ..message = 'Queued';
    _notify();
    try {
      final task = queue.enqueueUpload(
        bytes: bytes,
        fileName: item.fileName,
        mimeType: '',
        kind: kind,
        ownerId: ownerId,
        altText: item.altText,
        order: _items.indexOf(item),
        alreadyAttached: _publishedCount,
        entityKey: entityKey,
        attachment: attachmentFor,
        onProgress: (fraction) {
          item.progress = fraction;
          _notify();
        },
      );
      item.task = task;
      item.bindUpdates(task.updates, _notify);
      _applyPublished(item, await task.future);
    } on MediaFailure catch (failure) {
      _applyFailure(item, failure.message);
    } catch (error) {
      _applyFailure(item, 'Upload failed: ${error.runtimeType}.');
    }
  }

  /// A row that already has a reference overwrites its own object in place, so no document is ever
  /// re-pointed and no duplicate object lands in the bucket.
  Future<void> _replaceInPlace(MediaItem item, MediaRef existing, Uint8List bytes) async {
    item
      ..status = MediaItemStatus.uploading
      ..progress = 0
      ..message = 'Replacing';
    _notify();
    try {
      _applyPublished(
        item,
        await _repository.replace(
          existing: existing,
          bytes: bytes,
          fileName: item.fileName,
          mimeType: '',
          onProgress: (fraction) {
            item.progress = fraction;
            _notify();
          },
        ),
      );
    } on MediaFailure catch (failure) {
      item.ref = existing;
      _applyFailure(item, failure.message);
    } catch (error) {
      item.ref = existing;
      _applyFailure(item, 'Replace failed: ${error.runtimeType}.');
    }
  }

  Future<void> _uploadThroughInterface(MediaItem item, Uint8List bytes) async {
    item
      ..status = MediaItemStatus.uploading
      ..progress = 0;
    _notify();
    try {
      _applyPublished(
        item,
        await _repository.upload(
          bytes: bytes,
          fileName: item.fileName,
          mimeType: '',
          kind: kind,
          ownerId: ownerId,
          altText: item.altText,
          order: _items.indexOf(item),
          onProgress: (fraction) {
            item.progress = fraction;
            _notify();
          },
        ),
      );
    } on MediaFailure catch (failure) {
      _applyFailure(item, failure.message);
    } catch (error) {
      _applyFailure(item, 'Upload failed: ${error.runtimeType}.');
    }
  }

  void _applyPublished(MediaItem item, MediaRef ref) {
    item
      ..ref = ref
      ..status = MediaItemStatus.published
      ..progress = 1
      ..message = 'Published'
      ..bytes = null
      ..task = null;
    if (_primaryId.isEmpty) _primaryId = ref.id;
    item.close();
    _notify();
    unawaited(_hydrateOne(item));
  }

  /// Fetches the display URL for a row that just landed, so the editor shows the CDN variant the
  /// storefront will actually get. The result goes on [MediaItem.renderUrl] and never into
  /// [MediaItem.ref]: a signed link must not be one `copyWith` away from a Firestore document.
  Future<void> _hydrateOne(MediaItem item) async {
    final queue = pipeline;
    final ref = item.ref;
    if (queue == null || ref == null || _disposed) return;
    try {
      final resolved = await queue.resolveForRender(<MediaRef>[ref]);
      if (_disposed || item.ref?.id != ref.id) return;
      final url = resolved.isEmpty ? '' : resolved.first.url;
      if (url.isEmpty) return;
      item.renderUrl = url;
      _notify();
    } on MediaFailure catch (failure) {
      item.message = failure.message;
      _notify();
    }
  }

  void _applyFailure(MediaItem item, String message) {
    final cancelled = item.status == MediaItemStatus.cancelled ||
        message.startsWith('The upload was cancelled');
    item
      ..status = cancelled ? MediaItemStatus.cancelled : MediaItemStatus.failed
      ..message = message
      ..progress = 1;
    _notify();
  }

  Future<void> retry(MediaItem item) async {
    final task = item.task;
    final queue = pipeline;
    if (task != null && queue != null && task.canRetry && task.hasBytes) {
      // Same media id, same staging key, same final key: a retry overwrites its own object.
      item
        ..status = MediaItemStatus.uploading
        ..progress = 0
        ..message = 'Retrying the same object key';
      _notify();
      try {
        _applyPublished(item, await queue.retryUpload(task));
      } on MediaFailure catch (failure) {
        _applyFailure(item, failure.message);
      } catch (error) {
        _applyFailure(item, 'Retry failed: ${error.runtimeType}.');
      }
      return;
    }
    if (item.bytes == null) {
      item.message = 'That upload can no longer be retried — pick the image again.';
      _notify();
      return;
    }
    await upload(item);
  }

  void cancel(MediaItem item) {
    final task = item.task;
    if (task == null || !task.isInFlight) return;
    pipeline?.cancelUpload(task);
    item
      ..status = MediaItemStatus.cancelled
      ..message = 'Cancelled — the staged copy is being removed.';
    _notify();
  }

  /// Removes the row. A published row is also recorded in [removedRefs], so the owning form can
  /// delete the object after its save succeeds.
  void remove(MediaItem item) {
    cancel(item);
    item.close();
    _items.remove(item);
    final ref = item.ref;
    if (ref != null) _removed.add(ref);
    if (_primaryId == ref?.id) _primaryId = '';
    _notify();
  }

  /// Picks a replacement file for a row that already has a published object.
  ///
  /// The object key is kept, so the document keeps pointing at the same path and the bucket never
  /// accumulates a second copy of a photo someone simply re-shot.
  Future<void> replaceFromPicker(MediaItem item) async {
    if (!isConfigured) {
      _notice = statusMessage;
      _notify();
      return;
    }
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp', 'avif'],
        dialogTitle: 'Replace ${item.fileName}',
      );
    } catch (error) {
      _notice = 'The file picker could not run in this browser (${error.runtimeType}).';
      _notify();
      return;
    }
    if (picked.isEmpty) return;
    final file = picked.first;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      item.message = 'That file could not be read (${error.runtimeType}).';
      _notify();
      return;
    }
    item
      ..bytes = bytes
      ..status = MediaItemStatus.staged
      ..progress = 0
      ..message = 'Ready to replace';
    // The image being replaced still occupies a slot, so the cap check must not count it twice or a
    // full gallery could never be refreshed.
    final analysis = _analyse(item, alreadyAttached: _publishedCount - 1);
    if (!analysis.isAccepted) {
      item.status = MediaItemStatus.rejected;
      item.message = analysis.error ?? 'That file cannot replace this image.';
      _notify();
      return;
    }
    await upload(item);
  }

  // ------------------------------------------------------------- ordering

  void move(int from, int to) {
    if (from < 0 || to < 0 || from >= _items.length || to >= _items.length) return;
    _items.insert(to, _items.removeAt(from));
    _notify();
  }

  void setPrimary(MediaItem item) {
    final ref = item.ref;
    if (ref == null) return;
    _primaryId = ref.id;
    item.message = 'Primary';
    _notify();
  }

  bool isPrimary(MediaItem item) {
    final ref = item.ref;
    if (ref == null) return false;
    return _primaryId.isEmpty ? _items.first == item : ref.id == _primaryId;
  }

  void setAltText(MediaItem item, String value) {
    item.altText = value;
    final ref = item.ref;
    if (ref != null && ref.altText != value.trim()) {
      item.ref = ref.copyWith(altText: value.trim());
    }
    _notify();
  }

  MediaAttachment? get attachmentFor {
    if (attachmentCollection.isEmpty) return null;
    final id = entityKey ?? ownerId;
    if (id.isEmpty) return null;
    return MediaAttachment(collection: attachmentCollection, docId: id);
  }

  /// Pulls render-time URLs for rows the document already had, so a private bucket's editor shows
  /// the admin what the storefront sees instead of an empty frame.
  Future<void> _hydratePreviews() async {
    final queue = pipeline;
    if (queue == null || !isConfigured) return;
    final refs = _items.map((item) => item.ref).whereType<MediaRef>().toList(growable: false);
    if (refs.isEmpty) return;
    try {
      final resolved = await queue.resolveForRender(refs);
      if (_disposed) return;
      for (final ref in resolved) {
        if (ref.url.isEmpty) continue;
        for (final item in _items) {
          if (item.ref?.id == ref.id) item.renderUrl = ref.url;
        }
      }
      _notify();
    } on MediaFailure catch (failure) {
      _notice = failure.message;
    }
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final item in _items) {
      final task = item.task;
      if (task != null && task.isInFlight) pipeline?.cancelUpload(task);
      item.close();
    }
    super.dispose();
  }
}
