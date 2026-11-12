import 'dart:convert';

/// The parts of the model's `config.json` the on-device pipeline needs.
class IndicTinyConfig {
  IndicTinyConfig({
    required this.sampleRate,
    required this.voices,
    required this.defaultVoice,
    required this.symbols,
    required this.addBlank,
    required this.melMean,
    required this.melStd,
    required this.nTimesteps,
    required this.temperature,
    required this.pauseSeconds,
    required this.lengthScale,
    required this.languageId,
    required this.speakerIds,
    required this.styleId,
    required this.nFft,
    required this.hop,
    required this.padding,
    required this.frameMultiple,
    required this.maxTokens,
  });

  final int sampleRate;
  final Map<String, String> voices; // voice name -> speaker key (female -> te_F)
  final String defaultVoice;
  final List<String> symbols; // namespaced: "c:క"
  final bool addBlank;
  final double melMean, melStd;
  final int nTimesteps;
  final double temperature;
  final double pauseSeconds;
  final Map<String, double> lengthScale; // per speaker key
  final int languageId;
  final Map<String, int> speakerIds;
  final int styleId;
  final int nFft, hop;
  final String padding;
  final int frameMultiple; // from onnx/onnx_manifest.json
  final int maxTokens; // from onnx/onnx_manifest.json

  late final Map<String, int> symbolId = {for (var i = 0; i < symbols.length; i++) symbols[i]: i};

  factory IndicTinyConfig.fromJson(String configJson, String manifestJson) {
    final c = json.decode(configJson) as Map<String, dynamic>;
    final m = json.decode(manifestJson) as Map<String, dynamic>;
    final vocab = c['vocab'] as Map<String, dynamic>;
    final syn = (c['synthesis'] as Map<String, dynamic>?) ?? const {};
    final ids = c['ids'] as Map<String, dynamic>;
    final head = (c['vocoder'] as Map<String, dynamic>)['head'] as Map<String, dynamic>;
    final style = (syn['style'] as String?) ?? 'read';
    final mel = (c['mel_stats'] as List).cast<num>();
    return IndicTinyConfig(
      sampleRate: (c['sample_rate'] as num).toInt(),
      voices: (c['voices'] as Map).map((k, v) => MapEntry(k as String, v as String)),
      defaultVoice: (c['default_voice'] as String?) ?? (c['voices'] as Map).keys.first as String,
      symbols: (vocab['symbols'] as List).cast<String>(),
      addBlank: (vocab['add_blank'] as bool?) ?? true,
      melMean: mel[0].toDouble(),
      melStd: mel[1].toDouble(),
      nTimesteps: (syn['n_timesteps'] as num?)?.toInt() ?? 4,
      temperature: (syn['temperature'] as num?)?.toDouble() ?? 0.667,
      pauseSeconds: (syn['sentence_pause_s'] as num?)?.toDouble() ?? 0.15,
      lengthScale: ((syn['length_scale'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      languageId: (ids['language'] as num).toInt(),
      speakerIds: (ids['speakers'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
      styleId: ((ids['styles'] as Map)[style] as num).toInt(),
      nFft: (head['n_fft'] as num).toInt(),
      hop: (head['hop_length'] as num).toInt(),
      padding: (head['padding'] as String?) ?? 'same',
      frameMultiple: (m['frame_multiple'] as num).toInt(),
      maxTokens: (m['max_tokens'] as num).toInt(),
    );
  }
}
