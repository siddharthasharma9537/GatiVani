import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The user's own Gemini API key (BYOK). Narrating/processing a newspaper
/// edition the user uploaded costs real money per call — instead of that
/// falling on the shared GEMINI_API_KEY, Paper/OCR requests run on the
/// user's own key. Cached locally (SharedPreferences — browser localStorage
/// on web) and attached as a header on requests the user themselves triggers.
/// When signed in, it's also mirrored to Supabase Vault (see set_gemini_key /
/// get_gemini_key / clear_gemini_key RPCs) so the same account doesn't get
/// re-prompted on another device or after a reinstall.
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
    await _pushToRemote();
  }

  /// Call once after sign-in completes: if this device has no key cached yet,
  /// pull the one already registered against this account (set from another
  /// device, or before a reinstall) so the BYOK gate doesn't re-prompt.
  static Future<void> syncFromRemote() async {
    if (hasKey) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final remoteKey =
          await Supabase.instance.client.rpc('get_gemini_key') as String?;
      if (remoteKey != null && remoteKey.isNotEmpty) {
        _key = remoteKey;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKey, remoteKey);
      }
    } catch (_) {
      // Best-effort — an offline session just falls back to the local gate.
    }
  }

  static Future<void> _pushToRemote() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      if (_key == null) {
        await Supabase.instance.client.rpc('clear_gemini_key');
      } else {
        await Supabase.instance.client
            .rpc('set_gemini_key', params: {'p_key': _key});
      }
    } catch (_) {
      // Best-effort — the key still works locally even if the sync fails.
    }
  }

  /// Wipe only the local cache, without pushing a clear to the remote
  /// account. Call on sign-out so a different account signing in on this
  /// same device doesn't inherit the previous account's key before its own
  /// syncFromRemote() has a chance to run.
  static Future<void> clearLocal() async {
    _key = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  /// Attach to any request that may need the user's Gemini key. Empty when
  /// no key is set — harmless to send on requests that don't require one.
  static Map<String, String> get headers =>
      hasKey ? {'x-user-gemini-key': _key!} : const {};
}
