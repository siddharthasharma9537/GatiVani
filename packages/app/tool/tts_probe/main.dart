// Dev probe (not part of the app): runs the real Indic Tiny TTS Telugu voice pack through the app's own Dart pipeline in a
// browser, and reports real-time factor and output sanity. Build:  flutter build web -t tool/tts_probe/main.dart --output build/tts_probe
// It downloads the pinned voice pack from Hugging Face (same as the app does), then synthesises neutral test sentences with both
// voices. Results go to #result (JSON) and, if the page was served by a server that accepts PUT /upload/<name>, the WAVs are saved.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:gativani_app/services/tts/indic_tiny/config.dart';
import 'package:gativani_app/services/tts/indic_tiny/engine.dart';
import 'package:gativani_app/services/tts/indic_tiny/runner_factory.dart';
import 'package:gativani_app/services/tts/indic_tiny/telugu_normalizer.dart';
import 'package:gativani_app/services/tts/voice_pack/pack_manifest.dart';
import 'package:gativani_app/services/tts/voice_pack/voice_pack_store_factory.dart';
import 'package:web/web.dart' as web;

const _sentences = [
  'ఈ రోజు ఉదయం హైదరాబాద్‌లో తేలికపాటి వర్షం కురిసింది.',
  'రాష్ట్రంలో 140 పాఠశాలలకు కొత్త భవనాలు మంజూరయ్యాయి, ఇందుకు రూ. 15 కోట్లు ఖర్చు అవుతుంది.',
  'పరీక్షల్లో 85 శాతం మంది విద్యార్థులు ఉత్తీర్ణులయ్యారు.',
];

void _log(String s) {
  web.console.log(s.toJS);
  final el = web.document.getElementById('log');
  if (el != null) el.textContent = '${el.textContent}\n$s';
}

Future<void> main() async {
  final body = web.document.body!;
  body.innerHTML = '<pre id="log">tts probe</pre><pre id="result"></pre>'.toJS;
  final result = <String, Object?>{};
  try {
    final store = createVoicePackStore(VoicePackManifest.indicTinyTelugu);
    var lastPct = -1;
    if (!await store.isInstalled()) {
      _log('installing voice pack (${VoicePackManifest.indicTinyTelugu.totalBytes ~/ 1048576} MB)…');
      final sw = Stopwatch()..start();
      await store.install(onProgress: (d, t) {
        final pct = d * 100 ~/ t;
        if (pct != lastPct && pct % 10 == 0) {
          lastPct = pct;
          _log('  $pct%');
        }
      });
      result['install_seconds'] = sw.elapsedMilliseconds / 1000;
    }
    _log('pack installed and verified');
    final config = IndicTinyConfig.fromJson(await store.readText('config.json'), await store.readText('onnx_manifest.json'));
    final runner = createOnnxRunner(await store.modelLocations(), threads: 2);
    final engine = IndicTinyEngine(config: config, runner: runner, seed: 1);
    final loadSw = Stopwatch()..start();
    await engine.init();
    result['model_load_seconds'] = loadSw.elapsedMilliseconds / 1000;
    _log('model loaded in ${result['model_load_seconds']} s');
    result['normalised'] = [for (final s in _sentences) const TeluguNormalizer().normalize(s)];
    final runs = <Map<String, Object?>>[];
    for (final voice in ['female', 'male']) {
      for (var i = 0; i < _sentences.length; i++) {
        final sw = Stopwatch()..start();
        final audio = await engine.synthesize(_sentences[i], voice: voice);
        sw.stop();
        var peak = 0.0;
        var nan = 0;
        for (final v in audio.samples) {
          if (v.isNaN) nan++;
          if (v.abs() > peak) peak = v.abs();
        }
        final run = {
          'voice': voice,
          'sentence': i,
          'audio_seconds': audio.seconds,
          'synth_seconds': sw.elapsedMicroseconds / 1e6,
          'rtf': (sw.elapsedMicroseconds / 1e6) / audio.seconds,
          'peak': peak,
          'nan': nan,
          'dropped_chars': engine.frontend.lastDropped.join(),
        };
        runs.add(run);
        _log(jsonEncode(run));
        final name = '${voice}_$i.wav';
        final wav = audio.toWav();
        try {
          final init = web.RequestInit(method: 'PUT', body: wav.toJS);
          await web.window.fetch('/upload/$name'.toJS, init).toDart;
        } catch (_) {}
      }
    }
    result['runs'] = runs;
    result['user_agent'] = web.window.navigator.userAgent;
    result['hardware_concurrency'] = web.window.navigator.hardwareConcurrency;
    await engine.dispose();
    result['ok'] = true;
  } catch (e, st) {
    result['ok'] = false;
    result['error'] = '$e';
    result['stack'] = '$st'.split('\n').take(8).join('\n');
  }
  final text = const JsonEncoder.withIndent(' ').convert(result);
  web.document.getElementById('result')!.textContent = text;
  (web.window as JSObject).setProperty('probeResult'.toJS, text.toJS);
  (web.window as JSObject).setProperty('probeDone'.toJS, true.toJS);
}
