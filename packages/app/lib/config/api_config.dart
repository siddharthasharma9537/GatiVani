import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Migrated to the shared SoHum identity project (sohum) -- see
  // github.com/SoHum-Digital-Services/sohum-contracts.
  static const String functionsUrl = String.fromEnvironment(
    'SUPABASE_FUNCTIONS_URL',
    defaultValue: 'https://ziebgspujtdzkiwyybsa.supabase.co/functions/v1',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InppZWJnc3B1anRkemtpd3l5YnNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA0ODE5NjMsImV4cCI6MjEwNjA1Nzk2M30.wEqY7dttS1hitsZCZSC0GXFyqeiFUb8jdVlYG-toRmU',
  );

  static String get documentsProcessUrl => '$functionsUrl/documents-process';
  /// Deprecated: kept only so older builds keep working. New code starts an
  /// edition through [pipelineStartUrl].
  static String get documentsProcessEditionUrl =>
      '$functionsUrl/documents-process-edition';

  /// Edition ingest: start a job, then poll it. The pipeline runs pages in
  /// parallel and recovers ones whose worker died — see
  /// docs/ORCHESTRATION_PLAN.md Phase 3.
  static String get pipelineStartUrl => '$functionsUrl/pipeline-start';
  static String get pipelineStatusUrl => '$functionsUrl/pipeline-status';

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

  /// Same shape as [authHeaders], but carries the signed-in user's own
  /// session JWT in Authorization when there is one (falling back to the
  /// anon key when signed out). [authHeaders] always sends the anon key
  /// regardless of sign-in state, so any table whose RLS checks auth.uid()
  /// (e.g. recent_plays, scoped per user) sees every caller as anonymous
  /// through it — reads return nothing, writes can't attach real ownership.
  /// Use this instead for anything RLS scopes to "the calling user".
  static Map<String, String> get userAuthHeaders {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Authorization': 'Bearer ${token ?? anonKey}',
      'apikey': anonKey,
    };
  }

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
