import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/api_config.dart';
import '../../../design/tokens.dart';
import '../../../l10n/strings.dart';
import '../today/today_screen.dart' show paperLang;
import 'paper_audio_models.dart';
import 'paper_audio_player.dart';
import 'paper_audio_repository.dart';

PaperAudioRepository defaultPaperAudioRepository() =>
    PaperAudioRepository(workerUrl: ApiConfig.paperAudioUrl);

String _clock(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

Uri paperAudioStoryUri(PaperAudioStory s, {bool autoplay = false}) =>
    Uri(path: '/paper/today/audio/story', queryParameters: {
      'edition': s.edition,
      'date': s.date,
      'id': s.storyId,
      if (autoplay) 'autoplay': '1',
    });

/// Card on the Today screen. Invisible unless the feature is configured and the signed-in user
/// can read audio rows for this day (anyone else gets an empty list from RLS, or an error).
class PaperAudioEntry extends StatefulWidget {
  const PaperAudioEntry(
      {super.key, required this.edition, required this.date, this.repository});
  final String edition, date;
  final PaperAudioRepository? repository;
  @override
  State<PaperAudioEntry> createState() => _PaperAudioEntryState();
}

class _PaperAudioEntryState extends State<PaperAudioEntry> {
  late final _repo = widget.repository ?? defaultPaperAudioRepository();
  PaperAudioPlaylist? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PaperAudioEntry old) {
    super.didUpdateWidget(old);
    if (old.edition != widget.edition || old.date != widget.date) _load();
  }

  Future<void> _load() async {
    setState(() => _list = null);
    if (!_repo.configured) return;
    try {
      final list = await _repo.playlist(widget.edition, widget.date);
      if (mounted) setState(() => _list = list);
    } catch (_) {
      // Not signed in, not the owner or offline: the entry simply stays hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null || list.stories.isEmpty) return const SizedBox.shrink();
    final p = GatiPalette.of(context);
    final lang = paperLang(context);
    return Card(
      color: p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gati.rCard),
          side: BorderSide(color: p.line)),
      child: ListTile(
        leading: const Icon(Icons.headphones_rounded, color: kAccent),
        title: Text(tr(lang, 'paper_audio_entry')),
        subtitle: Text(tr(lang, 'paper_audio_count')
            .replaceAll('{n}', '${list.stories.length}')
            .replaceAll('{min}', '${(list.totalSeconds / 60).round()}')),
        onTap: () =>
            context.push(Uri(path: '/paper/today/audio', queryParameters: {
          'edition': widget.edition,
          'date': widget.date,
        }).toString()),
      ),
    );
  }
}

/// The day's audio stories in `rank` order.
class PaperAudioListScreen extends StatefulWidget {
  const PaperAudioListScreen(
      {super.key, required this.edition, required this.date, this.repository});
  final String edition, date;
  final PaperAudioRepository? repository;
  @override
  State<PaperAudioListScreen> createState() => _PaperAudioListScreenState();
}

class _PaperAudioListScreenState extends State<PaperAudioListScreen> {
  late final _repo = widget.repository ?? defaultPaperAudioRepository();
  PaperAudioPlaylist? _list;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final list = await _repo.playlist(widget.edition, widget.date);
      if (mounted) setState(() => _list = list);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = paperLang(context);
    final list = _list;
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
          backgroundColor: p.paper,
          foregroundColor: p.ink,
          title: Text(tr(lang, 'paper_audio_entry'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: list == null && !_failed
                ? const LinearProgressIndicator()
                : _failed
                    ? Column(children: [
                        Text(tr(lang, 'paper_audio_unavailable')),
                        TextButton(
                            onPressed: _load,
                            child: Text(tr(lang, 'paper_retry'))),
                      ])
                    : ListView(padding: const EdgeInsets.all(16), children: [
                        if (list!.stories.isEmpty)
                          Text(tr(lang, 'paper_audio_unavailable')),
                        for (final s in list.stories)
                          ListTile(
                            leading: CircleAvatar(child: Text('${s.rank}')),
                            title: Text(s.headline),
                            subtitle: Text(
                                '${tr(lang, 'paper_pages')} ${s.page} · ${_clock(Duration(seconds: s.durationSeconds.round()))}'),
                            onTap: () => context.push(
                                paperAudioStoryUri(s, autoplay: true)
                                    .toString()),
                          ),
                      ]),
          ),
        ),
      ),
    );
  }
}

/// One story's audio, with the Listen controls (play/pause, seek, speed, previous/next story).
class PaperAudioStoryScreen extends StatefulWidget {
  const PaperAudioStoryScreen({
    super.key,
    required this.edition,
    required this.date,
    required this.id,
    this.autoplay = false,
    this.repository,
    this.playerFactory,
  });
  final String edition, date, id;
  final bool autoplay;
  final PaperAudioRepository? repository;
  final PaperAudioPlayer Function(PaperAudioRepository)? playerFactory;
  @override
  State<PaperAudioStoryScreen> createState() => _PaperAudioStoryScreenState();
}

