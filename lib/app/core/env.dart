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

  static bool get hasFirebase =>
      firebaseApiKey.isNotEmpty && firebaseProjectId.isNotEmpty && firebaseAppId.isNotEmpty;

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isFullyConfigured => hasFirebase && hasSupabase && !hasServiceRoleKeyInClient;

  static bool get hasServiceRoleKeyInClient => _forbiddenKey.isNotEmpty;

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
