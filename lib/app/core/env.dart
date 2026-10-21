import 'dart:convert';

/// Build-time configuration. Nothing here is a secret at rest: values arrive through
/// `--dart-define` and defaults are empty so an unconfigured build fails loudly instead of
/// silently shipping placeholder credentials.
class Env {
  const Env._();

  static const String _firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');

  /// Local-only emulator mode: `--dart-define=OM_USE_EMULATORS=true` points the SDK at the Firebase
  /// Local Emulator Suite on 127.0.0.1 so the store can be run and demoed with no cloud project and
  /// no real credentials. Off by default, and the placeholders below are deliberately worded so they
  /// cannot be mistaken for a key — they are only ever sent to localhost.
  static const bool useEmulators = bool.fromEnvironment('OM_USE_EMULATORS');
  static const String localEmulatorProjectId = 'demo-om-events';

  static String get firebaseApiKey => useEmulators && _firebaseApiKey.isEmpty
      ? 'localhost-emulator-not-a-real-key'
      : _firebaseApiKey;

  static String get firebaseProjectId => useEmulators && _firebaseProjectId.isEmpty
      ? localEmulatorProjectId
      : _firebaseProjectId;

  static String get firebaseAppId => useEmulators && _firebaseAppId.isEmpty
      ? 'OM-LOCAL-EMULATOR-APP'
      : _firebaseAppId;

  /// Emulator endpoints. These match the `emulators` block in firebase.json, so `firebase
  /// emulators:start` needs no extra flags. Overridable for a machine where a port is taken.
  static const String emulatorHost =
      String.fromEnvironment('OM_EMULATOR_HOST', defaultValue: 'localhost');
  static const int authEmulatorPort =
      int.fromEnvironment('OM_AUTH_EMULATOR_PORT', defaultValue: 9099);
  static const int firestoreEmulatorPort =
      int.fromEnvironment('OM_FIRESTORE_EMULATOR_PORT', defaultValue: 8080);
  static const int functionsEmulatorPort =
      int.fromEnvironment('OM_FUNCTIONS_EMULATOR_PORT', defaultValue: 5001);
  static const String firebaseAuthDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const String firebaseStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String firebaseMeasurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String supabaseMediaBucket =
      String.fromEnvironment('SUPABASE_MEDIA_BUCKET', defaultValue: 'om-events-media');

  static const String functionsRegion =
      String.fromEnvironment('FUNCTIONS_REGION', defaultValue: 'us-central1');
  static const String siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://omevents.example');
  static const String currencyCode = String.fromEnvironment('CURRENCY', defaultValue: 'INR');

  /// Client builds must never carry these; they exist only so the guard below can assert that
  /// nobody wired a privileged key into the bundle.
  static const String _forbiddenKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

  /// The raw define, read only by `AppBootstrap`'s fail-fast guard and by its test. A build that
  /// *did* pass it has already compiled the literal into `main.dart.js`, so refusing to expose a
  /// getter would protect nothing — only refusing to boot does.
  static String get supabaseServiceRoleKey => _forbiddenKey;

  static bool get hasFirebase =>
      firebaseApiKey.isNotEmpty && firebaseProjectId.isNotEmpty && firebaseAppId.isNotEmpty;

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isFullyConfigured => hasFirebase && hasSupabase && !hasServiceRoleKeyInClient;

  /// True when this bundle carries a privileged Supabase credential — either deliberately through
  /// `SUPABASE_SERVICE_ROLE_KEY`, or by accident in the `SUPABASE_ANON_KEY` slot, which is how it
  /// actually happens: the dashboard shows both keys in one panel and a paste is invisible in a
  /// `--dart-define` line. Enforced at bootstrap by `AppBootstrap.assertNoPrivilegedKeyInBundle`.
  static bool get hasServiceRoleKeyInClient =>
      _forbiddenKey.isNotEmpty || isPrivilegedClientKey(supabaseAnonKey);

  /// Whether [key] names the service-role (secret) credential rather than the public one.
  /// Recognises the current `sb_secret…` prefix and the legacy JWT form, whose payload is the only
  /// place `role` appears — the token itself is base64url, so the word never shows up in clear.
  static bool isPrivilegedClientKey(String key) {
    final value = key.trim();
    if (value.isEmpty) return false;
    if (value.startsWith('sb_secret')) return true;
    final payload = _jwtPayload(value);
    return payload != null && payload['role'] == 'service_role';
  }

  static Map<String, Object?>? _jwtPayload(String jwt) {
    final segments = jwt.split('.');
    if (segments.length != 3) return null;
    var payload = segments[1];
    final padding = payload.length % 4;
    if (padding != 0) payload += '=' * (4 - padding);
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      // Not a decodable JWT, so there is no claim to assert against. Anything genuinely privileged
      // still trips the checks above.
      return null;
    }
  }

  static List<String> missingKeys() {
    final missing = <String>[];
    if (firebaseApiKey.isEmpty) missing.add('FIREBASE_API_KEY');
    if (firebaseProjectId.isEmpty) missing.add('FIREBASE_PROJECT_ID');
    if (firebaseAppId.isEmpty) missing.add('FIREBASE_APP_ID');
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    return missing;
  }
}
