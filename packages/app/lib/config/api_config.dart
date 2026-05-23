import 'package:http/http.dart' as http;

/// Backend connection config for GatiVani.
///
/// Override at build/run time with --dart-define:
///   flutter run --dart-define=BACKEND_API_BASE=http://192.168.1.x:8788/api
///   flutter run --dart-define=PUBLIC_ORIGIN=http://192.168.1.x:8788
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'BACKEND_API_BASE',
    defaultValue: 'http://localhost:8788/api',
  );

  static const String publicOrigin = String.fromEnvironment(
    'PUBLIC_ORIGIN',
    defaultValue: 'http://localhost:8788',
  );

  // ── Endpoints ────────────────────────────────────────────────────────────

  static String get documentsProcessUrl => '$baseUrl/documents/process';
  static String get healthUrl => '$publicOrigin/health';

  // ── Subscription tier header ──────────────────────────────────────────────
  // Accepted by the backend only when TRUST_CLIENT_TIER_HEADERS=true (dev).
  // Replace with JWT once auth is wired up.
  static const String subscriptionTier = 'premium';

  // ── Health check ─────────────────────────────────────────────────────────

  /// Returns true if the backend responds with ok=true within [timeout].
  static Future<bool> isBackendReachable({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final response =
          await http.get(Uri.parse(healthUrl)).timeout(timeout);
      return response.statusCode == 200 &&
          (response.body.contains('"ok":true') ||
              response.body.contains('"ok": true'));
    } catch (_) {
      return false;
    }
  }
}
