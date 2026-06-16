import 'package:http/http.dart' as http;

/// Backend connection config for GatiVani.
///
/// The backend lives in Supabase Edge Functions.
///   Health    → GET  /functions/v1/health
///   Process   → POST /functions/v1/documents-process  (multipart)
///   Synthesize→ POST /functions/v1/documents-synthesize (JSON)
///
/// Override at build/run time with:
///   flutter run --dart-define=SUPABASE_FUNCTIONS_URL=https://<ref>.supabase.co/functions/v1
class ApiConfig {
  ApiConfig._();

  static const String functionsUrl = String.fromEnvironment(
    'SUPABASE_FUNCTIONS_URL',
    defaultValue: 'https://jjoxowdvzmlchtfarpbs.supabase.co/functions/v1',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impqb3hvd2R2em1sY2h0ZmFycGJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MTQ2MDEsImV4cCI6MjA5NTA5MDYwMX0.45oi82WrFqF8eQHbXjQ5hjcONXa8xkYROvgoGVMqsNI',
  );

  static String get documentsProcessUrl => '$functionsUrl/documents-process';
  static String get documentsProcessEditionUrl =>
      '$functionsUrl/documents-process-edition';

  /// Supabase project origin, e.g. https://<ref>.supabase.co
  static String get projectUrl =>
      functionsUrl.replaceFirst('/functions/v1', '');

  /// Supabase REST base (functionsUrl minus the /functions/v1 suffix).
  static String get restUrl => '$projectUrl/rest/v1';

  /// Supabase GoTrue (Auth) base.
  static String get authUrl => '$projectUrl/auth/v1';

  /// Browser URL to start a provider OAuth flow. Supabase handles the provider
  /// handshake and redirects back to [redirectTo] with the session in the URL
  /// fragment. Providers must be enabled in the Supabase dashboard first.
  static String oauthAuthorizeUrl(String provider, String redirectTo) =>
      '$authUrl/authorize?provider=$provider'
      '&redirect_to=${Uri.encodeComponent(redirectTo)}';

  static String get documentsSynthesizeUrl => '$functionsUrl/documents-synthesize';
  static String get documentsSummarizeUrl => '$functionsUrl/documents-summarize';
  static String get healthUrl => '$functionsUrl/health';

  static Map<String, String> get authHeaders => {
    'Authorization': 'Bearer $anonKey',
    'apikey': anonKey,
  };

  /// Dev-only header; backend ignores unless TRUST_CLIENT_TIER_HEADERS=true.
  /// Replace with JWT once auth is wired up.
  static const String subscriptionTier = 'standard';

  /// Returns true if the backend responds with ok=true within [timeout].
  static Future<bool> isBackendReachable({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final response = await http.get(Uri.parse(healthUrl)).timeout(timeout);
      return response.statusCode == 200 &&
          (response.body.contains('"ok":true') ||
              response.body.contains('"ok": true'));
    } catch (_) {
      return false;
    }
  }
}
