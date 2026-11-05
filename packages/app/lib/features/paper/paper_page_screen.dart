import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/papers.dart';
import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../services/news_feed_service.dart';
import '../../services/settings_provider.dart';
import '../live/live_feed_screen.dart' show TakeCard, playGatiVaniTake;
import 'paper_hub_screen.dart' show ReviewNote;

/// One paper's page. The hero is GatiVani's own daily Take, labelled as not
/// from the paper. Nothing is fetched from the paper itself.
class PaperPageScreen extends StatefulWidget {
  const PaperPageScreen({super.key, required this.paperId});
  final String paperId;

  @override
  State<PaperPageScreen> createState() => _PaperPageScreenState();
}

class _PaperPageScreenState extends State<PaperPageScreen> {
  final _feed = NewsFeedService();
  Explainer? _take;
  bool _loading = true;
  String? _newsLang;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lang = context.read<SettingsProvider>().newsLanguage;
    _newsLang = lang;
    final take = await _feed.fetchExplainer(lang: lang);
    if (!mounted) return;
    setState(() {
      _take = take;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.lang;
    final p = GatiPalette.of(context);
    final paper = paperById(widget.paperId);
    // Same pattern as the Live tab: refetch when the News Language changes.
    if (_newsLang != null && _newsLang != settings.newsLanguage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    if (paper == null) {
      return Scaffold(
          backgroundColor: p.paper,
          body: SafeArea(child: _Header(lang: lang, title: '')));
    }
    final name = paper.name(lang);
    String withPaper(String key) => tr(lang, key).replaceAll('{paper}', name);
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: Column(children: [
          _Header(lang: lang, title: name),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    if (_take != null)
                      TakeCard(
                          take: _take!,
                          onListen: () => playGatiVaniTake(
                              _take!, _newsLang ?? 'te'))
                    else
                      Container(
                        padding: const EdgeInsets.all(Gati.s4),
                        decoration: BoxDecoration(
                            color: p.surface,
                            borderRadius: BorderRadius.circular(Gati.rCard),
                            border: Border.all(color: p.line)),
                        child: Text(
                            tr(lang,
                                _loading ? 'paper_take_loading' : 'paper_take_none'),
                            style: TextStyle(fontSize: 14, color: p.muted)),
                      ),
                    const SizedBox(height: Gati.s2),
                    Text(withPaper('paper_take_label'),
                        style: TextStyle(
                            fontSize: 13, height: 1.4, color: p.muted)),
                    const SizedBox(height: Gati.s6),
                    Text(tr(lang, 'paper_your_copy'),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: p.ink)),
                    const SizedBox(height: Gati.s2),
                    Text(withPaper('paper_upload_copy'),
                        style: TextStyle(
                            fontSize: 14, height: 1.5, color: p.ink)),
                    const SizedBox(height: Gati.s3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: kPaper,
                            minimumSize: const Size(44, 48)),
                        onPressed: () =>
                            context.push('/paper/uploads?upload=1'),
                        icon: const Icon(Icons.upload_file_rounded, size: 20),
                        label: Text(tr(lang, 'paper_upload_btn')),
                      ),
                    ),
                    const SizedBox(height: Gati.s3),
                    Text(withPaper('paper_official_audio'),
                        style: TextStyle(fontSize: 13, color: p.muted)),
                    if (lang == 'te') ...[
                      const SizedBox(height: Gati.s4),
                      const ReviewNote(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.lang, required this.title});
  final String lang;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.dark ? GatiDark.band : Gati.band,
        border: Border(bottom: BorderSide(color: p.line, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        IconButton(
          tooltip: tr(lang, 'back'),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Icon(Icons.arrow_back, color: p.ink),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/paper'),
        ),
        Expanded(
          child: Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: p.ink)),
        ),
      ]),
    );
  }
}
