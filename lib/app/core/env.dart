/// Build-time configuration. Nothing here is a secret at rest: values arrive through
/// `--dart-define` and defaults are empty so an unconfigured build fails loudly instead of
/// silently shipping placeholder credentials.
class Env {
  const Env._();

  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
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
