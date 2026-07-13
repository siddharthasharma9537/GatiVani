import 'package:shared_preferences/shared_preferences.dart';

/// The user's own Gemini API key (BYOK). Narrating/processing a newspaper
/// edition the user uploaded costs real money per call — instead of that
/// falling on the shared GEMINI_API_KEY, Paper/OCR requests run on the
/// user's own key. Stored locally only (SharedPreferences — browser
/// localStorage on web) and attached as a header on requests the user
/// themselves triggers; never persisted server-side.
class GeminiKeyStore {
  static const _prefKey = 'user_gemini_api_key';
  static String? _key;

  static bool get hasKey => _key != null && _key!.isNotEmpty;
  static String? get key => _key;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _key = prefs.getString(_prefKey);
  }

  static Future<void> setKey(String? value) async {
    final trimmed = value?.trim();
    _key = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (_key == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, _key!);
    }
  }

  /// Attach to any request that may need the user's Gemini key. Empty when
  /// no key is set — harmless to send on requests that don't require one.
  static Map<String, String> get headers =>
      hasKey ? {'x-user-gemini-key': _key!} : const {};
}
