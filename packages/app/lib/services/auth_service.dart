import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase auth (GoTrue): exposes the signed-in user and the
/// OAuth sign-in / sign-out actions, and notifies listeners when auth changes
/// (including the redirect that completes an OAuth round-trip on web).
class AuthService extends ChangeNotifier {
  AuthService() {
    _sub = _auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  final GoTrueClient _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _sub;

  User? get user => _auth.currentUser;
  bool get signedIn => user != null;
  String? get email => user?.email;

  String? get name {
    final m = user?.userMetadata;
    return (m?['full_name'] ?? m?['name']) as String?;
  }

  String? get avatarUrl => user?.userMetadata?['avatar_url'] as String?;

  /// Start a provider OAuth flow. On web this redirects the page back to the
  /// app's origin, where the SDK picks up the session and fires
  /// onAuthStateChange. On native, the redirect goes to a custom-scheme deep
  /// link (registered in AndroidManifest.xml / Info.plist and Supabase's
  /// Redirect URLs allowlist) that hands the browser back to the app; main.dart
  /// listens for it and exchanges the code, same as the web path does.
  Future<void> signIn(OAuthProvider provider) {
    return _auth.signInWithOAuth(
      provider,
      redirectTo: kIsWeb ? Uri.base.origin : 'gativani://login-callback',
    );
  }

  /// Email/password sign-up. Returns true if a session was granted immediately
  /// (email confirmation disabled); false means a confirmation email was sent
  /// and the caller should tell the user to check their inbox.
  Future<bool> signUpWithPassword(String email, String password,
      {String? name}) async {
    final res = await _auth.signUp(
      email: email,
      password: password,
      data: (name != null && name.isNotEmpty) ? {'full_name': name} : null,
    );
    return res.session != null;
  }

  Future<void> signInWithPassword(String email, String password) =>
      _auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
