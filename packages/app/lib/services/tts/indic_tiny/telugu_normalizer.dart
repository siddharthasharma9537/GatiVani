/// Telugu text normaliser for the on-device TTS.
///
/// The core is a port of the model's own `textnorm` for `lang="te"` (indic-tiny-tts-telugu, MIT): invisible characters removed,
/// repeated vowel signs collapsed, bracketed non-speech tags and Latin glosses dropped, and the digit-spelling rules (plain
/// integers; leading zeros and 10+ digits read digit by digit; Western/Indian grouping such as 1,30,650; Telugu cardinals in the
/// lakh/crore system).
///
/// The "extensions" go beyond what the model's own normaliser reads for Telugu (it leaves percent, currency, decimals, dates and
/// times unread, so the model's frontend would drop them): rupee amounts, percent, decimals, dates, clock times, ordinals ("12వ"),
/// a few unit abbreviations and Latin capital acronyms. These readings are AI proposals, not checked by a native Telugu reader.
///
/// Dart has no Unicode NFC; only the one composition Telugu needs (ె + ౖ -> ై) is applied.
class TeluguNormalizer {
  const TeluguNormalizer();

  // ------------------------------------------------------------ number words (port of numbers.py, te)
  static const _base = [
    'సున్నా', 'ఒకటి', 'రెండు', 'మూడు', 'నాలుగు', 'ఐదు', 'ఆరు', 'ఏడు', 'ఎనిమిది', 'తొమ్మిది',
    'పది', 'పదకొండు', 'పన్నెండు', 'పదమూడు', 'పద్నాలుగు', 'పదిహేను', 'పదహారు', 'పదిహేడు', 'పద్దెనిమిది', 'పందొమ్మిది',
  ];
  static const _tens = ['ఇరవై', 'ముప్పై', 'నలభై', 'యాభై', 'అరవై', 'డెబ్బై', 'ఎనభై', 'తొంభై'];

  /// Words for 0..99.
  static final List<String> units = () {
    final out = <String>[..._base];
    for (final t in _tens) {
      out.add(t);
      for (var u = 1; u < 10; u++) {
        out.add('$t ${_base[u]}');
      }
    }
    return out;
  }();

  // The non-final form (వందల, వేల, ...) is used when a smaller non-zero part follows.
  static String _hundred(int d, bool isFinal) {
    if (d == 1) return isFinal ? 'వంద' : 'నూట';
    return isFinal ? '${units[d]} వందలు' : '${units[d]} వందల';
  }

  static const _scaleForms = {
    'thousand': ['వేలు', 'వేల'],
    'lakh': ['లక్షలు', 'లక్షల'],
    'crore': ['కోట్లు', 'కోట్ల'],
  };
  static const _scaleOne = {'thousand': 'వెయ్యి', 'lakh': 'ఒక లక్ష', 'crore': 'ఒక కోటి'};

  static String _scale(int value, String scale, bool isFinal) {
    if (value == 1) return _scaleOne[scale]!;
    return '${units[value]} ${_scaleForms[scale]![isFinal ? 0 : 1]}';
  }

