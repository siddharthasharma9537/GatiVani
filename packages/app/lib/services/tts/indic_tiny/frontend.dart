import 'config.dart';
import 'telugu_normalizer.dart';

/// Text side of the pipeline: text -> numbers spelled out ([TeluguNormalizer]) -> the characters the model reads -> chunks ->
/// token ids. Ported from `indic_tiny_tts/frontend/textproc.py` and `tokenizer.py`. Characters the vocabulary still lacks are
/// dropped and listed in [lastDropped], so nothing is skipped silently.
class IndicTinyFrontend {
  IndicTinyFrontend(this.config);
  final IndicTinyConfig config;

  /// Characters the last [normalize] call had to drop (not in the model's vocabulary).
  final Set<String> lastDropped = {};

  static const _pauseLike = {':': ',', ';': ',', '…': '.', '–': ',', '—': ','};
  static const _maxChunk = 250; // characters; longer sentences are split at commas
  static final _letter = RegExp(r'\p{L}', unicode: true);

  static const _telugu = TeluguNormalizer();

  String normalize(String text) {
    lastDropped.clear();
    final known = config.symbolId;
    final b = StringBuffer();
    // Ellipses within a phrase are a pause, not a second synthesis chunk (AI proposal).
    for (final rune in _telugu.normalize(text.replaceAll(RegExp(r'\.{2,}|…+'), ',')).runes) {
      final ch = String.fromCharCode(rune);
      if (ch == ' ' || known.containsKey('c:$ch')) {
        b.write(ch);
      } else if (_pauseLike[ch] != null && known.containsKey('c:${_pauseLike[ch]}')) {
        b.write(_pauseLike[ch]);
      } else if (ch.trim().isEmpty) {
        b.write(' '); // tabs, newlines, zero-width spaces
      } else {
        lastDropped.add(ch);
        b.write(' ');
      }
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Split at sentence ends (. ? ! ।) followed by space; sentences over 250 characters are cut at a comma or a space.
  List<String> chunks(String norm) {
    final sentences = <String>[];
    var start = 0;
    for (var i = 0; i < norm.length; i++) {
      if ('।?!.'.contains(norm[i]) && i + 1 < norm.length && norm[i + 1] == ' ') {
        sentences.add(norm.substring(start, i + 1));
        start = i + 2;
      }
    }
    sentences.add(norm.substring(start));
    final out = <String>[];
    for (var sent in sentences) {
      while (sent.length > _maxChunk) {
        var cut = sent.lastIndexOf(',', _maxChunk - 1);
        cut = cut > 0 ? cut + 1 : sent.lastIndexOf(' ', _maxChunk - 1);
        if (cut <= 0) cut = _maxChunk;
        out.add(sent.substring(0, cut).trim());
        sent = sent.substring(cut).trim();
      }
      out.add(sent.trim());
    }
    return out.where((c) => _letter.hasMatch(c)).toList();
  }

  /// Token ids for one chunk, with the blank (id 0) between and around every symbol.
  List<int> ids(String chunk) {
    final syms = <int>[];
    for (final rune in chunk.runes) {
      syms.add(config.symbolId['c:${String.fromCharCode(rune)}']!);
    }
    if (!config.addBlank) return syms;
    final out = List<int>.filled(2 * syms.length + 1, 0);
    for (var i = 0; i < syms.length; i++) {
      out[2 * i + 1] = syms[i];
    }
    return out;
  }
}
