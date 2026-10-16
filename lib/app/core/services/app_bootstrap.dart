import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:om_events/app/core/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What actually came up. The app must be able to state this honestly on screen instead of
/// rendering a store that is secretly talking to nothing.
final class BootstrapReport {
  const BootstrapReport({
    required this.firebaseReady,
    required this.supabaseReady,
    this.failure,
    this.missing = const <String>[],
  });

  final bool firebaseReady;
  final bool supabaseReady;
  final String? failure;
  final List<String> missing;

  bool get isComplete => firebaseReady && supabaseReady && failure == null;
  bool get isPartial => firebaseReady || supabaseReady;

  static BootstrapReport notConfigured(List<String> missing) =>
      BootstrapReport(firebaseReady: false, supabaseReady: false, missing: missing);
}

/// Initialises the two backends from `--dart-define` values. Nothing is hardcoded and nothing is
/// invented: an absent key produces a report that says so, and the UI shows a configuration
/// screen rather than a store full of placeholder merchandise.
abstract final class AppBootstrap {
  static BootstrapReport? _last;

  static BootstrapReport get report =>
      _last ?? const BootstrapReport(firebaseReady: false, supabaseReady: false);

  static Future<BootstrapReport> run() async {
    final missing = Env.missingKeys();
    if (missing.isNotEmpty && !Env.hasFirebase && !Env.hasSupabase) {
      _last = BootstrapReport.notConfigured(missing);
      return _last!;
    }

    var firebaseReady = false;
    var supabaseReady = false;
    String? failure;

    if (Env.hasFirebase) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: Env.firebaseApiKey,
              appId: Env.firebaseAppId,
              messagingSenderId: Env.firebaseMessagingSenderId,
              projectId: Env.firebaseProjectId,
              authDomain: Env.firebaseAuthDomain.isEmpty
                  ? '${Env.firebaseProjectId}.firebaseapp.com'
                  : Env.firebaseAuthDomain,
              storageBucket: Env.firebaseStorageBucket.isEmpty
                  ? '${Env.firebaseProjectId}.appspot.com'
                  : Env.firebaseStorageBucket,
              measurementId:
                  Env.firebaseMeasurementId.isEmpty ? null : Env.firebaseMeasurementId,
            ),
          );
        }
        // Offline-first so a dropped connection degrades to cached reads instead of an empty
        // catalogue. The cache is per-browser and never a substitute for a refetch.
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
        FirebaseFunctions.instanceFor(region: Env.functionsRegion);
        firebaseReady = true;
      } catch (error, stack) {
        failure = 'Firebase initialisation failed: ${_describe(error)}';
        debugPrintStack(stackTrace: stack);
      }
    }

    if (failure == null && Env.hasSupabase) {
      try {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          // Supabase renamed the client key: `publishableKey` is the current parameter and the
          // old `anonKey` is deprecated. The build-time env key stays `SUPABASE_ANON_KEY` so the
          // value already configured elsewhere keeps working — it is the same public credential.
          publishableKey: Env.supabaseAnonKey,
          debug: kDebugMode,
        );
        supabaseReady = true;
      } catch (error) {
        final detail = 'Supabase initialisation failed: ${_describe(error)}';
        failure = failure == null ? detail : '$failure $detail';
      }
    }

    _last = BootstrapReport(
      firebaseReady: firebaseReady,
      supabaseReady: supabaseReady,
      failure: failure,
      missing: missing,
    );
    return _last!;
  }

  /// Firebase auth errors carry provider text that is not for end users; log the detail, keep the
  /// code.
  static String _describe(Object error) {
    if (error is FirebaseException) return '${error.plugin}/${error.code}';
    if (error is FirebaseAuthException) return error.code;
    return error.runtimeType.toString();
  }

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get db => FirebaseFirestore.instance;
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: Env.functionsRegion);
  static SupabaseClient get supabase => Supabase.instance.client;
}
