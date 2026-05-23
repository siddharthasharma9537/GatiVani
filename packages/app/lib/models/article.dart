class UploadedArticle {
  final String id;
  final String title;
  final String content;
  final String source;
  final String storageUrl;
  final String category;
  final String audioUrl;
  final DateTime extractedAt;

  // ── Processing metadata from backend ─────────────────────────────────────
  final bool truncated;
  final int totalPages;
  final int processedPages;
  final String tier;

  UploadedArticle({
    required this.id,
    required this.title,
    required this.content,
    required this.source,
    required this.storageUrl,
    required this.category,
    required this.audioUrl,
    required this.extractedAt,
    this.truncated = false,
    this.totalPages = 1,
    this.processedPages = 1,
    this.tier = 'premium',
  });

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'title': title,
        'content': content,
        'source': source,
        'storageUrl': storageUrl,
        'category': category,
        'audioUrl': audioUrl,
        'extractedAt': extractedAt.toIso8601String(),
        'truncated': truncated,
        'totalPages': totalPages,
        'processedPages': processedPages,
        'tier': tier,
      };

  factory UploadedArticle.fromFirestore(Map<String, dynamic> data) {
    return UploadedArticle(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      source: data['source'] as String? ?? '',
      storageUrl: data['storageUrl'] as String? ?? '',
      category: data['category'] as String? ?? 'News',
      audioUrl: data['audioUrl'] as String? ?? '',
      extractedAt: DateTime.parse(
          data['extractedAt'] as String? ?? DateTime.now().toIso8601String()),
      truncated: data['truncated'] as bool? ?? false,
      totalPages: data['totalPages'] as int? ?? 1,
      processedPages: data['processedPages'] as int? ?? 1,
      tier: data['tier'] as String? ?? 'premium',
    );
  }

  UploadedArticle copyWith({
    String? id,
    String? title,
    String? content,
    String? source,
    String? storageUrl,
    String? category,
    String? audioUrl,
    DateTime? extractedAt,
    bool? truncated,
    int? totalPages,
    int? processedPages,
    String? tier,
  }) {
    return UploadedArticle(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      source: source ?? this.source,
      storageUrl: storageUrl ?? this.storageUrl,
      category: category ?? this.category,
      audioUrl: audioUrl ?? this.audioUrl,
      extractedAt: extractedAt ?? this.extractedAt,
      truncated: truncated ?? this.truncated,
      totalPages: totalPages ?? this.totalPages,
      processedPages: processedPages ?? this.processedPages,
      tier: tier ?? this.tier,
    );
  }
}
