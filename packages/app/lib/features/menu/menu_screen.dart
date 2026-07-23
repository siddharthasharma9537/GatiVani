import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../config/districts.dart';
import '../design/components/gati_district_sheet.dart';
import '../design/components/gati_wordmark.dart';
import '../l10n/strings.dart';
import '../services/alerts_service.dart';
import '../services/auth_service.dart';
import '../services/settings_provider.dart';
import '../services/share_stub.dart'
    if (dart.library.html) '../services/share_web.dart' as share_;

/// The menu / account hub as a standalone route (kept for deep-links / native).
/// On the home shell it's rendered as the fixed reveal-drawer panel via
/// [MenuBody] instead of this Scaffold.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final p = GatiPalette.of(context);
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: p.paper,
        elevation: 0,
        foregroundColor: p.ink,
        title: Text(tr(lang, 'menu'),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w500, color: p.ink)),
      ),
      body: const SafeArea(child: MenuBody()),
    );
  }
}

/// The menu content (account + navigation) without any scaffold — shared by
/// the [MenuScreen] route and the home reveal drawer. Language, theme,
/// playback speed and the Gemini key live in the dedicated Settings screen
/// (reached via the row below) instead of inline here.
class MenuBody extends StatelessWidget {
  const MenuBody({super.key, this.padding});
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    final p = GatiPalette.of(context);
    return ListView(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ── Account ────────────────────────────────────────────────────────
        _accountCard(context, lang),
        const SizedBox(height: 20),

        // ── App — the things GatiVāni is actually about ────────────────────
        _sectionLabel(p, 'GatiVāni'),
        _card(p, Column(children: [
          _navRow(
              p,
              Icons.location_on_outlined,
              tr(lang, 'my_district'),
              districtByEn(s.district) == null
                  ? tr(lang, 'no_district')
                  : (lang == 'te'
                      ? districtByEn(s.district)!.te
                      : districtByEn(s.district)!.en),
              () => showGatiDistrictSheet(context)),
          Divider(height: 1, color: p.line),
          _alertsRow(context, p, lang),
          Divider(height: 1, color: p.line),
          _navRow(p, Icons.history_rounded, tr(lang, 'history'), null,
              () => context.push('/history')),
          Divider(height: 1, color: p.line),
          _navRow(p, Icons.headphones_rounded, tr(lang, 'tab_shows'), null,
              () => context.go('/shows')),
          Divider(height: 1, color: p.line),
          _navRow(p, Icons.settings_outlined, tr(lang, 'settings'), null,
              () => context.push('/settings')),
          if (share_.canShare) ...[
            Divider(height: 1, color: p.line),
            _navRow(p, Icons.share_outlined, tr(lang, 'share_app'), null,
                () => share_.shareContent(
                      title: 'GatiVāni',
                      text: tr(lang, 'share_app_message'),
                      url: 'https://gativani.sohum.cloud',
                    )),
          ],
        ])),
        const SizedBox(height: 24),

        // ── About ──────────────────────────────────────────────────────────
        Center(
          child: Column(children: [
            GatiWordmark(size: 18, color: p.ink, lang: lang, animated: false),
            const SizedBox(height: 2),
            Text(tr(lang, 'about_tagline'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
      ],
    );
  }

  // Signed-in user (avatar + name/email + log out) or the guest sign-in card.
  Widget _accountCard(BuildContext context, String lang) {
    final auth = context.watch<AuthService>();
    if (auth.signedIn) {
      final name = auth.name ?? auth.email ?? tr(lang, 'account');
      final email = auth.email ?? '';
      final avatar = auth.avatarUrl;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration:
            BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: GatiDark.accentSoft,
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? const Icon(Icons.person, color: Gati.pasupuGlow, size: 24)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kPaper,
                          fontSize: 16,
                          fontWeight: FontWeight.w500)),
                  if (email.isNotEmpty)
                    Text(email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Gati.onInkMuted, fontSize: 12.5)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: kPaper,
                  side: const BorderSide(color: Color(0xFF4A4A47)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => context.read<AuthService>().signOut(),
              child: Text(tr(lang, 'log_out'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ),
        ]),
      );
    }
    // Guest — sign in / create account.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: GatiDark.accentSoft, shape: BoxShape.circle),
            child: const Icon(Icons.person_outline,
                color: Gati.pasupuGlow, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(lang, 'guest'),
                  style: const TextStyle(
                      color: kPaper, fontSize: 16, fontWeight: FontWeight.w500)),
              Text(tr(lang, 'guest_sub'),
                  style: const TextStyle(
                      color: Gati.onInkMuted, fontSize: 12.5)),
            ],
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: kPaper,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => _openAuth(context, signUp: false),
              child: Text(tr(lang, 'sign_in'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: kPaper,
                  side: const BorderSide(color: Color(0xFF4A4A47)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => _openAuth(context, signUp: true),
              child: Text(tr(lang, 'sign_up'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ),
        ]),
      ]),
    );
  }

  void _openAuth(BuildContext context, {required bool signUp}) {
    context.push('/auth', extra: signUp);
  }

  // Alerts row with an unread dot — new items since the screen was last
  // opened light it up. AlertsService refreshes lazily in the background.
  Widget _alertsRow(BuildContext context, GatiPalette p, String lang) {
    AlertsService.i.refreshIfStale(context.read<SettingsProvider>());
    return ListenableBuilder(
      listenable: AlertsService.i,
      builder: (context, _) => InkWell(
        onTap: () => context.push('/alerts'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(Icons.notifications_none_rounded, size: 20, color: p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(lang, 'alerts'),
                      style: TextStyle(fontSize: 14.5, color: p.ink)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(tr(lang, 'alerts_sub'),
                        style: TextStyle(fontSize: 12, color: p.muted)),
                  ),
                ],
              ),
            ),
            if (AlertsService.i.unread > 0)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                    color: kAccent, shape: BoxShape.circle),
              ),
            Icon(Icons.chevron_right, size: 18, color: p.muted),
          ]),
        ),
      ),
    );
  }

  Widget _navRow(GatiPalette p, IconData icon, String label,
          String? subtitle, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 20, color: p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 14.5, color: p.ink)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          style: TextStyle(fontSize: 12, color: p.muted)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: p.muted),
          ]),
        ),
      );

  Widget _sectionLabel(GatiPalette p, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: p.muted,
                letterSpacing: 0.3)),
      );

  Widget _card(GatiPalette p, Widget child) => Container(
        decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Material(color: Colors.transparent, child: child),
      );
}
