const paperSectionIds = [
  'front',
  'editorial',
  'business',
  'cinema',
  'sports',
  'vasundhara',
  'pratibha',
  'chaduvu',
  'regional',
  'national',
  'back',
  'general',
];
const paperSectionTitles = [
  'Front page',
  'Editorial news',
  'Business',
  'Cinema',
  'Champion (sports)',
  'Vasundhara',
  'Pratibha',
  'Chaduvu',
  'Regional',
  'National',
  'Back page',
  'General news',
];

class PaperDay {
  const PaperDay(this.edition, this.date, this.title);
  final String edition, date, title;
  factory PaperDay.fromJson(Map<String, dynamic> json) => PaperDay(
        json['edition'] as String,
        json['source_date'] as String,
        (json['paper_editions'] as Map?)?['title'] as String? ??
            json['edition'] as String,
      );
  Map<String, dynamic> toJson() => {
        'edition': edition,
        'source_date': date,
        'paper_editions': {'title': title},
      };
}

class PaperItem {
  const PaperItem(this.role, this.text);
  final String role, text;
  factory PaperItem.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String;
    if (!const [
      'headline',
      'kicker',
      'deck',
      'byline',
      'subheading',
      'body',
      'caption',
      'side'
    ].contains(role)) {
      throw const FormatException('Unknown paper item role');
    }
    return PaperItem(role, json['text'] as String);
  }
  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

class PaperStory {
  PaperStory.fromJson(Map<String, dynamic> json)
      : id = json['source_id'] as String,
        edition = json['edition'] as String,
        date = json['source_date'] as String,
        section = json['section'] as String,
        order = (json['sort_order'] as num).toInt(),
        headline = json['headline'] as String,
        graphic = json['headline_is_graphic'] == true,
        imageUrl = _httpsUrl(json['headline_image_url'] as String?),
        byline = json['byline'] as String? ?? '',
        displayText = json['display_text'] as String,
        narration = json['narration_text'] as String,
        words = (json['word_count'] as num).toInt(),
        pages = (json['page_numbers'] as List)
            .cast<num>()
            .map((n) => n.toInt())
            .toList(),
        continuation =
            (json['continuation_info'] as List).cast<Map<String, dynamic>>(),
        items = (json['items'] as List)
            .map((i) => PaperItem.fromJson(Map<String, dynamic>.from(i as Map)))
            .toList() {
    if (!paperSectionIds.contains(section) || pages.isEmpty) {
      throw const FormatException('Invalid story section/pages');
    }
  }
  final String id,
      edition,
      date,
      section,
      headline,
      byline,
      displayText,
      narration;
  final String? imageUrl;
  final bool graphic;
  final int order, words;
  final List<int> pages;
  final List<PaperItem> items;
  final List<Map<String, dynamic>> continuation;
  static String? _httpsUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? value
        : null;
  }

  Map<String, dynamic> toJson() => {
        'source_id': id,
        'edition': edition,
        'source_date': date,
        'section': section,
        'sort_order': order,
        'headline': headline,
        'headline_is_graphic': graphic,
        'headline_image_url': imageUrl,
        'byline': byline,
        'display_text': displayText,
        'narration_text': narration,
        'word_count': words,
        'page_numbers': pages,
        'continuation_info': continuation,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

class PaperView {
  const PaperView(this.days, this.day, this.stories, this.section);
  final List<PaperDay> days;
  final PaperDay day;
  final List<PaperStory> stories;
  final String? section;
  factory PaperView.fromJson(Map<String, dynamic> json) => PaperView(
        (json['days'] as List)
            .map((d) => PaperDay.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList(),
        PaperDay.fromJson(Map<String, dynamic>.from(json['day'] as Map)),
        (json['stories'] as List)
            .map(
                (s) => PaperStory.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
        json['section'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'days': days.map((d) => d.toJson()).toList(),
        'day': day.toJson(),
        'stories': stories.map((s) => s.toJson()).toList(),
        'section': section,
      };
}
