import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../models/article.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'filter_screen.dart';
import 'sort_screen.dart';

/// Displays a list of articles from a newspaper with processing status.
/// Each article can be played, shows quality score, and handles processing states.
class ArticleListScreen extends StatefulWidget {
  final String newspaperTitle;
  final String newspaperDate;
  final String language;
  final List<UploadedArticle> articles;

  const ArticleListScreen({
    Key? key,
    required this.newspaperTitle,
    required this.newspaperDate,
    required this.language,
    required this.articles,
  }) : super(key: key);

  @override
  State<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends State<ArticleListScreen> {
  late List<_ArticleState> _articleStates;

  @override
  void initState() {
    super.initState();
    _initializeArticleStates();
  }

  void _initializeArticleStates() {
    _articleStates = widget.articles.map((article) {
      return _ArticleState(
        article: article,
        status: _getArticleStatus(article),
      );
    }).toList();
  }

  _ProcessingStatus _getArticleStatus(UploadedArticle article) {
    // Determine status based on article fields
    // In a real app, this would come from API response
    if (article.audioUrl.isEmpty) {
      return _ProcessingStatus.processing;
    }
    return _ProcessingStatus.completed;
  }

  int _getProcessedCount() {
    return _articleStates
        .where((s) => s.status == _ProcessingStatus.completed)
        .length;
  }

  void _retryArticle(int index) {
    setState(() {
      _articleStates[index].status = _ProcessingStatus.processing;
      // In a real app, retry would trigger an API call
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _articleStates[index].status = _ProcessingStatus.completed;
          });
        }
      });
    });
  }

  void _playArticle(UploadedArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          article: article,
          queue: widget.articles,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final processedCount = _getProcessedCount();
    final totalCount = widget.articles.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header with newspaper metadata
            _buildHeader(context, processedCount, totalCount),
            // List of articles
            Expanded(
              child: widget.articles.isEmpty
                  ? _buildEmptyState(context)
                  : _buildArticleList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    int processedCount,
    int totalCount,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: GVColors.bgSecondary(context),
        border: Border(
          bottom: BorderSide(
            color: GVColors.borderTertiary(context),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button, title, and action buttons
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(GVRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.arrow_back_ios_new_outlined,
                      size: 18, color: GVColors.textSecondary(context)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.newspaperTitle,
                      style: GVTypography.title(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.newspaperDate} • ${widget.language}',
                      style: GVTypography.small(context),
                    ),
                  ],
                ),
              ),
              // Search button
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                ),
                borderRadius: BorderRadius.circular(GVRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.search_outlined,
                      size: 20, color: GVColors.textSecondary(context)),
                ),
              ),
              // Filter button
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FilterScreen()),
                ),
                borderRadius: BorderRadius.circular(GVRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.tune_outlined,
                      size: 20, color: GVColors.textSecondary(context)),
                ),
              ),
              // Sort button
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SortScreen()),
                ),
                borderRadius: BorderRadius.circular(GVRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.sort_outlined,
                      size: 20, color: GVColors.textSecondary(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress indicator
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Processing articles',
                          style: GVTypography.small(context),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: GVColors.bgTertiary(context),
                            borderRadius: BorderRadius.circular(GVRadius.pill),
                          ),
                          child: Text(
                            '$processedCount of $totalCount',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: GVColors.textSecondary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: totalCount > 0 ? processedCount / totalCount : 0,
                        minHeight: 4,
                        backgroundColor: GVColors.borderTertiary(context),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          GVColors.accent(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArticleList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.articles.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        thickness: 0.5,
        color: GVColors.borderTertiary(context),
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final article = widget.articles[index];
        final state = _articleStates[index];
        return _buildArticleCard(context, article, state, index);
      },
    );
  }

  Widget _buildArticleCard(
    BuildContext context,
    UploadedArticle article,
    _ArticleState state,
    int index,
  ) {
    return InkWell(
      onTap: state.status == _ProcessingStatus.completed
          ? () => _playArticle(article)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Article icon / status indicator
            _buildStatusIndicator(context, state.status),
            const SizedBox(width: 12),
            // Article content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and section badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          article.title,
                          style: GVTypography.body(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSectionBadge(context, article.category),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Preview text
                  Text(
                    _getPreviewText(article.content),
                    style: GVTypography.small(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Quality score / status info
                  _buildStatusInfo(context, article, state.status),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Action icon based on status
            _buildActionIcon(context, state.status, index, article),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context, _ProcessingStatus status) {
    switch (status) {
      case _ProcessingStatus.completed:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: GVColors.successBg(context),
            borderRadius: BorderRadius.circular(GVRadius.md),
            border: Border.all(
              color: GVColors.success(context).withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Icon(
            Icons.check_circle_outlined,
            size: 20,
            color: GVColors.success(context),
          ),
        );
      case _ProcessingStatus.processing:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: GVColors.bgTertiary(context),
            borderRadius: BorderRadius.circular(GVRadius.md),
            border: Border.all(
              color: GVColors.borderTertiary(context),
              width: 0.5,
            ),
          ),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  GVColors.accent(context),
                ),
              ),
            ),
          ),
        );
      case _ProcessingStatus.failed:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: GVColors.dangerBg(context),
            borderRadius: BorderRadius.circular(GVRadius.md),
            border: Border.all(
              color: GVColors.danger(context).withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Icon(
            Icons.error_outline,
            size: 20,
            color: GVColors.danger(context),
          ),
        );
    }
  }

  Widget _buildSectionBadge(BuildContext context, String category) {
    final color = _getCategoryColor(context, category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(GVRadius.pill),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        category,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatusInfo(
    BuildContext context,
    UploadedArticle article,
    _ProcessingStatus status,
  ) {
    switch (status) {
      case _ProcessingStatus.completed:
        // Quality score as percentage
        final qualityScore = _getQualityScore(article);
        return Row(
          children: [
            Icon(Icons.stars_rounded,
                size: 14, color: GVColors.accent(context)),
            const SizedBox(width: 4),
            Text(
              '$qualityScore% quality',
              style: TextStyle(
                fontSize: 11,
                color: GVColors.textSecondary(context),
              ),
            ),
          ],
        );
      case _ProcessingStatus.processing:
        return Text(
          'Processing...',
          style: TextStyle(
            fontSize: 11,
            color: GVColors.textSecondary(context),
            fontStyle: FontStyle.italic,
          ),
        );
      case _ProcessingStatus.failed:
        return Text(
          'Failed to process',
          style: TextStyle(
            fontSize: 11,
            color: GVColors.danger(context),
          ),
        );
    }
  }

  Widget _buildActionIcon(
    BuildContext context,
    _ProcessingStatus status,
    int index,
    UploadedArticle article,
  ) {
    switch (status) {
      case _ProcessingStatus.completed:
        return InkWell(
          onTap: () => _playArticle(article),
          borderRadius: BorderRadius.circular(GVRadius.md),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.play_circle_outline,
              size: 20,
              color: GVColors.accent(context),
            ),
          ),
        );
      case _ProcessingStatus.processing:
        return Container(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                GVColors.textSecondary(context),
              ),
            ),
          ),
        );
      case _ProcessingStatus.failed:
        return InkWell(
          onTap: () => _retryArticle(index),
          borderRadius: BorderRadius.circular(GVRadius.md),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.refresh_outlined,
              size: 20,
              color: GVColors.danger(context),
            ),
          ),
        );
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: GVColors.textTertiary(context),
          ),
          const SizedBox(height: 16),
          Text(
            'No articles',
            style: GVTypography.heading(context),
          ),
          const SizedBox(height: 8),
          Text(
            'This newspaper has no articles yet.',
            style: GVTypography.bodySecondary(context),
          ),
        ],
      ),
    );
  }

  String _getPreviewText(String content) {
    if (content.isEmpty) return 'No preview available';
    // Truncate to 50 characters
    final preview = content.replaceAll('\n', ' ').trim();
    return preview.length > 50 ? '${preview.substring(0, 50)}...' : preview;
  }

  int _getQualityScore(UploadedArticle article) {
    // In a real app, this would come from API
    // For now, return a consistent score based on article data
    if (article.audioUrl.isEmpty) return 0;
    // Simple heuristic: more content = higher quality
    final contentLength = article.content.length;
    if (contentLength > 5000) return 95;
    if (contentLength > 2000) return 85;
    if (contentLength > 500) return 75;
    return 65;
  }

  Color _getCategoryColor(BuildContext context, String category) {
    switch (category.toLowerCase()) {
      case 'news':
        return GVColors.accent(context);
      case 'government':
        return GVColors.success(context);
      case 'editorial':
        return const Color(0xFF378ADD);
      case 'education':
        return const Color(0xFF9C27B0);
      case 'health':
        return const Color(0xFFE91E63);
      case 'business':
        return const Color(0xFFFFA500);
      default:
        return GVColors.textSecondary(context);
    }
  }
}

// ── Article state tracking ───────────────────────────────────────────────────

enum _ProcessingStatus { completed, processing, failed }

class _ArticleState {
  final UploadedArticle article;
  _ProcessingStatus status;

  _ArticleState({
    required this.article,
    required this.status,
  });
}

