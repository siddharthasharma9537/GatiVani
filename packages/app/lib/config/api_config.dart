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
    defaultValue: 'sb_publishable_fNZOLe19iitMJpPnBngXmA_nsIIp30s',
  );

  static String get documentsProcessUrl => '$functionsUrl/documents-process';
  static String get documentsSynthesizeUrl => '$functionsUrl/documents-synthesize';
  static String get healthUrl => '$functionsUrl/health';

  static Map<String, String> get authHeaders => {
    'Authorization': 'Bearer $anonKey',
    'apikey': anonKey,
  };

  /// Dev-only header; backend ignores unless TRUST_CLIENT_TIER_HEADERS=true.
  /// Replace with JWT once auth is wired up.
  static const String subscriptionTier = 'premium';

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
