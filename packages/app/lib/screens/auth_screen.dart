import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/settings_provider.dart';

/// Login / signup UI scaffolding. Styled and navigable, but not yet wired to a
/// real auth backend — the primary action shows a demo notice. [signUp] picks
/// the initial mode; the user can toggle between the two.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signUp = false});
  final bool signUp;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.signUp;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final title = tr(lang, _signUp ? 'sign_up' : 'sign_in');
    return Scaffold(
      backgroundColor: kPaper,
      appBar: AppBar(
        backgroundColor: kPaper,
        surfaceTintColor: kPaper,
        elevation: 0,
        foregroundColor: kInk,
        title: Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w500, color: kInk)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.headphones_rounded, color: kAccent, size: 34),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600, color: kInk)),
            const SizedBox(height: 22),
            if (_signUp) _field(lang, 'name', Icons.person_outline),
            if (_signUp) const SizedBox(height: 12),
            _field(lang, 'email', Icons.mail_outline),
            const SizedBox(height: 12),
            _field(lang, 'password', Icons.lock_outline, obscure: true),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: kPaper,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(lang, 'auth_note'))),
              ),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: () => setState(() => _signUp = !_signUp),
                child: Text(
                    tr(lang, _signUp ? 'have_account' : 'no_account'),
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: kAccent,
                        fontWeight: FontWeight.w500)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(lang, 'continue_guest'),
                    style: const TextStyle(fontSize: 13, color: kMuted)),
              ),
            ),
            const SizedBox(height: 24),
            Text(tr(lang, 'auth_note'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: kMuted)),
          ],
        ),
      ),
    );
  }

  Widget _field(String lang, String key, IconData icon, {bool obscure = false}) {
    return TextField(
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: tr(lang, key),
        prefixIcon: Icon(icon, size: 20, color: kMuted),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE7E4DB))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE7E4DB))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAccent)),
      ),
    );
  }
}
