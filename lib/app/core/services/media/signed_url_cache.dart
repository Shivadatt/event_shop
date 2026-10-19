import 'dart:async';

import 'package:om_events/app/core/services/media/media_limits.dart';

// SignedUrlCache's constructor takes `signer`/`ttl` and assigns `_signer`/`_ttl` in its initialiser
// list. The initializing-formal form (`this._signer`) silences this lint on the pinned SDK but is a
// hard error on Dart 3.10, where a named parameter may not start with an underscore — and this
// package still has to build there. Scoped to this file rather than inline because a `// ignore:`
// only covers the next line when it sits alone, and the initialiser list leaves no such line.
// ignore_for_file: prefer_initializing_formals

/// A signed URL plus the instant it stops being usable.
final class SignedUrlEntry {
  const SignedUrlEntry({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;

  bool isFresh(Duration margin, DateTime now) => expiresAt.difference(now) > margin;

  int get secondsRemaining {
    final left = expiresAt.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }
}

/// TTL cache for private-bucket signed URLs.
///
/// Two invariants make this safe:
///  * a URL is refreshed *before* it expires (by [MediaLimits.signedUrlRefreshMargin]), because a
///    link that dies mid-`<img>` fetch renders as a broken image and looks like deleted media;
///  * concurrent requests for the same path share one in-flight signature, so a product page with
///    ten gallery thumbs costs one round trip instead of ten.
///
/// The cached value is *never* a storable value: only `storagePath` is persisted, and callers get
/// the URL at render time (docs/supabase-storage.md).
final class SignedUrlCache {
  SignedUrlCache({
    required Future<String> Function(String storagePath, Duration ttl) signer,
    Duration ttl = MediaLimits.signedUrlTtl,
    Duration refreshMargin = MediaLimits.signedUrlRefreshMargin,
    DateTime Function()? clock,
  })  : _signer = signer,
        _ttl = ttl,
        _margin = refreshMargin,
        _clock = clock ?? DateTime.now;

  final Future<String> Function(String storagePath, Duration ttl) _signer;
  final Duration _ttl;

  /// Never shorter than a sixth of the TTL: with a 15-minute link a fixed 3-minute margin already
  /// covers a page load, and clamping keeps a misconfigured margin from re-signing on every frame.
  final Duration _margin;
  final DateTime Function() _clock;

  final Map<String, SignedUrlEntry> _entries = <String, SignedUrlEntry>{};
  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};

  Duration get ttl => _ttl;

  int get size => _entries.length;

  /// A usable cached link, or null when it is missing or about to expire. Used by the batch signer
  /// so only the paths that truly need a signature are sent to the API.
  SignedUrlEntry? cached(String storagePath, {Duration? margin}) {
    final entry = _entries[storagePath];
    if (entry == null) return null;
    return entry.isFresh(margin ?? _margin, _clock()) ? entry : null;
  }

  /// Adopts a URL produced elsewhere (the batch endpoint) so it is refreshed on the same schedule.
  void store(String storagePath, String url, Duration ttl) {
    _entries[storagePath] = SignedUrlEntry(url: url, expiresAt: _clock().add(ttl));
  }

  Future<String> urlFor(String storagePath, {Duration? ttl}) async {
    if (storagePath.isEmpty) {
      throw StateError('SignedUrlCache requires a non-empty storagePath.');
    }
    final effectiveTtl = ttl ?? _ttl;
    final cached = _entries[storagePath];
    if (cached != null &&
        effectiveTtl >= _ttl &&
        cached.isFresh(_marginFor(effectiveTtl), _clock())) {
      return cached.url;
    }
    final pending = _inFlight[storagePath];
    if (pending != null) return pending;

    final request = _signAndStore(storagePath, effectiveTtl);
    _inFlight[storagePath] = request;
    try {
      return await request;
    } finally {
      // The map's value is the Future itself, so `remove` hands one back; this entry's result is
      // already awaited above, so the returned handle is deliberately dropped rather than awaited.
      unawaited(_inFlight.remove(storagePath));
    }
  }

  Future<String> _signAndStore(String storagePath, Duration ttl) async {
    final url = await _signer(storagePath, ttl);
    _entries[storagePath] = SignedUrlEntry(
      url: url,
      expiresAt: _clock().add(ttl),
    );
    return url;
  }

  /// Drop a cached link (after a replace/delete the old signature points at bytes that no longer
  /// exist on some CDN edges).
  void invalidate(String storagePath) {
    _entries.remove(storagePath);
    _inFlight.remove(storagePath);
  }

  void clear() {
    _entries.clear();
    _inFlight.clear();
  }

  Duration _marginFor(Duration ttl) {
    final proportional = Duration(seconds: (ttl.inSeconds / 6).floor());
    final bounded = _margin < proportional ? proportional : _margin;
    return bounded < ttl ? bounded : Duration(seconds: (ttl.inSeconds / 2).floor());
  }
}
