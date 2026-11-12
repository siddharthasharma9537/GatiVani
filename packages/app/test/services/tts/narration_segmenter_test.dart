import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/tts/narration_segmenter.dart';

// Neutral Telugu test sentences written for this file (no newspaper content).
void main() {
  const seg = NarrationSegmenter();

  test('splits at danda, question and exclamation marks', () {
    expect(seg.split('ఈ రోజు వర్షం కురిసింది। రేపు ఎండ ఉంటుందా? తప్పకుండా వస్తాను!'),
        ['ఈ రోజు వర్షం కురిసింది।', 'రేపు ఎండ ఉంటుందా?', 'తప్పకుండా వస్తాను!']);
  });

  test('splits at a full stop followed by a space, not inside numbers or dates', () {
    expect(seg.split('ధర 3.5 రూపాయలు పెరిగింది. తేదీ 12.11.2026 నాడు ప్రకటించారు.'),
        ['ధర 3.5 రూపాయలు పెరిగింది.', 'తేదీ 12.11.2026 నాడు ప్రకటించారు.']);
  });

  test('abbreviations and initials do not end a sentence', () {
    expect(seg.split('డా. రావు గారు రూ. 500 చెల్లించారు. అది అందరికీ తెలుసు.'),
        ['డా. రావు గారు రూ. 500 చెల్లించారు.', 'అది అందరికీ తెలుసు.']);
    expect(seg.split('ఎ. కె. అని ఆయన పేరు రాసుకున్నారు. సరే.'.replaceAll('ఎ. కె.', 'A. K.')),
        ['A. K. అని ఆయన పేరు రాసుకున్నారు.', 'సరే.']);
  });

  test('a headline on its own line is its own sentence; blank lines are boundaries', () {
    expect(seg.split('వర్షాలు మళ్లీ వచ్చాయి\n\nనిన్న రాత్రి నుంచి ఎడతెరిపి లేకుండా కురుస్తున్నాయి'),
        ['వర్షాలు మళ్లీ వచ్చాయి', 'నిన్న రాత్రి నుంచి ఎడతెరిపి లేకుండా కురుస్తున్నాయి']);
  });

  test('very short fragments are joined to the next sentence', () {
    expect(seg.split('సరే: ఈ రోజు పని పూర్తయింది అందరికీ ధన్యవాదాలు.'), ['సరే: ఈ రోజు పని పూర్తయింది అందరికీ ధన్యవాదాలు.']);
  });

  test('a long sentence is cut at a comma, each piece within the limit', () {
    final long = '${List.generate(30, (i) => 'ఇది పదం సంఖ్య ${i + 1}').join(', ')}.';
    final parts = seg.split(long);
    expect(parts.length, greaterThan(1));
    expect(parts.every((p) => p.length <= 220), true);
    expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '), long);
  });

  test('empty and punctuation-only input give nothing', () {
    expect(seg.split(''), isEmpty);
    expect(seg.split('  \n\n ... '), isEmpty);
  });

  test('keeps the text intact (joined) for a continuous story', () {
    const story = 'మొదటి వాక్యం ఇక్కడ ఉంది. రెండో వాక్యం ఇక్కడ ఉంది. మూడో వాక్యం ఇక్కడ ఉంది.';
    expect(seg.split(story).join(' '), story);
  });
}
