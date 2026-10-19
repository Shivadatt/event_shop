import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/services/media/signed_url_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How the bucket serves bytes. Read from the bucket's own `public` flag rather than assumed,
/// because the two answers need different stored values: a public bucket yields a permanent URL
/// that may be written into Firestore; a private one yields only an expiring signed URL that must
/// not be.
enum MediaBucketVisibility {
  public,
  private,

  /// Not resolvable (`getBucket` denied): treated as public, because storing a signed URL is the
  /// more expensive mistake. The assumption is logged and reported to the admin UI.
  assumedPublic,
}

/// Result of a bucket sweep.
final class MediaObjectListing {
  const MediaObjectListing({required this.paths, required this.isPartial});

  final List<String> paths;

  /// True when the sweep stopped at the object cap. A partial sweep must never be offered for
  /// deletion, because an object that was simply not reached looks orphaned.
  final bool isPartial;

  int get count => paths.length;
}

/// Thin, honest wrapper over one Supabase Storage bucket.
///
/// Everything Supabase-specific stops here: the client is never handed to a widget, a controller or
/// a model, and every failure leaves as a [MediaFailure] whose text a store owner can act on.
final class SupabaseStorageService {
  SupabaseStorageService({
    String? bucketId,
    SupabaseClient? client,
    SignedUrlCache? signedUrlCache,
  })  : _bucketId = bucketId ?? MediaConfig.bucket,
        _clientOverride = client,
        _signedUrls = signedUrlCache;

  final String _bucketId;
  final SupabaseClient? _clientOverride;
  SignedUrlCache? _signedUrls;
  SignedUrlCache? _thumbSignedUrls;

  MediaBucketVisibility? _visibility;
  String? _writerUid;
  Future<String>? _writerUidInFlight;

  /// False while the pipeline cannot reach the bucket. The UI reads this to disable the upload
  /// control with an explanation instead of starting a spinner that can never finish.
  bool get isConfigured =>
      _clientOverride != null || MediaConfig.availability == MediaAvailability.ready;

  String get bucketId => _bucketId;

  /// Test seam: replaces the TTL cache.
  set signedUrlCache(SignedUrlCache value) => _signedUrls = value;

  SignedUrlCache get urlCache => _signedUrls ??= SignedUrlCache(
        signer: (path, ttl) => createSignedUrl(path, ttl: ttl),
      );

  /// Separate cache for grid thumbnails.
  ///
  /// A signed URL embeds the transform in its signature, so one path has two legitimately different
  /// signed URLs (full and 480px) and they must not share a cache slot; keying both by path in one
  /// map would make a grid render full-resolution bytes under a cached thumbnail's name.
  SignedUrlCache get thumbnailCache => _thumbSignedUrls ??= SignedUrlCache(
        signer: (path, ttl) =>
            createSignedUrl(path, ttl: ttl, width: MediaLimits.thumbnailWidth),
      );

  String get statusMessage => isConfigured
      ? 'Supabase bucket "$_bucketId" is reachable.'
      : MediaConfig.statusMessage;

  SupabaseClient get client {
    final override = _clientOverride;
    if (override != null) return override;
    if (!Env.hasSupabase) {
      throw MediaFailure(
        'Cannot access the media bucket — ${MediaConfig.missingKeyNames.join(' and ')} '
        'must be supplied with --dart-define. Bucket: $_bucketId.',
      );
    }
    if (!AppBootstrap.report.supabaseReady) {
      final detail = AppBootstrap.report.failure;
      throw MediaFailure(
        'Cannot access the media bucket — Supabase did not initialise'
        '${detail == null ? '' : ' ($detail)'} while building this bundle. '
        'Check SUPABASE_URL and SUPABASE_ANON_KEY. Bucket: $_bucketId.',
      );
    }
    try {
      return AppBootstrap.supabase;
    } catch (error) {
      throw MediaFailure(
        'Cannot access the media bucket — the Supabase client is not available '
        '(${error.runtimeType}). Supply SUPABASE_URL and SUPABASE_ANON_KEY and restart the app.',
      );
    }
  }

  StorageFileApi get objects => client.storage.from(_bucketId);

