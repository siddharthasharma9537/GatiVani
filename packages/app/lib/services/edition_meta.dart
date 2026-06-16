/// Parses the structured newspaper metadata hiding inside an edition's
/// filename-derived title, e.g. "Eenadu TS 12 05 2025 removed" →
/// publication "Eenadu/ఈనాడు", edition "Telangana/తెలంగాణ", date 12 May 2025.
/// Everything is best-effort with graceful fallbacks: if nothing parses, the
/// caller still gets a junk-stripped [cleanTitle].
class EditionMeta {
  const EditionMeta({
    this.publicationEn,
    this.publicationTe,
    this.editionEn,
    this.editionTe,
    this.date,
    required this.cleanTitle,
  });

  final String? publicationEn;
  final String? publicationTe;
  final String? editionEn;
  final String? editionTe;
  final DateTime? date;

  /// Junk-stripped, title-cased fallback when no publication is recognized.
  final String cleanTitle;

  bool get hasMasthead => publicationEn != null;

  String publication(String lang) =>
      (lang == 'te' ? publicationTe : publicationEn) ?? publicationEn ?? '';
  String? edition(String lang) => lang == 'te' ? editionTe : editionEn;

  // Known Telugu/regional mastheads. Key is a lowercase needle in the title.
  static const Map<String, List<String>> _publications = {
    'eenadu': ['Eenadu', 'ఈనాడు'],
    'sakshi': ['Sakshi', 'సాక్షి'],
    'andhrajyothy': ['Andhra Jyothy', 'ఆంధ్రజ్యోతి'],
    'jyothy': ['Andhra Jyothy', 'ఆంధ్రజ్యోతి'],
    'namasthe': ['Namasthe Telangana', 'నమస్తే తెలంగాణ'],
    'namaste': ['Namasthe Telangana', 'నమస్తే తెలంగాణ'],
    'andhraprabha': ['Andhra Prabha', 'ఆంధ్రప్రభ'],
    'prajashakti': ['Prajasakti', 'ప్రజాశక్తి'],
    'vaartha': ['Vaartha', 'వార్త'],
    'mana telangana': ['Mana Telangana', 'మన తెలంగాణ'],
    'velugu': ['V6 Velugu', 'వెలుగు'],
  };

  // Edition codes / regions. Key is a lowercase token.
  static const Map<String, List<String>> _editions = {
    'ts': ['Telangana', 'తెలంగాణ'],
    'tg': ['Telangana', 'తెలంగాణ'],
    'telangana': ['Telangana', 'తెలంగాణ'],
    'ap': ['Andhra Pradesh', 'ఆంధ్రప్రదేశ్'],
    'andhra': ['Andhra Pradesh', 'ఆంధ్రప్రదేశ్'],
    'hyderabad': ['Hyderabad', 'హైదరాబాద్'],
    'hyd': ['Hyderabad', 'హైదరాబాద్'],
    'warangal': ['Warangal', 'వరంగల్'],
    'vijayawada': ['Vijayawada', 'విజయవాడ'],
    'visakha': ['Visakhapatnam', 'విశాఖపట్నం'],
    'vizag': ['Visakhapatnam', 'విశాఖపట్నం'],
    'guntur': ['Guntur', 'గుంటూరు'],
    'karimnagar': ['Karimnagar', 'కరీంనగర్'],
    'nizamabad': ['Nizamabad', 'నిజామాబాద్'],
  };

  // Tokens that are never part of a real title.
  static const Set<String> _junk = {
    'removed', 'final', 'copy', 'watermark', 'scan', 'scanned', 'page', 'pages',
    'layout', 'edition', 'ed', 'compressed', 'pdf', 'jpg', 'jpeg', 'png',
    'new', 'draft', 'test', 'sample', 'merged', 'full',
  };

  static EditionMeta parse(String rawTitle) {
    final title = rawTitle.trim();
    final lower = title.toLowerCase();

    // Publication: first known masthead whose needle appears.
    String? pubEn, pubTe;
    for (final e in _publications.entries) {
      if (lower.contains(e.key)) {
        pubEn = e.value[0];
        pubTe = e.value[1];
        break;
      }
    }

    final date = _parseDate(title);

    // Tokenize on whitespace and common separators for edition + cleanup.
    final tokens = title.split(RegExp(r'[\s_\-./]+')).where((t) => t.isNotEmpty);

    // Edition: first token that matches an edition code/region.
    String? edEn, edTe;
    for (final t in tokens) {
      final m = _editions[t.toLowerCase()];
      if (m != null) {
        edEn = m[0];
        edTe = m[1];
        break;
      }
    }

    // Clean title: drop junk, publication needle words, edition tokens and any
    // pure-number tokens (dates, page indices). Title-case what remains.
    final keep = <String>[];
    for (final t in tokens) {
      final tl = t.toLowerCase();
      if (_junk.contains(tl)) continue;
      if (_editions.containsKey(tl)) continue;
      if (pubEn != null && _publications.containsKey(tl)) continue;
      if (RegExp(r'^\d+$').hasMatch(t)) continue;
      keep.add(t);
    }
    final clean = keep
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ')
        .trim();

    return EditionMeta(
      publicationEn: pubEn,
      publicationTe: pubTe,
      editionEn: edEn,
      editionTe: edTe,
      date: date,
      cleanTitle: clean.isEmpty ? title : clean,
    );
  }

  static DateTime? _parseDate(String s) {
    // YYYYMMDD, e.g. 20250512
    final ymd = RegExp(r'\b(20\d{2})(\d{2})(\d{2})\b').firstMatch(s);
    if (ymd != null) {
      final d = _build(int.parse(ymd[3]!), int.parse(ymd[2]!), int.parse(ymd[1]!));
      if (d != null) return d;
    }
    // DD MM YYYY with separators, e.g. 12 05 2025 / 12-05-2025 / 12.05.2025
    final dmy =
        RegExp(r'\b(\d{1,2})[\s_\-./](\d{1,2})[\s_\-./](20\d{2})\b').firstMatch(s);
    if (dmy != null) {
      final d = _build(int.parse(dmy[1]!), int.parse(dmy[2]!), int.parse(dmy[3]!));
      if (d != null) return d;
    }
    return null;
  }

  static DateTime? _build(int day, int month, int year) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final d = DateTime(year, month, day);
    // Reject overflow (e.g. day 31 in a 30-day month rolled forward).
    if (d.month != month || d.day != day) return null;
    return d;
  }
}
