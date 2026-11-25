import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design/tokens.dart';
import '../../../l10n/strings.dart';
import '../../../services/settings_provider.dart';
import 'paper_models.dart';
import 'paper_repository.dart';
import '../audio/paper_audio_ui.dart';

String paperLang(BuildContext context) =>
    context.watch<SettingsProvider>().lang;

// Telugu section names are AI proposals, not native-reader approved.
const _sectionTelugu = [
  'మొదటి పేజీ',
  'సంపాదకీయ వార్తలు',
  'వ్యాపారం',
  'సినిమా',
  'ఛాంపియన్ (క్రీడలు)',
  'వసుంధర',
  'ప్రతిభ',
  'చదువు',
  'ప్రాంతీయ',
  'జాతీయ',
  'చివరి పేజీ',
  'సాధారణ వార్తలు',
];
String paperSectionLabel(String id, String lang) {
  final index = paperSectionIds.indexOf(id);
  if (index < 0) return id;
  return lang == 'te' ? _sectionTelugu[index] : paperSectionTitles[index];
}

void showPaperAbout(BuildContext context, String lang) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(lang, 'paper_about')),
        content:
            SingleChildScrollView(child: Text(tr(lang, 'paper_about_text'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel))
        ],
      ),
    );

class TodayPaperScreen extends StatefulWidget {
  const TodayPaperScreen({super.key, this.repository});
  final PaperRepository? repository;
  @override
  State<TodayPaperScreen> createState() => _TodayPaperScreenState();
}

class _TodayPaperScreenState extends State<TodayPaperScreen> {
  late final _repo = widget.repository ?? PaperRepository();
  List<PaperDay> _days = [];
  PaperDay? _day;
  List<PaperStory> _stories = [];
  String? _section;
  bool _loading = true, _failed = false, _saved = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cached = await _repo.cachedView();
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _days = cached.days;
        _day = cached.day;
        _stories = cached.stories;
        _section = cached.section;
        _saved = true;
        _loading = false;
      });
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final days = await _repo.latestDays();
      final day = days.where((d) => d.edition == _day?.edition).firstOrNull ??
          days.firstOrNull;
      final stories = day == null ? <PaperStory>[] : await _repo.stories(day);
      if (!mounted || request != _request) return;
      setState(() {
        _days = days;
        _day = day;
        _stories = stories;
        _loading = false;
        _saved = false;
        _selectSection();
      });
      if (day == null) {
        await _repo.clearCache();
      } else {
        await _cache();
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _failed = true;
          _saved = _day != null;
        });
      }
    }
  }

  Future<void> _pick(PaperDay day) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final stories = await _repo.stories(day);
      if (!mounted || request != _request) return;
      setState(() {
        _day = day;
        _stories = stories;
        _loading = false;
        _saved = false;
        _selectSection();
      });
      await _cache();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _failed = true;
          _saved = _day != null;
        });
      }
    }
  }

  void _selectSection() {
    if (!_stories.any((s) => s.section == _section)) {
      _section = paperSectionIds
          .where((id) => _stories.any((s) => s.section == id))
          .firstOrNull;
    }
  }

  Future<void> _cache() async {
    final day = _day;
    if (day != null) {
      await _repo.cacheView(PaperView(_days, day, _stories, _section));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = paperLang(context);
    final visible = _stories.where((s) => s.section == _section).toList();
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        title: Text(tr(lang, 'today_paper')),
        actions: [
          IconButton(
              tooltip: tr(lang, 'paper_refresh'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: tr(lang, 'paper_about'),
              onPressed: () => showPaperAbout(context, lang),
              icon: const Icon(Icons.info_outline)),
        ],
      ),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            children: [
              if (_days.isNotEmpty && _day != null)
                DropdownButtonFormField<String>(
                  initialValue: _day!.edition,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr(lang, 'paper_edition')),
                  items: [
                    for (final day in _days)
                      DropdownMenuItem(
                          value: day.edition, child: Text(day.title))
                  ],
                  onChanged: _loading
                      ? null
                      : (id) => _pick(_days.firstWhere((d) => d.edition == id)),
                ),
              if (_day != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('${tr(lang, 'paper_source')}, ${_day!.date}',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ),
              if (_day != null)
                PaperAudioEntry(edition: _day!.edition, date: _day!.date),
              if (_loading) ...[
                const LinearProgressIndicator(),
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(tr(lang, 'paper_loading'))),
              ],
              if (_failed) ...[
                Text(
                    '${tr(lang, 'paper_error')} ${_saved ? tr(lang, 'paper_cached') : ''}',
                    style: TextStyle(color: p.muted)),
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                        onPressed: _refresh,
                        child: Text(tr(lang, 'paper_retry')))),
              ],
              if (_day == null && !_loading && !_failed)
                Text(tr(lang, 'paper_empty')),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final id in paperSectionIds)
                  if (_stories.any((s) => s.section == id))
                    ChoiceChip(
                      label: Text(
                          '${paperSectionLabel(id, lang)} · ${_stories.where((s) => s.section == id).length}'),
                      selected: _section == id,
                      onSelected: (_) {
                        setState(() => _section = id);
                        _cache();
                      },
                    ),
              ]),
              if (_day != null && visible.isEmpty && !_loading)
                Text(tr(lang, 'paper_no_stories')),
              for (final story in visible)
                Card(
                  color: p.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Gati.rCard),
                      side: BorderSide(color: p.line)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Gati.rCard),
                    onTap: () => context
                        .push(Uri(path: '/paper/today/story', queryParameters: {
                      'edition': story.edition,
                      'date': story.date,
                      'id': story.id,
                    }).toString()),
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (story.graphic)
                                GraphicHeadline(story: story, lang: lang),
                              if (story.headline.isNotEmpty || !story.graphic)
                                Semantics(
                                    header: true,
                                    child: Text(
                                        story.headline.isEmpty
                                            ? tr(lang, 'paper_no_headline')
                                            : story.headline,
                                        style: TextStyle(
                                            fontSize: 19,
                                            height: 1.4,
                                            fontWeight: FontWeight.w600,
                                            color: p.ink))),
                              const SizedBox(height: 8),
                              Text(
                                  '${tr(lang, 'paper_pages')} ${story.pages.join(', ')} · ${story.words} ${tr(lang, 'paper_words')}',
                                  style: TextStyle(color: p.muted)),
                            ])),
                  ),
                ),
            ],
          ),
        ),
      ))),
    );
  }
}

class GraphicHeadline extends StatelessWidget {
  const GraphicHeadline({super.key, required this.story, required this.lang});
  final PaperStory story;
  final String lang;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(lang, 'paper_graphic'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (story.imageUrl != null)
          Image.network(story.imageUrl!,
              fit: BoxFit.fitWidth,
              semanticLabel: tr(lang, 'paper_graphic'),
              errorBuilder: (_, __, ___) =>
                  Text(tr(lang, 'paper_picture_missing'))),
      ]);
}
