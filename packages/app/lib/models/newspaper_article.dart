enum ArticleAudioStatus { none, loading, ready, failed }

class NewspaperArticle {
  final String id;
  final String title;
  final String content;
  final String preview;
  final String category;
  final int estimatedDurationSeconds;
  final int page;

  /// Content language ('te' | 'hi') — drives the TTS voice/locale used when
  /// this article is narrated. Defaults to 'te' since editions/most existing
  /// content are Telugu; Live articles fetched under a Hindi News Language
  /// selection carry 'hi' through from WebArticle.
  final String language;

  /// Type detected by Gemini: "newspaper" | "sloka" | "mantra" | "book" | "other"
  final String documentType;

  /// TTS reading style: "news_anchor" | "devotional_slow" | "mantra_clear" | "normal"
  final String readingStyle;

  /// Voice model suggested by the backend for this document type.
  /// e.g. "priya" for news, "kavitha" for slokas, "shubh" for mantras.
  /// Empty string means fall back to the user's selected voice.
  final String suggestedSpeaker;

  /// URL of the source document image (used as album art / thumbnail).
  /// For image uploads this is the actual photo; for PDFs it is empty.
  final String imageUrl;

  String? audioUrl;
  // Cached audio of the short "briefing" narration (headline + lede), separate
  // from the full-article audioUrl.
  String? summaryAudioUrl;
  // A real (AI) abstractive summary, when generated via long-press → Summarize.
  // When set, brief playback narrates + highlights this instead of the lede.
  String? summaryText;
  ArticleAudioStatus audioStatus;
  bool isDownloaded;
  bool isSelected;

  NewspaperArticle({
    required this.id,
    required this.title,
    required this.content,
    required this.preview,
    required this.category,
    required this.estimatedDurationSeconds,
    this.page = 1,
    this.language = 'te',
    this.documentType = 'newspaper',
    this.readingStyle = 'news_anchor',
    this.suggestedSpeaker = '',
    this.imageUrl = '',
    this.audioUrl,
    this.summaryAudioUrl,
    this.summaryText,
    this.audioStatus = ArticleAudioStatus.none,
    this.isDownloaded = false,
    this.isSelected = false,
  });

  /// Telugu TTS: ~700 chars/min
  static int estimateDuration(String text) =>
      ((text.length / 700) * 60).round().clamp(15, 3600);

  String get estimatedDurationFormatted {
    final m = estimatedDurationSeconds ~/ 60;
    final s = estimatedDurationSeconds % 60;
    if (m == 0) return '${s}s';
    if (s == 0) return '${m} min';
    return '${m}m ${s}s';
  }

  /// The text that gets narrated AND highlighted: headline first (as its own
  /// sentence so TTS pauses), then the body. Used by both TTS and the lyrics
  /// view so audio and word-sync stay aligned.
  String get spokenText {
    final t = title.trim();
    final b = (content.trim().isNotEmpty ? content : preview).trim();
    if (t.isEmpty) return b;
    final sep = RegExp(r'[.?!।॥…]$').hasMatch(t) ? '\n\n' : '.\n\n';
    return '$t$sep$b';
  }

  /// Short "briefing" narration: headline + the lede (the first whole sentences
  /// of the body, snapped to a sentence boundary, ~250 chars). A news lede
  /// summarizes by convention, so this is a faithful gist — and ~3–4× fewer
  /// characters than the full body, so ~3–4× cheaper to synthesize.
  String get briefingText {
    final t = title.trim();
    final b = (content.trim().isNotEmpty ? content : preview).trim();
    String lede;
    if (b.length <= 300) {
      lede = b;
    } else {
      final sentences = b.split(RegExp(r'(?<=[.?!।॥…])\s+'));
      final buf = StringBuffer();
      for (final s in sentences) {
        if (buf.isNotEmpty && buf.length + s.length > 250) break;
        buf.write(buf.isEmpty ? s : ' $s');
      }
      lede = buf.isEmpty ? b.substring(0, 250) : buf.toString();
    }
    if (t.isEmpty) return lede;
    final sep = RegExp(r'[.?!।॥…]$').hasMatch(t) ? '\n\n' : '.\n\n';
    return '$t$sep$lede';
  }

  /// Returns true if imageUrl points to a displayable image (not a PDF).
  bool get hasImage {
    if (imageUrl.isEmpty) return false;
    final lower = imageUrl.toLowerCase();
    return lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('.gif');
  }

  factory NewspaperArticle.fromJson(
    Map<String, dynamic> json, {
    String imageUrl = '',
  }) {
    final content = json['content'] as String? ?? '';
    return NewspaperArticle(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: content,
      preview: json['preview'] as String? ??
          content.replaceAll('\n', ' ').trim().substring(
                0,
                content.length.clamp(0, 200),
              ),
      category: json['category'] as String? ?? 'News',
      estimatedDurationSeconds:
          json['estimatedDurationSeconds'] as int? ?? estimateDuration(content),
      page: json['page'] as int? ?? 1,
      language: json['language'] as String? ?? 'te',
      documentType: json['documentType'] as String? ?? 'newspaper',
      readingStyle: json['readingStyle'] as String? ?? 'news_anchor',
      suggestedSpeaker: json['suggestedSpeaker'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? imageUrl,
      audioUrl: json['audioUrl'] as String?,
      summaryAudioUrl: json['summaryAudioUrl'] as String?,
    );
  }

  NewspaperArticle copyWith({
    ArticleAudioStatus? audioStatus,
    String? audioUrl,
    String? summaryAudioUrl,
    bool? isDownloaded,
    bool? isSelected,
    String? documentType,
    String? readingStyle,
    String? suggestedSpeaker,
    String? imageUrl,
  }) =>
      NewspaperArticle(
        id: id,
        title: title,
        content: content,
        preview: preview,
        category: category,
        estimatedDurationSeconds: estimatedDurationSeconds,
        page: page,
        documentType: documentType ?? this.documentType,
        readingStyle: readingStyle ?? this.readingStyle,
        suggestedSpeaker: suggestedSpeaker ?? this.suggestedSpeaker,
        imageUrl: imageUrl ?? this.imageUrl,
        audioUrl: audioUrl ?? this.audioUrl,
        summaryAudioUrl: summaryAudioUrl ?? this.summaryAudioUrl,
        audioStatus: audioStatus ?? this.audioStatus,
        isDownloaded: isDownloaded ?? this.isDownloaded,
        isSelected: isSelected ?? this.isSelected,
      );
}

class NewspaperResult {
  final String id;
  final String title;
  final String date;
  final String storageUrl;
  final List<NewspaperArticle> articles;
  final String tier;
  final bool truncated;
  final int totalPages;
  final int processedPages;

  NewspaperResult({
    required this.id,
    required this.title,
    required this.date,
    required this.storageUrl,
    required this.articles,
    required this.tier,
    this.truncated = false,
    this.totalPages = 1,
    this.processedPages = 1,
  });

  List<String> get categories {
    final cats = articles.map((a) => a.category).toSet().toList()..sort();
    return ['All', ...cats];
  }

  List<NewspaperArticle> articlesForCategory(String category) =>
      category == 'All' ? articles : articles.where((a) => a.category == category).toList();
}
