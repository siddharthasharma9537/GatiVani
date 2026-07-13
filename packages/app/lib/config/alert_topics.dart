/// The alert-topic catalog: things people wait on agencies for — exam
/// results, admit cards, govt job notifications. Ids are the contract with
/// the feeds-alerts edge function (its TOPICS map mirrors this list); labels
/// are what the chips show.
class AlertTopic {
  const AlertTopic(this.id, this.en, this.te, this.group);

  final String id;
  final String en;
  final String te;
  final String group; // 'exams' | 'jobs'
}

const List<AlertTopic> kAlertTopics = [
  // ── Exams & results ────────────────────────────────────────────────────────
  AlertTopic('jee', 'JEE Main / Advanced', 'జేఈఈ మెయిన్ / అడ్వాన్స్‌డ్', 'exams'),
  AlertTopic('neet', 'NEET', 'నీట్', 'exams'),
  AlertTopic('eapcet', 'EAPCET / EAMCET', 'ఈఏపీసెట్ / ఎంసెట్', 'exams'),
  AlertTopic('cat', 'CAT / MBA entrance', 'క్యాట్ / ఎంబీఏ ఎంట్రన్స్', 'exams'),
  AlertTopic('gate', 'GATE', 'గేట్', 'exams'),
  AlertTopic('boards', 'SSC / Inter / CBSE boards',
      'పదో తరగతి / ఇంటర్ / సీబీఎస్ఈ', 'exams'),
  // ── Government jobs ────────────────────────────────────────────────────────
  AlertTopic('upsc', 'UPSC Civil Services', 'యూపీఎస్సీ సివిల్స్', 'jobs'),
  AlertTopic('tspsc', 'TSPSC (Telangana)', 'టీఎస్పీఎస్సీ (తెలంగాణ)', 'jobs'),
  AlertTopic('appsc', 'APPSC (Andhra Pradesh)', 'ఏపీపీఎస్సీ (ఆంధ్రప్రదేశ్)',
      'jobs'),
  AlertTopic('ssc_jobs', 'SSC (Staff Selection)', 'ఎస్ఎస్సీ ఉద్యోగాలు', 'jobs'),
  AlertTopic('railways', 'Railways (RRB)', 'రైల్వే (ఆర్ఆర్బీ)', 'jobs'),
  AlertTopic('banking', 'Banking (IBPS / SBI)', 'బ్యాంకింగ్ (ఐబీపీఎస్/ఎస్బీఐ)',
      'jobs'),
  AlertTopic('dsc', 'Teacher posts (DSC / TET)', 'డీఎస్సీ / టెట్', 'jobs'),
];

AlertTopic? alertTopicById(String id) {
  for (final t in kAlertTopics) {
    if (t.id == id) return t;
  }
  return null;
}
