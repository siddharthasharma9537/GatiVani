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
  /// app's origin, where the SDK picks up the session and fires onAuthStateChange.
  Future<void> signIn(OAuthProvider provider) {
    return _auth.signInWithOAuth(
      provider,
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
