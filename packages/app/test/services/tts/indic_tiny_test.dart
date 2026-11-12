import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/tts/indic_tiny/config.dart';
import 'package:gativani_app/services/tts/indic_tiny/dsp.dart';
import 'package:gativani_app/services/tts/indic_tiny/engine.dart';
import 'package:gativani_app/services/tts/indic_tiny/frontend.dart';
import 'package:gativani_app/services/tts/indic_tiny/onnx_runner.dart';

const _configJson = '''
{"language":"te","sample_rate":24000,"voices":{"female":"te_F","male":"te_M"},"default_voice":"female",
 "mel_stats":[-2.4,2.4],
 "vocab":{"add_blank":true,"symbols":["<blank>","<unk>","c: ","c:.","c:,","c:క","c:ా","c:త"]},
 "synthesis":{"n_timesteps":4,"temperature":0.667,"style":"read","sentence_pause_s":0.15,"length_scale":{"te_F":0.9942,"te_M":1.0022}},
 "ids":{"language":6,"speakers":{"te_F":12,"te_M":13},"styles":{"read":0}},
 "vocoder":{"head":{"n_fft":8,"hop_length":2,"padding":"center"}}}
''';
const _manifestJson = '{"frame_multiple":2,"max_tokens":2048}';

IndicTinyConfig _cfg() => IndicTinyConfig.fromJson(_configJson, _manifestJson);

void main() {
  test('torchLinspace matches torch.linspace(0, 1, 5)', () {
    expect(torchLinspace(0, 1, 5).toList(), [0.0, 0.25, 0.5, 0.75, 1.0]);
  });

  test('durations: ceil(exp(logw)) * scale, mel length truncated, padded to the frame multiple', () {
    final logw = Float32List.fromList([0.0, math.log(2.5), math.log(1.2)]); // exp -> 1, 2.5, 1.2 ; ceil -> 1, 3, 2
    final d = durations(logw, 1.0, 2);
    expect(d.wCeil.toList(), [1.0, 3.0, 2.0]);
    expect(d.yLen, 6);
    expect(d.yPad, 6);
    final d2 = durations(Float32List.fromList([0.0, 0.0, 0.0]), 1.0, 2); // 3 frames -> pad to 4
    expect(d2.yLen, 3);
    expect(d2.yPad, 4);
  });

  test('lengthRegulate repeats each token for its duration, zero after the end', () {
    // 2 channels, 3 tokens; durations 1, 2, 1 -> frames: t0, t1, t1, t2, then padding
    final muX = Float32List.fromList([10, 20, 30, 1, 2, 3]);
    final r = lengthRegulate(muX, 2, 3, Float32List.fromList([1, 2, 1]), 4, 6);
    expect(r.muY.sublist(0, 6).toList(), [10, 20, 20, 30, 0, 0]);
    expect(r.muY.sublist(6, 12).toList(), [1, 2, 2, 3, 0, 0]);
    expect(r.yMask.toList(), [1, 1, 1, 1, 0, 0]);
  });

  test('irfftFrame equals a direct inverse DFT of a real-signal spectrum', () {
    const n = 16;
    final rng = math.Random(3);
    final x = List<double>.generate(n, (_) => rng.nextDouble() * 2 - 1);
    final re = Float64List(n ~/ 2 + 1), im = Float64List(n ~/ 2 + 1);
    for (var k = 0; k <= n ~/ 2; k++) {
      var a = 0.0, b = 0.0;
      for (var i = 0; i < n; i++) {
        a += x[i] * math.cos(2 * math.pi * k * i / n);
        b -= x[i] * math.sin(2 * math.pi * k * i / n);
      }
      re[k] = a;
      im[k] = b;
    }
    final back = irfftFrame(re, im, n);
    for (var i = 0; i < n; i++) {
      expect(back[i], closeTo(x[i], 1e-9));
    }
  });

  test('istft reconstructs a signal from its own STFT (overlap-add, centre padding)', () {
    const nFft = 16, hop = 4;
    final rng = math.Random(5);
    final len = 64;
    final sig = List<double>.generate(len, (_) => rng.nextDouble() * 2 - 1);
    final win = List<double>.generate(nFft, (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / nFft));
    // forward STFT with centre (reflect) padding, as torch.stft(center=True)
    final padded = <double>[];
    for (var i = 0; i < nFft ~/ 2; i++) {
      padded.insert(0, sig[i + 1]);
    }
    padded.addAll(sig);
    for (var i = 0; i < nFft ~/ 2; i++) {
      padded.add(sig[len - 2 - i]);
    }
    final frames = 1 + len ~/ hop;
    const bins = nFft ~/ 2 + 1;
    final real = Float32List(bins * frames), imag = Float32List(bins * frames);
    for (var f = 0; f < frames; f++) {
      for (var k = 0; k < bins; k++) {
        var a = 0.0, b = 0.0;
        for (var i = 0; i < nFft; i++) {
          final v = padded[f * hop + i] * win[i];
          a += v * math.cos(2 * math.pi * k * i / nFft);
          b -= v * math.sin(2 * math.pi * k * i / nFft);
        }
        real[k * frames + f] = a;
        imag[k * frames + f] = b;
      }
    }
    final out = istft(real, imag, bins, frames, nFft, hop);
    expect(out.length, len);
    for (var i = 8; i < len - 8; i++) {
      expect(out[i], closeTo(sig[i], 1e-4)); // interior samples (edges depend on the padding mode)
    }
  });

  test('frontend: drops unknown characters (and says so), keeps known ones, maps pause-like ones', () {
    final fe = IndicTinyFrontend(_cfg());
    expect(fe.normalize('కా 12 త;'), 'కా త,');
    expect(fe.lastDropped, {'1', '2'});
  });

  test('frontend: chunks at sentence ends, ids have a blank around every symbol', () {
    final fe = IndicTinyFrontend(_cfg());
    expect(fe.chunks('కా త. కా కా'), ['కా త.', 'కా కా']);
    expect(fe.ids('కా'), [0, 5, 0, 6, 0]);
  });

  test('engine: runs the three graphs with the right shapes and returns audio at the model rate', () async {
    final runner = _FakeRunner();
    final engine = IndicTinyEngine(config: _cfg(), runner: runner, seed: 1);
    final audio = await engine.synthesize('కా త. కా త', voice: 'male', speed: 1.0);
    expect(audio.sampleRate, 24000);
    expect(audio.samples.isNotEmpty, true);
    expect(runner.calls.where((c) => c == 'text_encoder').length, 2); // two chunks
    expect(runner.calls.where((c) => c == 'flow_decoder').length, 8); // 4 Euler steps each
    expect(runner.calls.where((c) => c == 'vocoder').length, 2);
    expect(runner.lastSpeaker, 13); // te_M
    expect(audio.toWav().sublist(0, 4), utf8.encode('RIFF'));
    expect(() => engine.synthesize('కా', voice: 'robot'), throwsArgumentError);
  });
}

