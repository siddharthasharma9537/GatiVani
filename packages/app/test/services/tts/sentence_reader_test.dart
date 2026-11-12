import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/tts/sentence_reader.dart';

class _FakeOutput implements SentenceOutput {
  _FakeOutput(this.label, {this.failInit = false, this.failOn, this.rtf, this.speakTime = const Duration(milliseconds: 5)});
  @override
  final String label;
  final bool failInit;
  final String? failOn;
  final Duration speakTime;
  double? rtf;
  final log = <String>[];
  double speed = 1.0;
  var _stopped = false;
  var _paused = false;
  Completer<void>? _resumeSignal;
  Completer<void>? _stopSignal;

  @override
  double? get realTimeFactor => rtf;
  @override
  Future<void> init() async {
    log.add('init');
    if (failInit) throw StateError('no model');
  }

  @override
  Future<void> prepare(String text) async => log.add('prepare:$text');
  @override
  Future<void> play(String text) async {
    log.add('play:$text');
    if (failOn != null && text.contains(failOn!)) throw StateError('synth failed');
    _stopped = false;
    _stopSignal = Completer<void>();
    await Future.any([Future<void>.delayed(speakTime), _stopSignal!.future]);
    while (_paused && !_stopped) {
      _resumeSignal = Completer<void>();
      await Future.any([_resumeSignal!.future, _stopSignal!.future]);
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    log.add('pause');
  }

  @override
  Future<void> resume() async {
    _paused = false;
    log.add('resume');
    _resumeSignal?.complete();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _paused = false;
    log.add('stop');
    if (!(_stopSignal?.isCompleted ?? true)) _stopSignal!.complete();
  }

  @override
  Future<void> setSpeed(double s) async => speed = s;
  @override
  Future<void> dispose() async => log.add('dispose');
}

const _story = 'మొదటి వాక్యం ఇక్కడ ఉంది. రెండో వాక్యం ఇక్కడ ఉంది. మూడో వాక్యం ఇక్కడ ఉంది. నాలుగో వాక్యం ఇక్కడ ఉంది.';

List<String> _played(_FakeOutput o) => o.log.where((l) => l.startsWith('play:')).map((l) => l.substring(5)).toList();

void main() {
  test('reads every sentence in order and ends', () async {
    final out = _FakeOutput('on-device');
    final r = SentenceReader(primary: out)..load(_story);
    expect(r.sentences.length, 4);
    await r.play();
    expect(_played(out), r.sentences);
    expect(r.state, ReaderState.ended);
    expect(r.progress, 1);
  });

  test('prepares the next sentences ahead of time (look-ahead 2)', () async {
    final out = _FakeOutput('on-device', speakTime: const Duration(milliseconds: 30));
    final r = SentenceReader(primary: out)..load(_story);
    final f = r.play();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final prepared = out.log.where((l) => l.startsWith('prepare:')).map((l) => l.substring(8)).toList();
    expect(prepared, [r.sentences[1], r.sentences[2]]);
    await f;
  });

  test('pause and resume continue from the same sentence; stop keeps the position', () async {
    final out = _FakeOutput('on-device', speakTime: const Duration(milliseconds: 40));
    final r = SentenceReader(primary: out)..load(_story);
    final f = r.play();
    await Future<void>.delayed(const Duration(milliseconds: 55)); // inside sentence 1
    await r.pause();
    expect(r.state, ReaderState.paused);
    final at = r.index;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(r.index, at, reason: 'paused: no progress');
    await r.resume();
    await f;
    expect(r.state, ReaderState.ended);

    final out2 = _FakeOutput('on-device', speakTime: const Duration(milliseconds: 40));
    final r2 = SentenceReader(primary: out2)..load(_story);
    final f2 = r2.play();
    await Future<void>.delayed(const Duration(milliseconds: 55));
    await r2.stop();
    await f2;
    expect(r2.state, ReaderState.idle);
    final kept = r2.index;
    expect(kept, greaterThan(0));
    await r2.play();
    expect(_played(out2).last, r2.sentences.last);
    expect(_played(out2).where((t) => t == r2.sentences[kept]).length, 2, reason: 'the interrupted sentence is read again from its start');
  });

  test('seek and next/previous', () async {
    final out = _FakeOutput('on-device', speakTime: const Duration(milliseconds: 20));
    final r = SentenceReader(primary: out)..load(_story);
    await r.seekToSentence(2);
    expect(r.index, 2);
    await r.play();
    expect(_played(out), [r.sentences[2], r.sentences[3]]);
    r.load(_story);
    await r.seekToSentence(99);
    expect(r.index, 3);
    await r.seekToSentence(-5);
    expect(r.index, 0);
  });

  test('speed is passed to the output', () async {
    final out = _FakeOutput('on-device');
    final r = SentenceReader(primary: out)..load(_story);
    await r.setSpeed(1.5);
    await r.play();
    expect(out.speed, 1.5);
  });

  test('falls back when the on-device voice fails to start', () async {
    final a = _FakeOutput('on-device', failInit: true);
    final b = _FakeOutput('system');
    final r = SentenceReader(primary: a, fallback: b)..load(_story);
    await r.play();
    expect(_played(a), isEmpty);
    expect(_played(b), r.sentences);
    expect(r.outputLabel, 'system');
    expect(r.fallbackReason, contains('failed to start'));
    expect(r.state, ReaderState.ended);
  });

  test('falls back mid-story when one sentence fails, repeating that sentence on the fallback', () async {
    final a = _FakeOutput('on-device', failOn: 'మూడో');
    final b = _FakeOutput('system');
    final r = SentenceReader(primary: a, fallback: b)..load(_story);
    await r.play();
    expect(_played(a), [r.sentences[0], r.sentences[1], r.sentences[2]]);
    expect(_played(b), [r.sentences[2], r.sentences[3]]);
    expect(r.fallbackReason, contains('failed on a sentence'));
  });

  test('falls back when the model is slower than real time', () async {
    final a = _FakeOutput('on-device', rtf: 1.6);
    final b = _FakeOutput('system');
    final r = SentenceReader(primary: a, fallback: b)..load(_story);
    await r.play();
    expect(_played(a).length, 2, reason: 'the check needs 2 measured sentences');
    expect(_played(b), [r.sentences[2], r.sentences[3]]);
    expect(r.fallbackReason, contains('slower than real time'));
  });

  test('a fast model stays on-device', () async {
    final a = _FakeOutput('on-device', rtf: 0.3);
    final b = _FakeOutput('system');
    final r = SentenceReader(primary: a, fallback: b)..load(_story);
    await r.play();
    expect(_played(b), isEmpty);
    expect(r.fallbackReason, isNull);
  });

  test('without a fallback a failure becomes an error state', () async {
    final a = _FakeOutput('on-device', failInit: true);
    final r = SentenceReader(primary: a)..load(_story);
    await r.play();
    expect(r.state, ReaderState.error);
    expect(r.error, contains('failed to start'));
  });

  test('a second play() while playing does not start a second reader loop', () async {
    final out = _FakeOutput('on-device', speakTime: const Duration(milliseconds: 20));
    final r = SentenceReader(primary: out)..load(_story);
    final f = r.play();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await r.play();
    await f;
    expect(_played(out), r.sentences);
  });
}