class _PaperAudioStoryScreenState extends State<PaperAudioStoryScreen> {
  late final _repo = widget.repository ?? defaultPaperAudioRepository();
  late final PaperAudioPlayer _player =
      (widget.playerFactory ?? (r) => JustAudioPaperPlayer(r))(_repo);
  PaperAudioPlaylist? _list;
  bool _failed = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayer);
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final list = await _repo.playlist(widget.edition, widget.date);
      if (!mounted) return;
      setState(() => _list = list);
      final story = list.indexOf(widget.id) < 0
          ? null
          : list.stories[list.indexOf(widget.id)];
      if (story != null) await _player.load(story, autoplay: widget.autoplay);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onPlayer() {
    if (!mounted) return;
    setState(() {});
    // At the end of a story, go to the next one in rank order (once).
    if (_player.state == PaperAudioState.ended && !_advanced) {
      final next = _list?.next(widget.id);
      if (next != null) {
        _advanced = true;
        _go(next, autoplay: true);
      }
    }
  }

  void _go(PaperAudioStory s, {bool autoplay = false}) => context
      .pushReplacement(paperAudioStoryUri(s, autoplay: autoplay).toString());

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final lang = paperLang(context);
    final list = _list;
    final i = list?.indexOf(widget.id) ?? -1;
    final story = i < 0 ? null : list!.stories[i];
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
          backgroundColor: p.paper,
          foregroundColor: p.ink,
          title: Text(tr(lang, 'paper_story'))),
      bottomNavigationBar: story == null
          ? null
          : PaperAudioPanel(
              player: _player,
              lang: lang,
              onPrevious: list!.previous(widget.id) == null
                  ? null
                  : () => _go(list.previous(widget.id)!, autoplay: true),
              onNext: list.next(widget.id) == null
                  ? null
                  : () => _go(list.next(widget.id)!, autoplay: true),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(padding: const EdgeInsets.all(18), children: [
              if (list == null && !_failed) const LinearProgressIndicator(),
              if (_failed || (list != null && story == null)) ...[
                Text(tr(lang, 'paper_audio_unavailable')),
                TextButton(
                    onPressed: _load, child: Text(tr(lang, 'paper_retry'))),
              ],
              if (story != null) ...[
                Text(
                    tr(lang, 'paper_audio_position')
                        .replaceAll('{current}', '${i + 1}')
                        .replaceAll('{total}', '${list!.stories.length}'),
                    style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(height: 10),
                Semantics(
                    header: true,
                    child: Text(story.headline,
                        style: TextStyle(
                            fontSize: 26,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                            color: p.ink))),
                const SizedBox(height: 8),
                Text('${tr(lang, 'paper_pages')} ${story.page}',
                    style: TextStyle(color: p.muted)),
                if (_player.state == PaperAudioState.error)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(tr(lang, 'paper_audio_unavailable'),
                          style: TextStyle(color: Gati.kumkuma))),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Same look and the same controls as the on-device ListenPanel (play/pause, speed chips, stop),
/// plus previous/next story and a seek bar, driven by recorded audio instead of the on-device voice.
class PaperAudioPanel extends StatelessWidget {
  const PaperAudioPanel(
      {super.key,
      required this.player,
      required this.lang,
      this.onPrevious,
      this.onNext});
  final PaperAudioPlayer player;
  final String lang;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final s = player.state;
    final total = player.duration.inMilliseconds;
    final at = player.position.inMilliseconds;
    final loading = s == PaperAudioState.loading;
    return Material(
      color: p.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text(_clock(player.position),
                      style: TextStyle(fontSize: 12, color: p.muted)),
                  Expanded(
                    child: Slider(
                      value: total <= 0 ? 0 : at.clamp(0, total).toDouble(),
                      max: total <= 0 ? 1 : total.toDouble(),
                      onChanged: total <= 0
                          ? null
                          : (v) =>
                              player.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Text(_clock(player.duration),
                      style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                          tooltip: tr(lang, 'paper_audio_prev_story'),
                          onPressed: onPrevious,
                          icon: const Icon(Icons.skip_previous_rounded)),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: kAccent, foregroundColor: kPaper),
                        onPressed: loading
                            ? null
                            : () {
                                if (s == PaperAudioState.playing) {
                                  player.pause();
                                } else {
                                  player.play();
                                }
                              },
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: kPaper))
                            : Icon(s == PaperAudioState.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                        label: Text(s == PaperAudioState.playing
                            ? tr(lang, 'paper_pause')
                            : s == PaperAudioState.ended
                                ? tr(lang, 'paper_listen_again')
                                : s == PaperAudioState.paused
                                    ? tr(lang, 'resume')
                                    : tr(lang, 'listen')),
                      ),
                      IconButton(
                          tooltip: tr(lang, 'paper_audio_next_story'),
                          onPressed: onNext,
                          icon: const Icon(Icons.skip_next_rounded)),
                      IconButton(
                          tooltip: tr(lang, 'paper_stop'),
                          onPressed: player.stop,
                          icon: const Icon(Icons.stop_rounded)),
                    ]),
                const SizedBox(height: 4),
                Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(tr(lang, 'paper_speed'),
                          style: TextStyle(fontSize: 12.5, color: p.muted)),
                      for (final v in const [0.75, 1.0, 1.25, 1.5, 2.0])
                        ChoiceChip(
                          label: Text('$v×'),
                          visualDensity: VisualDensity.compact,
                          selected: player.speed == v,
                          onSelected: (_) => player.setSpeed(v),
                        ),
                    ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
