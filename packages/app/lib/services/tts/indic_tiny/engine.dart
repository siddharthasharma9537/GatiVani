import 'dart:math' as math;
import 'dart:typed_data';

import '../tts_engine.dart';
import 'config.dart';
import 'dsp.dart';
import 'frontend.dart';
import 'onnx_runner.dart';

/// Indic Tiny TTS Telugu (sulabhkatiyar/indic-tiny-tts-telugu; weights CC-BY-4.0, code MIT) running on the device through an
/// [OnnxRunner]. Pipeline, as in the model's own `TinyTTSOnnx`: text encoder -> durations -> length regulation -> 4 Euler steps
/// of the flow decoder from noise -> mel -> vocoder spectrum -> inverse STFT.
class IndicTinyEngine implements TtsEngine {
  IndicTinyEngine({required this.config, required this.runner, this.seed});

  final IndicTinyConfig config;
  final OnnxRunner runner;
  final int? seed; // fixed noise for repeatable audio (tests); null = new noise each time
  late final IndicTinyFrontend frontend = IndicTinyFrontend(config);
  bool _loaded = false;

  static const _minFrames = 2; // a chunk shorter than this many mel frames is skipped (the inverse STFT needs >= 2)

  @override
  String get id => 'indic-tiny-te';

  @override
  List<String> get voices => config.voices.keys.toList();

  @override
  Future<void> init() async {
    if (_loaded) return;
    await runner.load();
    _loaded = true;
  }

  @override
  Future<void> dispose() => runner.dispose();

  @override
  Future<TtsAudio> synthesize(String text, {String? voice, double speed = 1.0}) async {
    await init();
    if (speed < 0.25 || speed > 4.0) throw ArgumentError('speed must be between 0.25 and 4.0, got $speed');
    final v = voice ?? config.defaultVoice;
    final spk = config.voices[v];
    if (spk == null) throw ArgumentError('unknown voice $v; choose from ${voices.join(', ')}');
    final lengthScale = (config.lengthScale[spk] ?? 1.0) / speed;
    final rng = math.Random(seed);
    final pause = Float32List((config.pauseSeconds * config.sampleRate).toInt());
    final pieces = <Float32List>[];
    for (final chunk in frontend.chunks(frontend.normalize(text))) {
      final wav = await _speakChunk(frontend.ids(chunk), spk, lengthScale, rng);
      if (wav == null) continue;
      if (pieces.isNotEmpty) pieces.add(pause);
      pieces.add(wav);
    }
    final total = pieces.fold<int>(0, (a, p) => a + p.length);
    final out = Float32List(total);
    var off = 0;
    for (final p in pieces) {
      out.setRange(off, off + p.length, p);
      off += p.length;
    }
    return TtsAudio(out, config.sampleRate);
  }

  Future<Float32List?> _speakChunk(List<int> ids, String spk, double lengthScale, math.Random rng) async {
    if (ids.length > config.maxTokens) {
      throw StateError('${ids.length} tokens > ${config.maxTokens}: the text frontend should have chunked this');
    }
    final enc = await runner.run('text_encoder', {
      'tokens': Tensor.i64([1, ids.length], ids),
      'token_lengths': Tensor.i64([1], [ids.length]),
      'language': Tensor.i64([1], [config.languageId]),
      'speaker': Tensor.i64([1], [config.speakerIds[spk]!]),
      'style': Tensor.i64([1], [config.styleId]),
    });
    final muX = enc[0], logw = enc[1], cond = enc[2];
    final tx = muX.shape.last;
    final channels = muX.shape[1];
    final d = durations(logw.floats!, lengthScale, config.frameMultiple);
    if (d.yLen < _minFrames) return null;
    final reg = lengthRegulate(muX.floats!, channels, tx, d.wCeil, d.yLen, d.yPad);

    // Euler ODE from temperature-scaled noise, config.nTimesteps steps (t in [0,1]).
    final n = channels * d.yPad;
    var x = Float32List(n);
    for (var i = 0; i < n; i++) {
      x[i] = _gauss(rng) * config.temperature;
    }
    final span = torchLinspace(0.0, 1.0, config.nTimesteps + 1);
    var t = span[0];
    var dt = span[1] - span[0];
    final mask = Tensor.f32([1, 1, d.yPad], reg.yMask);
    final mu = Tensor.f32([1, channels, d.yPad], reg.muY);
    for (var step = 1; step < span.length; step++) {
      final v = (await runner.run('flow_decoder', {
        'x': Tensor.f32([1, channels, d.yPad], x),
        'mask': mask,
        'mu': mu,
        't': Tensor.f32([1], Float32List.fromList([t])),
        'cond': cond,
      }))[0].floats!;
      final nx = Float32List(n);
      for (var i = 0; i < n; i++) {
        nx[i] = x[i] + dt * v[i];
      }
      x = nx;
      t = t + dt;
      if (step < span.length - 1) dt = span[step + 1] - t;
    }

    // keep the first yLen frames, undo the mel normalisation
    final mel = Float32List(channels * d.yLen);
    for (var c = 0; c < channels; c++) {
      for (var j = 0; j < d.yLen; j++) {
        mel[c * d.yLen + j] = x[c * d.yPad + j] * config.melStd + config.melMean;
      }
    }
    final spec = await runner.run('vocoder', {'mel': Tensor.f32([1, channels, d.yLen], mel)});
    final real = spec[0], imag = spec[1];
    final bins = real.shape[1], frames = real.shape[2];
    final wav = istft(real.floats!, imag.floats!, bins, frames, config.nFft, config.hop, padding: config.padding);
    for (var i = 0; i < wav.length; i++) {
      wav[i] = wav[i].clamp(-1.0, 1.0);
    }
    return wav;
  }

  /// Standard normal sample (Box-Muller).
  double _gauss(math.Random rng) {
    final u1 = 1.0 - rng.nextDouble(), u2 = rng.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
  }
}
