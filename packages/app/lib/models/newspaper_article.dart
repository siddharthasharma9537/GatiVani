enum ArticleAudioStatus { none, loading, ready, failed }

class NewspaperArticle {
  final String id;
  final String title;
  final String content;
  final String preview;
  final String category;
  final int estimatedDurationSeconds;
  final int page;

  /// Type detected by Gemini: "newspaper" | "sloka" | "mantra" | "book" | "other"
  final String documentType;

  /// TTS reading style: "news_anchor" | "devotional_slow" | "mantra_clear" | "normal"
  final String readingStyle;

  /// URL of the source document image (used as album art / thumbnail).
  /// For image uploads this is the actual photo; for PDFs it is empty.
  final String imageUrl;

  String? audioUrl;
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
    this.documentType = 'newspaper',
    this.readingStyle = 'news_anchor',
    this.imageUrl = '',
    this.audioUrl,
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
      documentType: json['documentType'] as String? ?? 'newspaper',
      readingStyle: json['readingStyle'] as String? ?? 'news_anchor',
      imageUrl: json['imageUrl'] as String? ?? imageUrl,
      audioUrl: json['audioUrl'] as String?,
    );
  }

  NewspaperArticle copyWith({
    ArticleAudioStatus? audioStatus,
    String? audioUrl,
    bool? isDownloaded,
    bool? isSelected,
    String? documentType,
    String? readingStyle,
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
        imageUrl: imageUrl ?? this.imageUrl,
        audioUrl: audioUrl ?? this.audioUrl,
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
