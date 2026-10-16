import 'dart:typed_data';

import 'package:om_events/app/core/errors/failures.dart';

/// Blocks image bytes from ever reaching a Firestore document.
///
/// The rule this enforces is architectural: Firestore stores a `MediaRef` (url, storagePath, alt,
/// order) and Supabase Storage holds the bytes. It matters because a single base64 product photo
/// (~3-4 MB as text) exceeds the 1 MiB document limit, blows up catalogue reads, and destroys the
/// page-weight budget of every listing that touches the document. Repositories that forget this
/// find out only when an admin uploads a hero shot, so the write path checks rather than trusting.
///
/// Run it on every document payload before `set`/`update`. The media pipeline calls it on
/// `media_objects` writes and on `products.images` writes; catalogue/order writers should call it
/// too (see docs/supabase-storage.md).
abstract final class FirestoreMediaGuard {
  /// A long run of pure base64 with no URL characters and no whitespace is an inline payload.
  /// Anything shorter than this cannot be an image, and real text (slugs, descriptions) always
  /// breaks the pattern within a few hundred characters.
  static const int _base64SuspicionLength = 512;

  static final RegExp _base64Blob = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

  /// Throws [MediaFailure] naming the offending field path when [payload] carries binary data or
  /// an inline image. [where] labels the write for the message ("media_objects/abc123").
  static void ensureNoImageBytes(Object? payload, {required String where}) =>
      _walk(payload, where, '<document>');

  static void _walk(Object? payload, String where, String path) {
    if (payload is Map) {
      for (final entry in payload.entries) {
        _walk(entry.value, where, '$path.${entry.key}');
      }
      return;
    }
    if (payload is Iterable) {
      var index = 0;
      for (final value in payload) {
        _walk(value, where, '$path[$index]');
        index++;
      }
      return;
    }
    if (payload == null || payload is num || payload is bool) return;

    if (payload is TypedData || payload is ByteBuffer) {
      throw MediaFailure(
        'Firestore write blocked: $path in $where carries raw image bytes '
        '(${payload.runtimeType}). '
        'Store a MediaRef (url + storagePath) and keep the bytes in Supabase Storage.',
      );
    }
    if (payload is String) {
      if (payload.startsWith('data:')) {
        throw MediaFailure(
          'Firestore write blocked: $path in $where contains a data: URL. '
          'Upload the image and store its public URL instead.',
        );
      }
      if (payload.length >= _base64SuspicionLength &&
          !payload.startsWith('http') &&
          !_hasSpace(payload) &&
          _base64Blob.hasMatch(payload)) {
        throw MediaFailure(
          'Firestore write blocked: $path in $where looks like ${payload.length} characters of '
          'inline base64. Images live in Supabase Storage; only the URL belongs in the document.',
        );
      }
    }
  }

  static bool _hasSpace(String value) => value.contains(' ') || value.contains('\n');

  /// True when [value] would be rejected. Used by forms to warn before a save is attempted.
  static bool looksLikeImageBytes(Object? value) {
    try {
      ensureNoImageBytes(value, where: '<probe>');
      return false;
    } on MediaFailure {
      return true;
    }
  }
}