  /// The uid that owns `tmp/…` and `reviews/…` object keys.
  ///
  /// Deliberately the **Supabase** uid, not the Firebase uid: storage RLS can only verify the
  /// subject of the JWT Supabase signed, so a path prefix is enforceable only when it names that
  /// subject. The Firebase author uid stays as bookkeeping in `media_objects`.
  ///
  /// When the deployment has not authenticated Supabase at all, an anonymous Supabase session is
  /// created so every upload still has an owner the policy can check.
  Future<String> writerUid() {
    final cached = _writerUid;
    if (cached != null && cached.isNotEmpty) return Future<String>.value(cached);
    final pending = _writerUidInFlight;
    if (pending != null) return pending;
    final request = _resolveWriterUid();
    _writerUidInFlight = request;
    return request.whenComplete(() => _writerUidInFlight = null);
  }

  Future<String> _resolveWriterUid() async {
    final auth = client.auth;
    final current = auth.currentUser;
    if (current != null) {
      _writerUid = current.id;
      return current.id;
    }
    try {
      final response = await auth.signInAnonymously();
      final uid = response.session?.user.id;
      if (uid == null || uid.isEmpty) {
        throw const MediaFailure(
          'Anonymous Supabase sign-in returned no user, so an upload cannot be attributed to a '
          'storage path. Enable "Allow Anonymous Sign-Ins" in Supabase Auth, or authenticate '
          'Supabase directly for staff.',
        );
      }
      _writerUid = uid;
      return uid;
    } on AuthException catch (error) {
      throw MediaFailure(
        'Supabase refused the sign-in that media uploads need '
        '(${error.code ?? error.statusCode ?? 'auth'}): ${_safeReason(error.message)}. '
        'Enable "Allow Anonymous Sign-Ins" in the Supabase Auth settings if this build uploads '
        'without a Supabase session.',
      );
    } catch (error) {
      throw failure('sign in for media uploads', error);
    }
  }

  /// Reads the bucket's `public` flag once and remembers it. A denied lookup falls back to
  /// [MediaBucketVisibility.assumedPublic] and logs, instead of silently storing expiring URLs.
  Future<MediaBucketVisibility> resolveVisibility() async {
    final known = _visibility;
    if (known != null) return known;
    try {
      final bucket = await client.storage.getBucket(_bucketId);
      _visibility =
          bucket.public ? MediaBucketVisibility.public : MediaBucketVisibility.private;
      return _visibility!;
    } catch (error) {
      debugPrint(
        'Media bucket visibility lookup failed (${error.runtimeType}); assuming public URLs. '
        'If this bucket is private, grant staff SELECT on storage.objects for bucket '
        '"$_bucketId".',
      );
      _visibility = MediaBucketVisibility.assumedPublic;
      return _visibility!;
    }
  }

  /// Only for tests and for an operator who knows their bucket setting without asking the API.
  void overrideVisibility(MediaBucketVisibility value) => _visibility = value;

  /// Whether a URL produced for this bucket may be persisted. Private buckets return false, which
  /// makes the repository store an empty `url` plus a path instead of a link that will die.
  bool get servesPublicUrls {
    final value = _visibility;
    return value == null ||
        value == MediaBucketVisibility.public ||
        value == MediaBucketVisibility.assumedPublic;
  }

  MediaBucketVisibility get knownVisibility => _visibility ?? MediaBucketVisibility.assumedPublic;

