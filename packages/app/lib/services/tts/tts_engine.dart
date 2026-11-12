import 'dart:typed_data';

/// A text-to-speech engine that runs on the device: text in, mono PCM out. Nothing here touches the network.
abstract class TtsEngine {
  /// Short id, e.g. `indic-tiny-te`.
  String get id;

  /// Voices this engine offers, e.g. `female`, `male`.
  List<String> get voices;

  /// Load models. Safe to call twice.
  Future<void> init();

  /// Speak [text]. [speed] > 1 talks faster. Returns float samples in [-1, 1] at [TtsAudio.sampleRate].
  Future<TtsAudio> synthesize(String text, {String? voice, double speed = 1.0});

  /// Free sessions and buffers.
  Future<void> dispose();
}

class TtsAudio {
  const TtsAudio(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;

  double get seconds => samples.length / sampleRate;

  /// 16-bit PCM WAV bytes (for caching or playing through a file player).
  Uint8List toWav() {
    final n = samples.length;
    final out = ByteData(44 + n * 2);
    void str(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    out.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, 1, Endian.little); // mono
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    str(36, 'data');
    out.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767.0).round();
      out.setInt16(44 + i * 2, v, Endian.little);
    }
    return out.buffer.asUint8List();
  }
}
