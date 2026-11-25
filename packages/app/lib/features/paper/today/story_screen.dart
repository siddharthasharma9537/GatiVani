import 'package:flutter/material.dart';
import '../../../design/tokens.dart';
import '../../../l10n/strings.dart';
import '../listen_panel.dart';
import 'paper_models.dart';
import 'paper_repository.dart';
import 'today_screen.dart';

class PublishedStoryScreen extends StatefulWidget {
  const PublishedStoryScreen(
      {super.key,
      required this.edition,
      required this.date,
      required this.id,
      this.repository});
  final String edition, date, id;
  final PaperRepository? repository;
  @override
  State<PublishedStoryScreen> createState() => _PublishedStoryScreenState();
}

class _PublishedStoryScreenState extends State<PublishedStoryScreen> {
  late final _repo = widget.repository ?? PaperRepository();
  PaperStory? _story;
  bool _loading = true, _failed = false, _saved = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PublishedStoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.edition != widget.edition ||
        oldWidget.date != widget.date ||
        oldWidget.id != widget.id) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final edition = widget.edition, date = widget.date, id = widget.id;
    setState(() {
      _story = null;
      _loading = true;
      _failed = false;
      _saved = false;
    });
    final cached = await _repo.cachedView();
    if (!mounted || request != _request) return;
    final saved = cached?.stories
        .where((s) => s.edition == edition && s.date == date && s.id == id)
        .firstOrNull;
    if (saved != null) {
      setState(() {
        _story = saved;
        _saved = true;
      });
    }
    try {
      final story = await _repo.story(edition, date, id);
      if (!mounted || request != _request) return;
      setState(() {
        _story = story;
        _loading = false;
        _saved = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = paperLang(context);
    final story = _story;
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
          backgroundColor: p.paper,
          foregroundColor: p.ink,
          title: Text(tr(lang, 'paper_story')),
          actions: [
            IconButton(
                tooltip: tr(lang, 'paper_about'),
                onPressed: () => showPaperAbout(context, lang),
                icon: const Icon(Icons.info_outline))
          ]),
      bottomNavigationBar: story == null || story.narration.trim().isEmpty
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45),
              child: SingleChildScrollView(
                  child: ListenPanel(
                key: ValueKey(
                    '${story.edition}/${story.date}/${story.id}/${story.narration.hashCode}'),
                narration: story.narration,
                lang: lang,
              )),
            ),
      body: SafeArea(
          child: RefreshIndicator(
              onRefresh: _load,
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 60),
                    children: [
                      if (_loading) const LinearProgressIndicator(),
                      if (_failed) ...[
                        Text(
                            '${tr(lang, 'paper_story_error')} ${_saved ? tr(lang, 'paper_cached') : ''}'),
                        TextButton(
                            onPressed: _load,
                            child: Text(tr(lang, 'paper_retry'))),
                      ],
                      if (story == null && !_failed && !_loading)
                        Text(tr(lang, 'paper_story_missing')),
                      if (story != null)
                        PublishedStoryText(story: story, lang: lang),
                    ]),
              )))),
    );
  }
}

class PublishedStoryText extends StatelessWidget {
  const PublishedStoryText(
      {super.key, required this.story, required this.lang});
  final PaperStory story;
  final String lang;
  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    Widget item(PaperItem i) {
      final heading = i.role == 'subheading';
      return Padding(
          padding: EdgeInsets.only(top: heading ? 12 : 0, bottom: 14),
          child: Semantics(
            header: heading,
            child: Text(
                i.role == 'byline'
                    ? '${tr(lang, 'paper_byline')}: ${i.text}'
                    : i.text,
                style: TextStyle(
                    fontSize: heading ? 22 : (i.role == 'byline' ? 14 : 18),
                    height: 1.65,
                    fontWeight: heading || i.role == 'deck'
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: i.role == 'byline' ? kAccent : p.ink)),
          ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${tr(lang, 'paper_source')}, ${story.date}',
          style: TextStyle(color: p.muted, fontSize: 12)),
      const SizedBox(height: 12),
      Text(paperSectionLabel(story.section, lang),
          style: const TextStyle(color: kAccent)),
      for (final kicker in story.items.where((i) => i.role == 'kicker'))
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(kicker.text,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.muted))),
      if (story.graphic) GraphicHeadline(story: story, lang: lang),
      if (story.headline.isNotEmpty || !story.graphic)
        Semantics(
            header: true,
            child: Text(
                story.headline.isEmpty
                    ? tr(lang, 'paper_no_headline')
                    : story.headline,
                style: TextStyle(
                    fontSize: 26,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: p.ink))),
      const SizedBox(height: 14),
      if (story.byline.isNotEmpty &&
          !story.items.any((i) => i.role == 'byline'))
        item(PaperItem('byline', story.byline)),
      for (final i in story.items.where(
          (i) => !['headline', 'kicker', 'caption', 'side'].contains(i.role)))
        item(i),
      for (final role in ['caption', 'side'])
        if (story.items.any((i) => i.role == role))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(Gati.rCard),
                border: Border.all(color: p.line)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                  header: true,
                  child: Text(
                      tr(lang,
                          role == 'caption' ? 'paper_captions' : 'paper_side'),
                      style: const TextStyle(color: kAccent))),
              for (final i in story.items.where((i) => i.role == role))
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(i.text,
                        style: TextStyle(
                            fontSize: 16, height: 1.6, color: p.muted))),
            ]),
          ),
      const SizedBox(height: 16),
      Text('${tr(lang, 'paper_pages')} ${story.pages.join(', ')}',
          style: TextStyle(color: p.muted)),
      for (final continuation in story.continuation)
        Text(
            '${tr(lang, 'paper_continues')} ${continuation['page']}${continuation['linked'] == true ? '' : ' · ${tr(lang, 'paper_unmatched')}'}',
            style: TextStyle(color: p.muted)),
    ]);
  }
}