  /// Writes bytes at [path].
  ///
  /// `upsert` is always on: the retry story depends on it. A retry reuses the exact key the first
  /// attempt was given, so the second attempt overwrites its own partial object instead of leaving
  /// a second copy of the same photo in the bucket.
  Future<void> putBytes({
    required String path,
    required Uint8List bytes,
    required String contentType,
    required String cacheControl,
    StorageRetryController? cancel,
    int retryAttempts = 2,
  }) async {
    try {
      await objects.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          cacheControl: cacheControl,
          upsert: true,
          contentType: contentType,
        ),
        retryAttempts: retryAttempts,
        retryController: cancel,
      );
    } on StorageException catch (error) {
      // A response lost after the object landed is a success, not a reason to write twice.
      if (_isDuplicate(error) && await exists(path)) return;
      throw failure('upload ${_short(path)}', error);
    } catch (error) {
      throw failure('upload ${_short(path)}', error);
    }
  }

  Future<bool> exists(String path) async {
    try {
      return await objects.exists(path);
    } on StorageException catch (error) {
      if (error.statusCode == '404') return false;
      throw failure('check ${_short(path)}', error);
    } catch (error) {
      throw failure('check ${_short(path)}', error);
    }
  }

  /// Server-side promotion from `tmp/…` to the entity prefix. The bytes never come back through the
  /// browser, which is the whole reason the pipeline stages first.
  Future<void> moveTo({required String fromPath, required String toPath}) async {
    try {
      await objects.move(fromPath, toPath);
    } on StorageException catch (error) {
      // Either this process already moved it (retry after a lost response) or the source is gone
      // because a previous attempt committed it. Either way the destination is what matters.
      if ((_isDuplicate(error) || _isNotFound(error)) && await exists(toPath)) return;
      throw failure('promote ${_short(fromPath)}', error);
    } catch (error) {
      throw failure('promote ${_short(fromPath)}', error);
    }
  }

  /// Deletes objects. On success the requested paths are reported back: the storage API deletes
  /// idempotently, and its response entries carry a bare file name rather than a full key.
  Future<List<String>> remove(List<String> paths) async {
    if (paths.isEmpty) return const <String>[];
    final removed = <String>[];
    for (var start = 0; start < paths.length; start += MediaLimits.deleteBatchSize) {
      final end = start + MediaLimits.deleteBatchSize > paths.length
          ? paths.length
          : start + MediaLimits.deleteBatchSize;
      final batch = paths.sublist(start, end);
      try {
        await objects.remove(batch);
        removed.addAll(batch);
      } on StorageException catch (error) {
        if (_isNotFound(error)) {
          removed.addAll(batch); // Already gone is a fulfilled delete request.
          continue;
        }
        throw failure('delete ${batch.length} object(s)', error);
      } catch (error) {
        throw failure('delete ${batch.length} object(s)', error);
      }
    }
    return removed;
  }

  /// Permanent URL for a public bucket. This is the only media value that may be stored in
  /// Firestore; note the deliberate absence of any token or signature.
  String publicUrl(String path, {int? width, int? quality}) {
    final transform = width == null
        ? null
        : TransformOptions(
            width: width,
            resize: ResizeMode.cover,
            quality: quality ?? MediaLimits.renderQuality,
          );
    return objects.getPublicUrl(path, transform: transform);
  }

  /// Thumbnail through Supabase's render endpoint, at the same 480px width the storefront grid asks
  /// for (see `MediaRef.thumbnailUrl` and `OmMediaImage`'s decode width).
  String thumbnailUrl(String path) => publicUrl(path, width: MediaLimits.thumbnailWidth);

  /// Detail-hero variant: the largest size worth shipping, not the original bytes.
  String heroUrl(String path) => publicUrl(path, width: MediaLimits.heroWidth, quality: 85);

  Future<String> createSignedUrl(
    String path, {
    Duration ttl = MediaLimits.signedUrlTtl,
    int? width,
    int? quality,
  }) async {
    final seconds = ttl.inSeconds < 1 ? 1 : ttl.inSeconds;
    final transform = width == null
        ? null
        : TransformOptions(
            width: width,
            resize: ResizeMode.cover,
            quality: quality ?? MediaLimits.renderQuality,
          );
    try {
      return await objects.createSignedUrl(path, seconds, transform: transform);
    } on StorageException catch (error) {
      throw failure('sign ${_short(path)}', error);
    } catch (error) {
      throw failure('sign ${_short(path)}', error);
    }
  }

  /// Cached, refreshed-before-expiry signed URL. Callers must never persist the result.
  Future<String> signedUrl(String path, {Duration ttl = MediaLimits.signedUrlTtl}) =>
      urlCache.urlFor(path, ttl: ttl);

  /// Same, but signed for the 480px CDN transform so a private gallery grid does not download
  /// every original.
  Future<String> signedThumbnailUrl(
    String path, {
    Duration ttl = MediaLimits.signedUrlTtl,
  }) =>
      thumbnailCache.urlFor(path, ttl: ttl);

  /// Drops both cached signatures for a path. Called after a replace or a delete: a live signature
  /// can still resolve to bytes a CDN edge has cached, and a stale full-size entry would otherwise
  /// survive the object it points at.
  void invalidateSigned(String path) {
    _signedUrls?.invalidate(path);
    _thumbSignedUrls?.invalidate(path);
  }

  /// Batch signing for a gallery: one request for ten thumbs instead of ten.
  Future<Map<String, String>> signedUrls(
    List<String> paths, {
    Duration ttl = MediaLimits.signedUrlTtl,
  }) async {
    if (paths.isEmpty) return const <String, String>{};
    final cache = urlCache;
    final fresh = <String, String>{};
    final needsSigning = <String>[];
    for (final path in paths) {
      final entry = cache.cached(path);
      if (entry != null) {
        fresh[path] = entry.url;
      } else {
        needsSigning.add(path);
      }
    }
    if (needsSigning.isEmpty) return fresh;
    final seconds = ttl.inSeconds < 1 ? 1 : ttl.inSeconds;
    try {
      final results = await objects.createSignedUrlsResult(needsSigning, seconds);
      for (final result in results) {
        if (result is SignedUrlSuccess) {
          fresh[result.path] = result.signedUrl;
          cache.store(result.path, result.signedUrl, ttl);
        } else if (result is SignedUrlFailure) {
          debugPrint('Signed URL denied for ${result.path}: ${_safeReason(result.error)}');
        }
      }
      for (final path in needsSigning) {
        if (fresh.containsKey(path)) continue;
        fresh[path] = await cache.urlFor(path, ttl: ttl);
      }
      return fresh;
    } on StorageException catch (error) {
      throw failure('sign ${paths.length} objects', error);
    } catch (error) {
      throw failure('sign ${paths.length} objects', error);
    }
  }

  /// Flat object listing for the orphan sweep, capped at [MediaLimits.orphanScanMaxObjects].
  Future<MediaObjectListing> listObjects({
    String? prefix,
    int maxObjects = MediaLimits.orphanScanMaxObjects,
  }) async {
    final paths = <String>[];
    String? cursor;
    var pages = 0;
    try {
      while (pages < 64) {
        final page = await objects.listPaginated(
          options: PaginatedSearchOptions(
            prefix: prefix,
            limit: MediaLimits.orphanScanPageSize,
            cursor: cursor,
          ),
        );
        for (final file in page.objects) {
          final key = file.key ?? (prefix == null || prefix.isEmpty ? file.name : '$prefix/${file.name}');
          if (key.isNotEmpty) paths.add(key);
          if (paths.length >= maxObjects) {
            return MediaObjectListing(paths: paths, isPartial: true);
          }
        }
        cursor = page.nextCursor;
        pages++;
        if (!page.hasNext || cursor == null || cursor.isEmpty) break;
      }
    } on StorageException catch (error) {
      throw failure('list the media bucket', error);
    } catch (error) {
      throw failure('list the media bucket', error);
    }
    return MediaObjectListing(paths: paths, isPartial: pages >= 64);
  }

  /// Turns any SDK or network failure into the project's failure type, with actionable text and no
  /// server trace that could name a policy, a token or a query string.
  MediaFailure failure(String action, Object error) {
    if (error is MediaFailure) return error;
    if (error is StorageException) {
      final status = error.statusCode;
      final reason = _safeReason(error.message);
      if (_isPermission(error)) {
        return MediaFailure(
          'Storage policy refused to $action. The rules for this path prefix do not allow the '
          'current Supabase role ($reason). See docs/supabase-storage.md — RLS policies for '
          'bucket "$_bucketId".',
        );
      }
      if (_isNotFound(error)) {
        return MediaFailure('That media object no longer exists in bucket "$_bucketId".');
      }
      if (status == '413' || _isTooLarge(error)) {
        return MediaFailure(
          'The bucket rejected the file size while trying to $action. Its own limit is lower than '
          'this build assumes — see docs/supabase-storage.md.',
        );
      }
      if (status == '408' || status == '502' || status == '503' || status == '504') {
        return MediaFailure('Media storage timed out while trying to $action. Retry the upload.');
      }
      return MediaFailure('Media storage could not $action${reason.isEmpty ? '' : ': $reason'}');
    }
    if (error is AuthException) {
      return MediaFailure('Sign-in is required before media can be $action (${error.code ?? 'auth'}).');
    }
    return MediaFailure(
      'Media storage could not $action — ${error.runtimeType}. Check the connection and retry.',
    );
  }

  static bool _isPermission(StorageException error) {
    final message = error.message.toLowerCase();
    return error.statusCode == '403' ||
        error.statusCode == '401' ||
        message.contains('row-level security') ||
        message.contains('jwt expired') ||
        message.contains('invalid claim') ||
        message.contains('not authorized');
  }

  static bool _isNotFound(StorageException error) {
    final message = error.message.toLowerCase();
    return error.statusCode == '404' ||
        message.contains('not found') ||
        message.contains('no such key');
  }

  static bool _isDuplicate(StorageException error) {
    final message = error.message.toLowerCase();
    return message.contains('already exists') || message.contains('duplicate key');
  }

  static bool _isTooLarge(StorageException error) =>
      error.message.toLowerCase().contains('exceeds file size limit');

  static String _safeReason(String raw) {
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final query = text.indexOf('?');
    if (query > 0) text = text.substring(0, query);
    if (text.length > 160) text = '${text.substring(0, 160)}…';
    return text;
  }

  static String _short(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
