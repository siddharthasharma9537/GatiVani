import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../services/tts/narration_controller.dart';
import '../../services/tts/sentence_reader.dart';

/// Shared "Listen" bar for published and local-review stories. Reads the story's narration text (headline once, then paragraphs and
/// subheadings; the server already leaves out markers, captions and side items) sentence by sentence with the on-device voice
/// (PlaybackService and its sign-in are not involved). In the browser the device's own voice is not used, so the text never
/// reaches a browser speech service: without the voice pack there is a download button instead.
class ListenPanel extends StatefulWidget {
  const ListenPanel(
      {super.key, required this.narration, this.lang = 'en', this.controller});
  final String narration;
  final String lang;
  final NarrationController? controller;

  @override
  State<ListenPanel> createState() => _ListenPanelState();
}

class _ListenPanelState extends State<ListenPanel> {
  late final NarrationController _ctl =
      widget.controller ?? NarrationController.i;
  SentenceReader? _r;
  bool _starting = false;
  String? _note;
  int _lastLogged = -1;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _ctl.allowSystemVoice = false;
    _load();
    _ctl.addListener(_rebuild);
  }

  Future<void> _load() async {
    await _ctl.load();
    if (_ctl.engine == NarrationEngine.cloud ||
        (kIsWeb && _ctl.engine == NarrationEngine.system)) {
      await _ctl.setEngine(NarrationEngine.auto);
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctl.removeListener(_rebuild);
    _r?.removeListener(_onReader);
    _r?.dispose();
    super.dispose();
  }

  void _onReader() {
    final r = _r;
    if (r != null && r.index != _lastLogged) {
      _lastLogged = r.index;
      if (r.state == ReaderState.playing || r.state == ReaderState.ended) {
        // ignore: avoid_print
        print(
            '[listen] ${r.outputLabel} sentence ${r.index.clamp(0, r.sentences.length)}/${r.sentences.length}'
            ' rtf=${r.realTimeFactor?.toStringAsFixed(3) ?? '-'} state=${r.state.name}');
      }
    }
    _rebuild();
  }

  Future<void> _start({int from = 0, bool play = true}) async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _note = null;
    });
    final old = _r;
    old?.removeListener(_onReader);
    final r = await _ctl.readerFor(widget.narration, startIndex: from);
    old?.dispose();
    if (!mounted) {
      r?.dispose();
      return;
    }
    if (r == null) {
      setState(() {
        _r = null;
        _starting = false;
        _note = kIsWeb ? 'paper_no_voice_web' : 'paper_no_voice_native';
      });
      return;
    }
    r.addListener(_onReader);
    await r.setSpeed(_speed);
    if (!mounted) {
      r.dispose();
      return;
    }
    _lastLogged = -1;
    // ignore: avoid_print
    print(
        '[listen] start: ${r.sentences.length} sentences, voice=${_ctl.voice}, output=${r.outputLabel}');
    setState(() {
      _r = r;
      _starting = false;
    });
    if (play) r.play();
  }

  double _speed = 1.0;

  Future<void> _changeVoice(String v) async {
    final r = _r;
    final at = r?.index ?? 0;
    final playing = r?.isPlaying ?? false;
    await _ctl.setVoice(v);
    if (r != null) {
      await r.stop();
      await _start(from: at, play: playing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final r = _r;
    final installed = _ctl.packStatus == PackStatus.installed;
    final installing = _ctl.packStatus == PackStatus.installing;
    final pct = _ctl.packTotal == 0
        ? 0.0
        : (_ctl.packDone / _ctl.packTotal).clamp(0.0, 1.0);
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
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r != null && r.sentences.isNotEmpty)
                      ..._sentenceView(p, r),
                    if (r?.state == ReaderState.error)
                      Text(tr(widget.lang, 'paper_voice_error')),
                    if (_note != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(tr(widget.lang, _note!),
                              style:
                                  TextStyle(fontSize: 12.5, color: kAccent))),
                    if (_ctl.packStatus == PackStatus.failed)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(tr(widget.lang, 'vs_failed'),
                              style: TextStyle(
                                  fontSize: 12.5, color: Gati.kumkuma))),
                    if (!installed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: installing
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    LinearProgressIndicator(
                                        value: pct,
                                        color: kAccent,
                                        backgroundColor: p.chip,
                                        minHeight: 5),
                                    const SizedBox(height: 4),
                                    Wrap(
                                        spacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                              '${tr(widget.lang, 'vs_downloading')} ${(pct * 100).round()}%',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: p.muted)),
                                          TextButton(
                                              onPressed: _ctl.cancelInstall,
                                              child: Text(
                                                  tr(widget.lang, 'cancel'))),
                                        ]),
                                  ])
                            : Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                    Text(tr(widget.lang, 'paper_pack_missing'),
                                        style: TextStyle(
                                            fontSize: 12.5, color: p.muted)),
                                    OutlinedButton(
                                        onPressed: _ctl.installPack,
                                        child: Text(tr(widget.lang,
                                            'paper_download_voice'))),
                                  ]),
                      ),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: kAccent,
                                foregroundColor: kPaper),
                            onPressed: _starting
                                ? null
                                : () {
                                    if (r == null ||
                                        r.state == ReaderState.ended ||
                                        r.state == ReaderState.error) {
                                      _start();
                                    } else if (r.isPlaying) {
                                      r.pause();
                                    } else if (r.state == ReaderState.idle) {
                                      r.play();
                                    } else {
                                      r.resume();
                                    }
                                  },
                            icon: _starting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kPaper))
                                : Icon(r != null && r.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded),
                            label:
                                Text(r == null || r.state == ReaderState.error
                                    ? tr(widget.lang, 'listen')
                                    : r.state == ReaderState.ended
                                        ? tr(widget.lang, 'paper_listen_again')
                                        : r.isPlaying
                                            ? tr(widget.lang, 'paper_pause')
                                            : tr(widget.lang, 'resume')),
                          ),
                          if (r != null) ...[
                            IconButton(
                                tooltip:
                                    tr(widget.lang, 'paper_previous_sentence'),
                                onPressed: r.previous,
                                icon: const Icon(Icons.skip_previous_rounded)),
                            IconButton(
                                tooltip: tr(widget.lang, 'paper_next_sentence'),
                                onPressed: r.next,
                                icon: const Icon(Icons.skip_next_rounded)),
                            IconButton(
                                tooltip: tr(widget.lang, 'paper_stop'),
                                onPressed: r.stop,
                                icon: const Icon(Icons.stop_rounded)),
                          ],
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                                visualDensity: VisualDensity.compact),
                            segments: [
                              ButtonSegment(
                                  value: 'female',
                                  label: Text(tr(widget.lang, 'paper_female'))),
                              ButtonSegment(
                                  value: 'male',
                                  label: Text(tr(widget.lang, 'paper_male')))
                            ],
                            selected: {_ctl.voice},
                            onSelectionChanged: (s) => _changeVoice(s.first),
                          ),
                        ]),
                    const SizedBox(height: 4),
                    Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(tr(widget.lang, 'paper_speed'),
                              style: TextStyle(fontSize: 12.5, color: p.muted)),
                          for (final s in const [0.75, 1.0, 1.25, 1.5, 2.0])
                            ChoiceChip(
                              label: Text('$s×'),
                              visualDensity: VisualDensity.compact,
                              selected: _speed == s,
                              onSelected: (_) {
                                setState(() => _speed = s);
                                r?.setSpeed(s);
                              },
                            ),
                        ]),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sentenceView(GatiPalette p, SentenceReader r) {
    final i = r.index.clamp(0, r.sentences.length - 1);
    Widget line(int k, {bool current = false}) =>
        k < 0 || k >= r.sentences.length
            ? const SizedBox.shrink()
            : Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 3),
                padding: EdgeInsets.symmetric(
                    horizontal: 8, vertical: current ? 6 : 2),
                decoration: BoxDecoration(
                    color: current
                        ? kAccent.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(r.sentences[k],
                    maxLines: current ? 4 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: current ? 17 : 13,
                        height: 1.45,
                        fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                        color: current ? p.ink : p.muted)),
              );
    final position = tr(widget.lang, 'paper_sentence')
        .replaceAll('{current}', '${i + 1}')
        .replaceAll('{total}', '${r.sentences.length}');
    return [
      Semantics(
          label: position,
          child: Column(
              children: [line(i - 1), line(i, current: true), line(i + 1)])),
      LinearProgressIndicator(
          value: r.progress,
          color: kAccent,
          backgroundColor: p.chip,
          minHeight: 4),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(
          position,
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
      ),
    ];
  }
}
