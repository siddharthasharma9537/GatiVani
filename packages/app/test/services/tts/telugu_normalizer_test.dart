import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/tts/indic_tiny/telugu_normalizer.dart';

/// Expected strings are hand-derived from the model's number tables (numbers.py, lang "te") and the extensions' own rules.
/// All Telugu sentences here are neutral test text written for this file (no newspaper content).
void main() {
  const n = TeluguNormalizer();

  group('cardinals (model port)', () {
    test('0..99', () {
      expect(TeluguNormalizer.cardinal(0), 'సున్నా');
      expect(TeluguNormalizer.cardinal(15), 'పదిహేను');
      expect(TeluguNormalizer.cardinal(21), 'ఇరవై ఒకటి');
      expect(TeluguNormalizer.cardinal(99), 'తొంభై తొమ్మిది');
    });
    test('hundreds, final and non-final forms', () {
      expect(TeluguNormalizer.cardinal(100), 'వంద');
      expect(TeluguNormalizer.cardinal(140), 'నూట నలభై');
      expect(TeluguNormalizer.cardinal(300), 'మూడు వందలు');
      expect(TeluguNormalizer.cardinal(305), 'మూడు వందల ఐదు');
    });
    test('thousand, lakh, crore', () {
      expect(TeluguNormalizer.cardinal(1000), 'వెయ్యి');
      expect(TeluguNormalizer.cardinal(2026), 'రెండు వేల ఇరవై ఆరు');
      expect(TeluguNormalizer.cardinal(10000), 'పది వేలు');
      expect(TeluguNormalizer.cardinal(100000), 'ఒక లక్ష');
      expect(TeluguNormalizer.cardinal(130650), 'ఒక లక్ష ముప్పై వేల ఆరు వందల యాభై');
      expect(TeluguNormalizer.cardinal(10000000), 'ఒక కోటి');
      expect(TeluguNormalizer.cardinal(25000000), 'రెండు కోట్ల యాభై లక్షలు'); // 2 crore 50 lakh
      expect(TeluguNormalizer.cardinal(250000000), 'ఇరవై ఐదు కోట్లు');
    });
    test('out of range throws', () {
      expect(() => TeluguNormalizer.cardinal(1000000000), throwsRangeError);
      expect(() => TeluguNormalizer.cardinal(-1), throwsRangeError);
    });
    test('no cardinal is empty or has double spaces', () {
      for (var i = 0; i < 20000; i++) {
        final w = TeluguNormalizer.cardinal(i);
        expect(w.isNotEmpty && !w.contains('  ') && w == w.trim(), true, reason: '$i -> "$w"');
      }
    });
  });

  group('digits in text (model port)', () {
    test('joins to Telugu letters, grouping, leading zeros', () {
      expect(n.normalize('140ఏళ్ల'), 'నూట నలభైఏళ్ల');
      expect(n.normalize('ఇది 140 ఏళ్ల చరిత్ర'), 'ఇది నూట నలభై ఏళ్ల చరిత్ర');
      expect(n.normalize('1,30,650'), TeluguNormalizer.cardinal(130650));
      expect(n.normalize('1,234'), TeluguNormalizer.cardinal(1234));
      expect(n.normalize('007'), 'సున్నా సున్నా ఏడు');
      expect(n.normalize('1234567890'), 'ఒకటి రెండు మూడు నాలుగు ఐదు ఆరు ఏడు ఎనిమిది తొమ్మిది సున్నా');
    });
    test('Telugu digits read like ASCII', () {
      expect(n.normalize('౧౫'), 'పదిహేను');
    });
  });

  group('cleaning (model port)', () {
    test('whitespace, zero-width, repeated vowel sign, composition', () {
      expect(n.normalize('ఎందరో  మహానుభావులు\n\tఅందరికీ'), 'ఎందరో మహానుభావులు అందరికీ');
      expect(n.normalize('కా​ల‍ం'), 'కాలం');
      expect(n.normalize('కిి'), 'కి');
      expect(n.normalize('వాడై'), 'వాడై');
    });
    test('non-speech tags and Latin glosses are dropped', () {
      expect(n.normalize('హలో [noise] ప్రపంచం'), 'హలో ప్రపంచం');
      expect(n.normalize('స్మార్ట్ఫోన్ (smart phone) వాడకం'), 'స్మార్ట్ఫోన్ వాడకం');
    });
  });

  group('extensions (AI proposals)', () {
    test('percent', () {
      expect(n.normalize('15%'), 'పదిహేను శాతం');
      expect(n.normalize('15 శాతం'), 'పదిహేను శాతం');
      expect(n.normalize('2.5%'), 'రెండు పాయింట్ ఐదు శాతం');
    });
    test('rupees', () {
      expect(n.normalize('₹500'), 'ఐదు వందలు రూపాయలు');
      expect(n.normalize('రూ. 10 వేలు'), 'పది వేలు రూపాయలు');
      expect(n.normalize('₹1,30,650'), '${TeluguNormalizer.cardinal(130650)} రూపాయలు');
      expect(n.normalize('రూ.40 వేల కోట్లు'), 'నలభై వేల కోట్లు రూపాయలు');
    });
    test('dates', () {
      expect(n.normalize('12-11-2026'), 'నవంబరు పన్నెండు, రెండు వేల ఇరవై ఆరు');
      expect(n.normalize('1/3/2025'), 'మార్చి ఒకటి, రెండు వేల ఇరవై ఐదు');
      expect(n.normalize('31.12.1999'), 'డిసెంబరు ముప్పై ఒకటి, వెయ్యి తొమ్మిది వందల తొంభై తొమ్మిది');
      // not a date: month 13
      expect(n.normalize('5-13-2026'), isNot(contains('డిసెంబరు')));
    });
    test('times', () {
      expect(n.normalize('5:00'), 'ఐదు గంటలు');
      expect(n.normalize('10:30'), 'పది గంటల ముప్పై నిమిషాలు');
    });
    test('decimals', () {
      expect(n.normalize('3.5'), 'మూడు పాయింట్ ఐదు');
      expect(n.normalize('0.25'), 'సున్నా పాయింట్ రెండు ఐదు');
    });
    test('ordinals', () {
      expect(n.normalize('1వ'), 'మొదటి');
      expect(n.normalize('12వ తేదీ'), 'పన్నెండవ తేదీ');
      expect(n.normalize('20వ'), 'ఇరవయ్యవ');
    });
    test('units and acronyms', () {
      expect(n.normalize('5km'), 'ఐదు కిలోమీటర్లు');
      expect(n.normalize('10 kg'), 'పది కిలోలు');
      expect(n.normalize('BJP'), 'బి జె పి');
      expect(n.normalize('ISRO'), 'ఐ ఎస్ ఆర్ ఓ');
    });
    test('a full news-style sentence', () {
      expect(
        n.normalize('దేశ జనాభాలో 15% మంది, 12-11-2026న ₹500 చెల్లించారు.'),
        'దేశ జనాభాలో పదిహేను శాతం మంది, నవంబరు పన్నెండు, రెండు వేల ఇరవై ఆరున ఐదు వందలు రూపాయలు చెల్లించారు.',
      );
    });
  });

  test('matches the model\'s own normaliser when a reference dump is present', () {
    // Dump made by the owner with scripts/tts_reference/ref_numbers.py; absent in CI, so the test then does nothing.
    final f = File(Platform.environment['TTS_REF_JSON'] ?? '');
    if (f.path.isEmpty || !f.existsSync()) return;
    final ref = (jsonDecode(f.readAsStringSync()) as Map).cast<String, String>();
    final diffs = <String>[];
    ref.forEach((k, v) {
      final got = n.normalize(k);
      if (got != v) diffs.add('"$k": model="$v" ours="$got"');
    });
    expect(diffs, isEmpty, reason: diffs.take(20).join('\n'));
  });
}