/// Stands in for the ONNX graphs: fixed 4 frames per token, 100-channel mel, a spectrum of the right shape.
class _FakeRunner implements OnnxRunner {
  final calls = <String>[];
  int lastSpeaker = -1;
  static const _c = 100;

  @override
  Future<void> load() async {}
  @override
  Future<void> dispose() async {}

  @override
  Future<List<Tensor>> run(String graph, Map<String, Tensor> inputs) async {
    calls.add(graph);
    switch (graph) {
      case 'text_encoder':
        final tx = inputs['tokens']!.shape[1];
        lastSpeaker = inputs['speaker']!.ints![0];
        return [
          Tensor.f32([1, _c, tx], Float32List(_c * tx)),
          Tensor.f32([1, 1, tx], Float32List.fromList(List<double>.filled(tx, math.log(2.0)))),
          Tensor.f32([1, 112], Float32List(112)),
        ];
      case 'flow_decoder':
        final x = inputs['x']!;
        return [Tensor.f32(x.shape, Float32List(x.floats!.length))];
      case 'vocoder':
        final frames = inputs['mel']!.shape[2];
        const bins = 5; // n_fft 8 in the test config
        final re = Float32List(bins * frames);
        for (var i = 0; i < re.length; i++) {
          re[i] = 0.1;
        }
        return [Tensor.f32([1, bins, frames], re), Tensor.f32([1, bins, frames], Float32List(bins * frames))];
    }
    throw StateError(graph);
  }
}