  /// Cardinal words for 0 <= n < 10^9.
  static String cardinal(int n) {
    if (n < 0 || n >= 1000000000) throw RangeError.range(n, 0, 999999999, 'n');
    if (n < 100) return units[n];
    var rest = n;
    final crore = rest ~/ 10000000;
    rest %= 10000000;
    final lakh = rest ~/ 100000;
    rest %= 100000;
    final thousand = rest ~/ 1000;
    rest %= 1000;
    final hundred = rest ~/ 100;
    rest %= 100;
    final values = [crore, lakh, thousand, hundred, rest];
    const scales = ['crore', 'lakh', 'thousand', 'hundred', ''];
    final words = <String>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == 0) continue;
      final isFinal = !values.skip(i + 1).any((x) => x != 0);
      final s = scales[i];
      if (s.isEmpty) {
        words.add(units[v]);
      } else if (s == 'hundred') {
        words.add(_hundred(v, isFinal));
      } else {
        words.add(_scale(v, s, isFinal));
      }
    }
    return words.join(' ');
  }

  static String _digitWords(String digits) => digits.split('').map((d) => units[int.parse(d)]).join(' ');

  /// Words for an integer written with ASCII digits: a leading zero or 10+ digits are read digit by digit.
  static String integerWords(String digits) {
    if ((digits.length > 1 && digits[0] == '0') || digits.length > 9) return _digitWords(digits);
    return cardinal(int.parse(digits));
  }

  static final _westernGroups = RegExp(r'^\d{1,3}(?:,\d{3})+$');
  static final _indianGroups = RegExp(r'^\d{1,2}(?:,\d{2})+,\d{3}$');

  /// ASCII digits of a valid Western/Indian grouped number, else null.
  static String? _grouped(String body) =>
      (_westernGroups.hasMatch(body) || _indianGroups.hasMatch(body)) ? body.replaceAll(',', '') : null;

  // ------------------------------------------------------------ generic cleaning (port of core.py, te path)
  static final _ws = RegExp(r'\s+');
  static final _zeroWidth = RegExp('[​‌‍⁠﻿­]');
  // an exactly repeated Telugu vowel sign is a typo
  static final _repeatedSign = RegExp('([ా-ౄె-ైొ-ౌౢౣ])\\1+');
  static const _nonspeech = {
    'noise', 'uhh', 'ugh', 'umm', 'talking', 'horn', 'unintelligible', 'stammers', 'buzz', 'buzzer', 'music', 'singing', 'popping',
    'breathing', 'inhaling', 'laugh', 'bird_squawk', 'throat_clearing', 'child_talking', 'phone_vibrating',
  };
  static final _tag = RegExp(r'\s*(?:\[\s*([A-Za-z_]+)\s*\]|\(\s*([a-z_]+)\s*\))');
  static final _snake = RegExp(r'^[a-z]+(?:_[a-z]+)+$');
  static const _latin = 'A-Za-zÀ-ÖØ-öø-ɏ';
  static final _gloss = RegExp('\\s*(\\[[$_latin .\'’&/-]*\\]|\\([$_latin .\'’&/-]*\\))');
  static final _hasLatin = RegExp('[$_latin]');
  static final _latinChar = RegExp('[$_latin]');

  static bool _isTelugu(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 0x0c00 && c <= 0x0c7f;
  }

  static String _collapse(String s) => s.split(_ws).where((p) => p.isNotEmpty).join(' ');

  static String _clean(String text) {
    var s = text.replaceAll(_zeroWidth, '').replaceAll('ై', 'ై');
    s = _collapse(s).replaceAllMapped(_repeatedSign, (m) => m.group(1)!);
    s = s.replaceAllMapped(_tag, (m) {
      final w = (m.group(1) ?? m.group(2) ?? '').toLowerCase();
      return (_nonspeech.contains(w) || _snake.hasMatch(w)) ? ' ' : m.group(0)!;
    });
    // A bracketed Latin gloss right after a Telugu word is not spoken: "స్మార్ట్‌ఫోన్ (smart phone)" -> "స్మార్ట్‌ఫోన్".
    for (var i = 0; i < 5; i++) {
      final before = s;
      s = _collapse(before.replaceAllMapped(_gloss, (m) {
        if (m.start > 0 && _isTelugu(before[m.start - 1]) && _hasLatin.hasMatch(m.group(1)!)) return '';
        return m.group(0)!;
      }));
      if (s == before) break;
    }
    return _collapse(s);
  }

  // ------------------------------------------------------------ extensions (AI proposals, see the class comment)
  static const _months = [
    'జనవరి', 'ఫిబ్రవరి', 'మార్చి', 'ఏప్రిల్', 'మే', 'జూన్', 'జులై', 'ఆగస్టు', 'సెప్టెంబరు', 'అక్టోబరు', 'నవంబరు', 'డిసెంబరు',
  ];

  /// Telugu digits (౦-౯, U+0C66..U+0C6F) -> ASCII, so one set of rules reads both.
  static String _asciiDigits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      b.writeCharCode(r >= 0x0c66 && r <= 0x0c6f ? 0x30 + (r - 0x0c66) : r);
    }
    return b.toString();
  }

  static const _scaleWords = [
    'వేల', 'వేలు', 'వెయ్యి', 'లక్షల', 'లక్షలు', 'లక్ష', 'కోట్ల', 'కోట్లు', 'కోటి', 'వందల', 'వందలు', 'వంద', 'మిలియన్', 'బిలియన్',
  ];
  static const _unitWords = {
    'km': 'కిలోమీటర్లు', 'kg': 'కిలోలు', 'cm': 'సెంటీమీటర్లు', 'mm': 'మిల్లీమీటర్లు', 'm': 'మీటర్లు', 'l': 'లీటర్లు',
    'ml': 'మిల్లీలీటర్లు', 'gb': 'జిబి', 'mb': 'ఎంబి', 'mw': 'మెగావాట్లు', 'kw': 'కిలోవాట్లు',
  };
  static const _abbrev = {
    'కి.మీ.': 'కిలోమీటర్లు', 'కి.మీ': 'కిలోమీటర్లు', 'సెం.మీ.': 'సెంటీమీటర్లు', 'సెం.మీ': 'సెంటీమీటర్లు',
    'మి.మీ.': 'మిల్లీమీటర్లు', 'డా.': 'డాక్టర్',
  };
  static const _letterNames = {
    'A': 'ఎ', 'B': 'బి', 'C': 'సి', 'D': 'డి', 'E': 'ఈ', 'F': 'ఎఫ్', 'G': 'జి', 'H': 'హెచ్', 'I': 'ఐ', 'J': 'జె', 'K': 'కె',
    'L': 'ఎల్', 'M': 'ఎం', 'N': 'ఎన్', 'O': 'ఓ', 'P': 'పి', 'Q': 'క్యూ', 'R': 'ఆర్', 'S': 'ఎస్', 'T': 'టి', 'U': 'యు',
    'V': 'వి', 'W': 'డబ్ల్యూ', 'X': 'ఎక్స్', 'Y': 'వై', 'Z': 'జెడ్',
  };

  static final _date = RegExp(r'(?<![\d])(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(?![\d])');
  static final _time = RegExp(r'(?<![\d:])(\d{1,2}):(\d{2})(?![\d:])');
  // "₹", "రూ." or "రూ" right before a number
  static final _rupees = RegExp('(?:₹\\s?|రూ\\.?\\s?)(\\d[\\d,]*(?:\\.\\d+)?)');
  static final _percent = RegExp(r'(\d[\d,]*(?:\.\d+)?)\s?%');
  static final _decimal = RegExp(r'(?<![\d.,])(\d{1,9})\.(\d+)(?![\d.])');
  static final _ordinal = RegExp('(?<![\\d,.])(\\d{1,3})వ(?![ఀ-౿])');
  static final _digitsUnit = RegExp(r'(\d)\s?(km|kg|cm|mm|ml|gb|mb|mw|kw|m|l)(?![A-Za-z])', caseSensitive: false);
  static final _acronym = RegExp(r'(?<![A-Za-z])([A-Z]{2,6})(?![A-Za-z])');
  static final _rupeeMark = RegExp('\u0000R((?:\\s*(?:${_scaleWords.join('|')})(?![ఀ-౿]))*)');

  static String _num(String body) {
    if (body.contains(',')) {
      final g = _grouped(body);
      return g != null ? integerWords(g) : body.split(',').map(integerWords).join(', ');
    }
    return integerWords(body);
  }

  static String _decimalWords(String n) {
    final parts = n.split('.');
    return '${_num(parts[0])} పాయింట్ ${_digitWords(parts[1])}';
  }

  static String _number(String n) => n.contains('.') ? _decimalWords(n) : _num(n);

  static String _ordinalWord(int n) {
    if (n == 1) return 'మొదటి';
    var w = cardinal(n);
    if (w.endsWith('ు') || w.endsWith('ి')) {
      w = w.substring(0, w.length - 1);
    } else if (w.endsWith('ై')) {
      w = '${w.substring(0, w.length - 1)}య్య';
    }
    return '$wవ';
  }

  static String _extensions(String text) {
    var s = _asciiDigits(text);
    _abbrev.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAllMapped(_date, (m) {
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
      if (d < 1 || d > 31 || mo < 1 || mo > 12) return m.group(0)!;
      return '${_months[mo - 1]} ${cardinal(d)}, ${cardinal(int.parse(m.group(3)!))}';
    });
    s = s.replaceAllMapped(_time, (m) {
      final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
      if (h < 1 || h > 24 || mi > 59) return m.group(0)!;
      return mi == 0 ? '${cardinal(h)} గంటలు' : '${cardinal(h)} గంటల ${cardinal(mi)} నిమిషాలు';
    });
    // "రూ. 40 వేల కోట్లు" -> "నలభై వేల కోట్లు రూపాయలు": the word for rupees goes after any scale words that follow the number
    s = s.replaceAllMapped(_rupees, (m) => '${_number(m.group(1)!)}\u0000R');
    s = s.replaceAllMapped(_rupeeMark, (m) => '${m.group(1)} రూపాయలు');
    s = s.replaceAllMapped(_percent, (m) => '${_number(m.group(1)!)} శాతం');
    s = s.replaceAllMapped(_decimal, (m) => _decimalWords('${m.group(1)}.${m.group(2)}'));
    s = s.replaceAllMapped(_ordinal, (m) => _ordinalWord(int.parse(m.group(1)!)));
    s = s.replaceAllMapped(_digitsUnit, (m) => '${m.group(1)} ${_unitWords[m.group(2)!.toLowerCase()]}');
    return s;
  }

  // ------------------------------------------------------------ digits (port of verbalize_digits, te)
  static final _numToken = RegExp(r'\d(?:\d|,(?=\d))*');

  static String _verbalizeDigits(String text) {
    final out = StringBuffer();
    var pos = 0;
    for (final m in _numToken.allMatches(text)) {
      final body = m[0]!;
      final String words;
      if (body.contains(',')) {
        final g = _grouped(body);
        words = g != null ? integerWords(g) : body.split(',').map(integerWords).join(', ');
      } else {
        words = integerWords(body);
      }
      out.write(text.substring(pos, m.start));
      // Direct join to Telugu letters (case suffixes: "140ఏళ్ల"), a space against Latin letters.
      if (m.start > 0 && _latinChar.hasMatch(text[m.start - 1])) out.write(' ');
      out.write(words);
      if (m.end < text.length && _latinChar.hasMatch(text[m.end])) out.write(' ');
      pos = m.end;
    }
    out.write(text.substring(pos));
    return out.toString();
  }

  static String _acronyms(String s) =>
      s.replaceAllMapped(_acronym, (m) => m.group(1)!.split('').map((c) => _letterNames[c]!).join(' '));

  /// Raw text -> Telugu text the model's vocabulary can read (numbers and the extensions spelled out).
  String normalize(String text) {
    var s = _clean(text);
    s = _extensions(s);
    s = _verbalizeDigits(s);
    s = _acronyms(s);
    return _collapse(s);
  }
}
