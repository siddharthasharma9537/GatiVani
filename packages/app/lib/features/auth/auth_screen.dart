import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/auth_service.dart';
import '../services/settings_provider.dart';

/// Login / signup — reached only when an account-tied action needs one
/// (playing audio, uploading a Paper edition; see PlaybackService and
/// today_screen.dart). Browsing itself never requires this screen, so it's
/// always safely poppable. OAuth (Google / Apple / Microsoft) is wired to
/// Supabase's hosted authorize endpoint — tapping a provider redirects
/// through Supabase, which completes the handshake and returns to the app.
/// The providers must be enabled with their client id + secret in the
/// Supabase dashboard for the round-trip to succeed (see
/// docs/AUTH_OAUTH_SETUP.md). Email/password goes straight to Supabase Auth.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signUp = false});
  final bool signUp;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.signUp;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Supabase provider codes. Microsoft is the "azure" provider in Supabase.
  static const _providers = [
    ('google', 'Google', Icons.g_mobiledata),
    ('apple', 'Apple', Icons.apple),
    ('azure', 'Microsoft', Icons.window),
  ];

  static const _providerMap = {
    'google': OAuthProvider.google,
    'apple': OAuthProvider.apple,
    'azure': OAuthProvider.azure,
  };

  Future<void> _oauth(String provider) async {
    final prov = _providerMap[provider];
    if (prov == null) return;
    try {
      // The SDK redirects (web) and, on return, picks up the session — the
      // router's redirect then lets the user through automatically.
      await context.read<AuthService>().signIn(prov);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
      }
    }
  }

  Future<void> _submitPassword() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    try {
      if (_signUp) {
        final gotSession = await auth.signUpWithPassword(email, password,
            name: _name.text.trim());
        if (!mounted) return;
        if (!gotSession) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Check your email to confirm your account.')));
        } else if (context.canPop()) {
          context.pop(); // back to whatever action asked for sign-in
        }
      } else {
        await auth.signInWithPassword(email, password);
        if (mounted && context.canPop()) context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    final title = tr(lang, _signUp ? 'sign_up' : 'sign_in');
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: p.paper,
        elevation: 0,
        foregroundColor: p.ink,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text(title,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w500, color: p.ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.headphones_rounded, color: kAccent, size: 34),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 22),

            // ── OAuth providers ──────────────────────────────────────────────
            for (final prov in _providers) ...[
              _oauthButton(p, lang, prov.$1, prov.$2, prov.$3),
              const SizedBox(height: 10),
            ],

            // ── divider ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Expanded(child: Divider(color: p.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or',
                      style: TextStyle(fontSize: 12.5, color: p.muted)),
                ),
                Expanded(child: Divider(color: p.line)),
              ]),
            ),

            // ── email / password ─────────────────────────────────────────────
            if (_signUp) _field(p, lang, 'name', Icons.person_outline,
                controller: _name),
            if (_signUp) const SizedBox(height: 12),
            _field(p, lang, 'email', Icons.mail_outline, controller: _email),
            const SizedBox(height: 12),
            _field(p, lang, 'password', Icons.lock_outline,
                obscure: true, controller: _password),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: kPaper,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _busy ? null : _submitPassword,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kPaper))
                  : Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: () => setState(() => _signUp = !_signUp),
                child: Text(tr(lang, _signUp ? 'have_account' : 'no_account'),
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: kAccent,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _oauthButton(GatiPalette p, String lang, String provider, String label,
          IconData icon) =>
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.line),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => _oauth(provider),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: p.ink),
          const SizedBox(width: 10),
          Text('${tr(lang, 'continue_with')} $label',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _field(GatiPalette p, String lang, String key, IconData icon,
      {bool obscure = false, TextEditingController? controller}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: p.ink),
      decoration: InputDecoration(
        labelText: tr(lang, key),
        labelStyle: TextStyle(color: p.muted),
        prefixIcon: Icon(icon, size: 20, color: p.muted),
        filled: true,
        fillColor: p.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAccent)),
      ),
    );
  }
}
