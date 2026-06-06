/**
 * TTS Comparison Test Cases — GatiVani
 *
 * These 5 cases cover the exact failure modes that matter for Telugu newspaper audio:
 *   1. Simple prose       — baseline naturalness
 *   2. Code-switching     — Telugu + English mixed in real headlines
 *   3. Numerals & dates   — extremely common in news; all three providers handle differently
 *   4. Long paragraph     — triggers Sarvam's 500-char chunking; tests join seam audibility
 *   5. Named entities     — political names, city names, proper nouns mispronounced by global models
 */

export interface TestCase {
  id: string;
  label: string;
  text: string;
  /** What to listen for when reviewing the audio output */
  reviewNotes: string;
}

export const TEST_CASES: TestCase[] = [
  {
    id: "01_simple_prose",
    label: "Simple Telugu prose",
    text: "ఈ రోజు వాతావరణం చాలా అనుకూలంగా ఉంది. రైతులు పంట పండించడానికి సిద్ధంగా ఉన్నారు.",
    reviewNotes: "Check: natural intonation, sentence breaks, no robotic pauses mid-word.",
  },
  {
    id: "02_code_switching",
    label: "Telugu + English code-switching",
    text: "ప్రభుత్వం Budget లో infrastructure కోసం రూ.50,000 కోట్లు కేటాయించింది. Finance Minister గారు press conference లో ఈ విషయం వెల్లడించారు.",
    reviewNotes: "Check: 'Budget', 'infrastructure', 'Finance Minister', 'press conference' — English words should sound natural inside Telugu flow, not jarring.",
  },
  {
    id: "03_numerals_dates",
    label: "Numbers, dates, percentages",
    text: "జనవరి 15, 2026 నాటికి రాష్ట్రంలో 3,47,892 మంది నిరుద్యోగులు ఉన్నారు. GDP వృద్ధి రేటు 7.4% కి చేరుకుంది.",
    reviewNotes: "Check: '3,47,892' reads as 'మూడు లక్షల నలభై ఏడు వేల ఎనిమిది వందల తొంభై రెండు', '7.4%' reads naturally, date format is correct.",
  },
  {
    id: "04_long_paragraph",
    label: "Long paragraph (triggers Sarvam 500-char chunking)",
    text: "హైదరాబాద్ లో జరిగిన అంతర్జాతీయ వాణిజ్య సదస్సులో ముఖ్యమంత్రి పాల్గొన్నారు. ఈ సదస్సులో దేశవిదేశాల నుండి 500 కంపెనీలు పాల్గొన్నాయి. రాష్ట్రానికి రూ.75,000 కోట్ల పెట్టుబడులు వస్తాయని అంచనా వేశారు. సాంకేతిక రంగంలో 50,000 ఉద్యోగాలు కల్పించే అవకాశం ఉందని నిపుణులు అభిప్రాయపడ్డారు. ముఖ్యమంత్రి మాట్లాడుతూ తెలంగాణ రాష్ట్రం పెట్టుబడులకు అత్యంత అనుకూలమైన వాతావరణాన్ని కల్పిస్తుందని అన్నారు. రానున్న రెండు సంవత్సరాలలో మరిన్ని మౌలిక సదుపాయాలు ఏర్పాటు చేయబడతాయని హామీ ఇచ్చారు.",
    reviewNotes: "This is 596 chars — forces Sarvam to split into 2 chunks. Listen at the split point (~450 chars) for an audible seam, pause, or tonal shift. Gemini providers handle this in one call.",
  },
  {
    id: "05_named_entities",
    label: "Named entities — people, places, parties",
    text: "తెలంగాణ రాష్ట్ర సమితి అధ్యక్షుడు కె. చంద్రశేఖర్ రావు హైదరాబాద్ లో జరిగిన బహిరంగ సభలో మాట్లాడారు. భారతీయ జనతా పార్టీ మరియు కాంగ్రెస్ నాయకులు ఆయన వ్యాఖ్యలను వ్యతిరేకించారు.",
    reviewNotes: "Check: 'కె. చంద్రశేఖర్ రావు' (KCR) pronounced correctly, 'హైదరాబాద్' not mangled, 'భారతీయ జనతా పార్టీ' (BJP) natural, 'కాంగ్రెస్' correctly stressed.",
  },
];
