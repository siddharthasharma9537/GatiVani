/// Lightweight i18n. UI chrome is English by default; flip to Telugu via the
/// language setting. Article content is always Telugu (it's a Telugu paper) —
/// only the chrome translates. Use `tr(lang, key)` and `sectionLabel(s, lang)`.

const Map<String, Map<String, String>> _kStrings = {
  'en': {
    'listen': 'Listen',
    'listen_briefing': 'Listen to briefing',
    'upload': 'Upload',
    'recently_played': 'Recently played',
    'browse_by_section': 'Browse by section',
    'all_articles': 'All articles',
    'all': 'All',
    'play': 'Play',
    'play_all': 'Play all',
    'sections': 'Sections',
    'pages': 'Pages',
    'page': 'Page',
    'todays_edition': "Today's edition",
    'articles': 'articles',
    'story_one': 'story',
    'story_many': 'stories',
    'language': 'Language',
    'menu': 'Menu',
    'settings': 'Settings',
    'account': 'Account',
    'guest': 'Guest',
    'guest_sub': 'Not signed in',
    'sign_in': 'Sign in',
    'sign_up': 'Create account',
    'log_out': 'Log out',
    'theme': 'Theme',
    'theme_system': 'System',
    'theme_light': 'Light',
    'theme_dark': 'Dark',
    'playback': 'Playback',
    'speed': 'Speed',
    'voice': 'Voice',
    'downloads': 'Downloads',
    'about': 'About',
    'about_tagline': 'Newspaper audio companion for your commute',
    'english': 'English',
    'telugu': 'తెలుగు',
    'email': 'Email',
    'password': 'Password',
    'name': 'Name',
    'have_account': 'Already have an account?',
    'no_account': "Don't have an account?",
    'continue_guest': 'Continue as guest',
    'auth_note': 'Demo — accounts are not yet connected to a server.',
    'lang_label': 'తె',
  },
  'te': {
    'listen': 'వినండి',
    'listen_briefing': 'సంక్షిప్తం వినండి',
    'upload': 'అప్‌లోడ్',
    'recently_played': 'ఇటీవల విన్నవి',
    'browse_by_section': 'విభాగాల వారీగా',
    'all_articles': 'అన్ని వార్తలు',
    'all': 'అన్నీ',
    'play': 'ప్లే',
    'play_all': 'అన్నీ ప్లే',
    'sections': 'విభాగాలు',
    'pages': 'పేజీలు',
    'page': 'పేజీ',
    'todays_edition': 'నేటి సంచిక',
    'articles': 'వార్తలు',
    'story_one': 'కథనం',
    'story_many': 'కథనాలు',
    'language': 'భాష',
    'menu': 'మెను',
    'settings': 'సెట్టింగ్‌లు',
    'account': 'ఖాతా',
    'guest': 'అతిథి',
    'guest_sub': 'సైన్ ఇన్ కాలేదు',
    'sign_in': 'సైన్ ఇన్',
    'sign_up': 'ఖాతా సృష్టించండి',
    'log_out': 'లాగ్ అవుట్',
    'theme': 'థీమ్',
    'theme_system': 'సిస్టమ్',
    'theme_light': 'లైట్',
    'theme_dark': 'డార్క్',
    'playback': 'ప్లేబ్యాక్',
    'speed': 'వేగం',
    'voice': 'వాయిస్',
    'downloads': 'డౌన్‌లోడ్‌లు',
    'about': 'గురించి',
    'about_tagline': 'మీ ప్రయాణానికి వార్తాపత్రిక ఆడియో సహచరి',
    'english': 'English',
    'telugu': 'తెలుగు',
    'email': 'ఇమెయిల్',
    'password': 'పాస్‌వర్డ్',
    'name': 'పేరు',
    'have_account': 'ఇప్పటికే ఖాతా ఉందా?',
    'no_account': 'ఖాతా లేదా?',
    'continue_guest': 'అతిథిగా కొనసాగండి',
    'auth_note': 'డెమో — ఖాతాలు ఇంకా సర్వర్‌కు అనుసంధానించబడలేదు.',
    'lang_label': 'EN',
  },
};

String tr(String lang, String key) =>
    _kStrings[lang]?[key] ?? _kStrings['en']?[key] ?? key;

/// "5 stories" / "5 కథనాలు" / "1 story".
String storyCount(int n, String lang) {
  final word = tr(lang, n == 1 ? 'story_one' : 'story_many');
  return '$n $word';
}

// ── Section names ──────────────────────────────────────────────────────────
// Category values stay English everywhere (filtering, storage); only the
// displayed label translates.
const Map<String, String> _kSectionTe = {
  'State': 'రాష్ట్రం',
  'National': 'జాతీయం',
  'International': 'అంతర్జాతీయం',
  'District': 'జిల్లా',
  'Politics': 'రాజకీయాలు',
  'Editorial': 'సంపాదకీయం',
  'Judiciary': 'న్యాయవ్యవస్థ',
  'Crime': 'నేరాలు',
  'Business': 'వాణిజ్యం',
  'Sports': 'క్రీడలు',
  'Health': 'ఆరోగ్యం',
  'Sci-Tech': 'సైన్స్-టెక్',
  'Education': 'విద్య',
  'Agriculture': 'వ్యవసాయం',
  'Entertainment': 'వినోదం',
  'Devotional': 'భక్తి',
  'Trending': 'ట్రెండింగ్',
  'News': 'వార్తలు',
};

String sectionLabel(String section, String lang) =>
    lang == 'te' ? (_kSectionTe[section] ?? section) : section;

// ── Date formatting ────────────────────────────────────────────────────────
const _kMonthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _kMonthsTe = [
  'జనవరి', 'ఫిబ్రవరి', 'మార్చి', 'ఏప్రిల్', 'మే', 'జూన్',
  'జులై', 'ఆగస్టు', 'సెప్టెంబర్', 'అక్టోబర్', 'నవంబర్', 'డిసెంబర్',
];
// DateTime.weekday: Mon=1..Sun=7.
const _kWeekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _kWeekdaysTe = ['సోమ', 'మంగళ', 'బుధ', 'గురు', 'శుక్ర', 'శని', 'ఆది'];

/// "12 May 2025" / "12 మే 2025".
String formatEditionDate(DateTime d, String lang) {
  final months = lang == 'te' ? _kMonthsTe : _kMonthsEn;
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// "Mon" / "సోమ".
String weekdayShort(DateTime d, String lang) =>
    (lang == 'te' ? _kWeekdaysTe : _kWeekdaysEn)[d.weekday - 1];
