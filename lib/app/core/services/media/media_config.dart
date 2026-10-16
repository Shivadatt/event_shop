import 'package:get/get.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/session_store.dart';

/// The two ways media can be unavailable are different problems, so they get different text:
/// nobody has supplied the build-time keys, versus the keys are present but `Supabase.initialize()`
/// refused them. Collapsing both into "not configured" sends an operator to the wrong fix.
enum MediaAvailability {
  ready,

  /// `SUPABASE_URL` and/or `SUPABASE_ANON_KEY` are empty in this build.
  missingKeys,

  /// The keys are present, but bootstrap could not bring the client up.
  initFailed,
}

/// Single place that decides whether the media pipeline may touch Supabase at all, and what to
/// say when it may not. Everything downstream reads this instead of re-deriving the condition.
abstract final class MediaConfig {
  /// Bucket that holds every store image. Overridable per deployment with `SUPABASE_MEDIA_BUCKET`.
  static String get bucket => Env.supabaseMediaBucket;

  static MediaAvailability get availability {
    if (!Env.hasSupabase) return MediaAvailability.missingKeys;
    if (!AppBootstrap.report.supabaseReady) return MediaAvailability.initFailed;
    return MediaAvailability.ready;
  }

  static bool get isConfigured => availability == MediaAvailability.ready;

  /// Names the missing `--dart-define` keys so a failure message is actionable on its own.
  static List<String> get missingKeyNames {
    final names = <String>[];
    if (Env.supabaseUrl.isEmpty) names.add('SUPABASE_URL');
    if (Env.supabaseAnonKey.isEmpty) names.add('SUPABASE_ANON_KEY');
    return names;
  }

  /// Presentable reason the pipeline is offline. The UI shows this instead of a spinner that
  /// never ends, so it must never be empty.
  static String get statusMessage {
    switch (availability) {
      case MediaAvailability.ready:
        return 'Media storage ready (bucket: $bucket).';
      case MediaAvailability.missingKeys:
        final names = missingKeyNames;
        if (names.isEmpty) return 'Media storage is not configured.';
        return 'Media storage is not configured: ${names.join(' and ')} '
            'must be supplied with --dart-define.';
      case MediaAvailability.initFailed:
        final detail = AppBootstrap.report.failure;
        return 'Media storage is offline because Supabase failed to initialise'
            '${detail == null ? '' : ' ($detail)'}.';
    }
  }

  /// Throws instead of returning: callers must not be able to continue past an unconfigured
  /// bucket with a null "result".
  static Never unavailable({String? action}) =>
      throw MediaFailure(unavailableMessage(action));

  static String unavailableMessage(String? action) =>
      'Cannot ${action ?? 'access media'} — ${statusMessage}';

  /// Whether this device may offer destructive media actions (delete/orphan purge).
  ///
  /// This is UX only, exactly like the route guards: the enforcement is the storage RLS policy,
  /// so a wrong client-side `true` still cannot delete anything.
  static bool get canManageMedia {
    if (!isConfigured) return false;
    if (!Get.isRegistered<SessionStore>()) return false;
    return Get.find<SessionStore>().isAdmin;
  }
}
