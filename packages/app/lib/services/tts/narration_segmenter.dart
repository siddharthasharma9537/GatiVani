/// Splits a story's narration text (one continuous story, no page markers) into sentences to read one at a time.
///
/// Boundaries: `।`, `॥`, `?`, `!`, and a single `.` followed by whitespace; ellipses are pauses within a phrase.
/// A blank line or a line break always ends a sentence
/// (headline, then body). A full stop is NOT a boundary after a known abbreviation (డా., రూ., శ్రీ., కి.మీ.) or a single capital
/// letter (initials), and never inside a number or date ("3.5", "12.11.2026": no whitespace follows the dot). Fragments with
/// no letter or digit are dropped; very short fragments are joined to the next sentence; sentences longer than [maxChars] are
/// cut at a comma, else a space.
class NarrationSegmenter {
  const NarrationSegmenter({this.maxChars = 220, this.minChars = 12});

  final int maxChars;
  final int minChars;

  static const _abbreviations = {
    'డా', 'రూ', 'శ్రీ', 'శ్రీమతి', 'సెం', 'మి', 'కి', 'మీ', 'ప్రొ', 'సం', 'తే', 'నం', 'Dr', 'Mr', 'Mrs', 'Ms', 'Rs', 'No', 'St',
  };
  static final _hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _ws = RegExp(r'\s');

  List<String> split(String text) {
    final sentences = <String>[];
    for (final para in text.replaceAll('\r', '').split(RegExp(r'\n+'))) {
      sentences.addAll(_splitParagraph(para.trim()));
    }
    // join very short fragments to the next sentence (a lone "ఈనాడు:" would be a choppy clip)
    final merged = <String>[];
    var carry = '';
    for (final s in sentences) {
      final joined = carry.isEmpty ? s : '$carry $s';
      if (joined.length < minChars && s != sentences.last) {
        carry = joined;
      } else {
        merged.add(joined);
        carry = '';
      }
    }
    if (carry.isNotEmpty) merged.add(carry);
    return [for (final s in merged) ..._cap(s)].where(_hasLetterOrDigit.hasMatch).toList();
  }

  List<String> _splitParagraph(String p) {
    if (p.isEmpty) return const [];
    final out = <String>[];
    var start = 0;
    for (var i = 0; i < p.length; i++) {
      final ch = p[i];
      if (!'।॥?!….'.contains(ch)) continue;
      // Newspaper headings use two or more dots (or …) inside one phrase.
      // Skip the whole run so its final dot cannot become a sentence boundary.
      if (ch == '…' || (ch == '.' && i + 1 < p.length && p[i + 1] == '.')) {
        while (i + 1 < p.length && '.…'.contains(p[i + 1])) {
          i++;
        }
        continue;
      }
      // swallow a run of closing punctuation/quotes: "?!" or ".”"
      var end = i + 1;
      while (end < p.length && '।॥?!….”’")'.contains(p[end])) {
        end++;
      }
      final atEnd = end >= p.length;
      if (!atEnd && !_ws.hasMatch(p[end])) continue; // "3.5", "12.11.2026", "a.b"
      if (ch == '.' && !atEnd && _isAbbreviation(p, start, i)) continue;
      out.add(p.substring(start, end).trim());
      start = end;
      i = end - 1;
    }
    if (start < p.length) out.add(p.substring(start).trim());
    return out;
  }

  bool _isAbbreviation(String p, int start, int dot) {
    var b = dot;
    while (b > start && !_ws.hasMatch(p[b - 1]) && p[b - 1] != '.') {
      b--;
    }
    final token = p.substring(b, dot);
    if (_abbreviations.contains(token)) return true;
    // an initial: one capital Latin letter
    if (token.length == 1 && RegExp(r'[A-Z]').hasMatch(token)) return true;
    // "కి.మీ." : the piece before this dot sits after another dot
    return b > start && p[b - 1] == '.' && _abbreviations.contains(token);
  }

  List<String> _cap(String s) {
    if (s.length <= maxChars) return [s];
    final out = <String>[];
    var rest = s;
    while (rest.length > maxChars) {
      var cut = -1;
      for (final c in const [',', ';', ':', '،']) {
        cut = cut > 0 ? cut : rest.lastIndexOf(c, maxChars - 1) + 1;
      }
      if (cut <= minChars) cut = rest.lastIndexOf(' ', maxChars);
      if (cut <= 0) cut = maxChars;
      out.add(rest.substring(0, cut).trim());
      rest = rest.substring(cut).trim();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }
}
