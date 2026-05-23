import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../models/article.dart';
import 'player_screen.dart';

/// Sort options screen for viewing articles sorted by quality or date.
/// Allows users to browse high-quality or latest articles.
class SortScreen extends StatefulWidget {
  final String? initialSort;

  const SortScreen({
    Key? key,
    this.initialSort = 'date',
  }) : super(key: key);

  @override
  State<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends State<SortScreen> {
  late String _sortBy;
  List<UploadedArticle> _sortedArticles = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentOffset = 0;
  int _totalArticles = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.initialSort ?? 'date';
    _loadSortedArticles(_sortBy);
  }

  Future<void> _loadSortedArticles(String sortBy, {int offset = 0}) async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('http://localhost:8788/api/articles/sort')
      //       .replace(queryParameters: {
      //     'by': sortBy,
      //     'limit': _pageSize.toString(),
      //     'offset': offset.toString(),
      //   }),
      // );
      //
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body);
      //   setState(() {
      //     if (offset == 0) {
      //       _sortedArticles = (data['articles'] as List)
      //           .map((a) => UploadedArticle.fromJson(a))
      //           .toList();
      //     } else {
      //       _sortedArticles.addAll((data['articles'] as List)
      //           .map((a) => UploadedArticle.fromJson(a))
      //           .toList());
      //     }
      //     _totalArticles = data['total'] ?? 0;
      //     _currentOffset = offset;
      //     _sortBy = sortBy;
      //     _isLoading = false;
      //   });
      // } else {
      //   throw Exception('Failed to load articles');
      // }

      // Mock data for demonstration
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _sortedArticles = _generateMockSortedArticles(sortBy, offset);
        _totalArticles = 250;
        _currentOffset = offset;
        _sortBy = sortBy;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load articles: $e';
        _isLoading = false;
      });
    }
  }

  void _changeSortOption(String sortBy) {
    if (sortBy != _sortBy) {
      _loadSortedArticles(sortBy);
    }
  }

  void _loadMore() {
    if (!_isLoading) {
      _loadSortedArticles(_sortBy, offset: _currentOffset + _pageSize);
    }
  }

  void _playArticle(UploadedArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          article: article,
          queue: _sortedArticles,
        ),
      ),
    );
  }

  List<UploadedArticle> _generateMockSortedArticles(String sortBy, int offset) {
    final articles = [
      UploadedArticle(
        id: '1',
        title: 'Breaking: Major Market Rally Today',
        content: 'Stock markets experienced a significant rally as investors...',
        source: 'The Hindu',
        storageUrl: '',
        category: 'Business',
        audioUrl: 'https://example.com/audio1.mp3',
        extractedAt: DateTime.now(),
      ),
      UploadedArticle(
        id: '2',
        title: 'Technology Breakthrough Announced',
        content: 'Scientists announced a major breakthrough in quantum computing...',
        source: 'Times of India',
        storageUrl: '',
        category: 'Technology',
        audioUrl: 'https://example.com/audio2.mp3',
        extractedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      UploadedArticle(
        id: '3',
        title: 'Health Ministry Launches New Initiative',
        content: 'The health ministry launched a new public health initiative...',
        source: 'The Hindu',
        storageUrl: '',
        category: 'Health',
        audioUrl: 'https://example.com/audio3.mp3',
        extractedAt: DateTime.now().subtract(const Duration(hours: 5)),
      ),
      UploadedArticle(
        id: '4',
        title: 'Entertainment: Award Ceremony Live Coverage',
        content: 'The annual entertainment awards were held yesterday with...',
        source: 'News Today',
        storageUrl: '',
        category: 'Entertainment',
        audioUrl: 'https://example.com/audio4.mp3',
        extractedAt: DateTime.now().subtract(const Duration(hours: 8)),
      ),
      UploadedArticle(
        id: '5',
        title: 'Sports: Championship Finals Result',
        content: 'The championship finals concluded with an exciting match...',
        source: 'The Hindu',
        storageUrl: '',
        category: 'Sports',
        audioUrl: 'https://example.com/audio5.mp3',
        extractedAt: DateTime.now().subtract(const Duration(hours: 12)),
      ),
    ];

    if (sortBy == 'quality') {
      // Sort by quality (descending)
      articles.sort((a, b) => b.content.length.compareTo(a.content.length));
    } else {
      // Sort by date (newest first)
      articles.sort((a, b) => b.extractedAt.compareTo(a.extractedAt));
    }

    return articles.skip(offset).take(_pageSize).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          _buildSortOptions(context),
          Expanded(
            child: _isLoading && _currentOffset == 0
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        GVColors.accent(context),
                      ),
                    ),
                  )
                : _hasError
                    ? _buildErrorState(context)
                    : _buildSortedArticles(context),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: GVColors.bgPrimary(context),
      elevation: 0,
      leading: InkWell(
        onTap: () => Navigator.pop(context),
        borderRadius: BorderRadius.circular(GVRadius.md),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.arrow_back_ios_new_outlined,
            size: 18,
            color: GVColors.textSecondary(context),
          ),
        ),
      ),
      title: Text(
        'Sort Articles',
        style: GVTypography.title(context),
      ),
      centerTitle: false,
    );
  }

  Widget _buildSortOptions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Text(
            'Sort By',
            style: GVTypography.bodySecondary(context),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSortOption(
                context,
                'Date',
                'Newest first',
                'date',
              ),
              const SizedBox(width: 12),
              _buildSortOption(
                context,
                'Quality',
                'Best content',
                'quality',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortOption(
    BuildContext context,
    String title,
    String subtitle,
    String sortValue,
  ) {
    final isSelected = _sortBy == sortValue;
    return Expanded(
      child: InkWell(
        onTap: () => _changeSortOption(sortValue),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? GVColors.accent(context).withValues(alpha: 0.12)
                : GVColors.bgTertiary(context),
            borderRadius: BorderRadius.circular(GVRadius.md),
            border: Border.all(
              color: isSelected
                  ? GVColors.accent(context)
                  : GVColors.borderTertiary(context),
              width: isSelected ? 1 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? GVColors.accent(context)
                        : GVColors.borderSecondary(context),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: GVColors.accent(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? GVColors.accent(context)
                            : GVColors.textPrimary(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: GVColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortedArticles(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _sortedArticles.length +
          (_currentOffset + _pageSize < _totalArticles ? 1 : 0),
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        thickness: 0.5,
        color: GVColors.borderTertiary(context),
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        if (index == _sortedArticles.length) {
          return _buildLoadMoreButton(context);
        }
        return _buildArticleCard(context, _sortedArticles[index]);
      },
    );
  }

  Widget _buildArticleCard(BuildContext context, UploadedArticle article) {
    final timeAgo = _getTimeAgo(article.extractedAt);
    return InkWell(
      onTap: () => _playArticle(article),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
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
              child: Icon(
                Icons.article_outlined,
                size: 20,
                color: GVColors.accent(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: GVTypography.body(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    article.content.replaceAll('\n', ' ').trim(),
                    style: GVTypography.small(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 12,
                        color: GVColors.textSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: GVColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.category_outlined,
                        size: 12,
                        color: GVColors.textSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        article.category,
                        style: TextStyle(
                          fontSize: 11,
                          color: GVColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.play_circle_outline,
              size: 20,
              color: GVColors.accent(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: _isLoading
            ? CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  GVColors.accent(context),
                ),
              )
            : ElevatedButton(
                onPressed: _loadMore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GVColors.bgTertiary(context),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Load More Articles',
                  style: TextStyle(
                    color: GVColors.accent(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: GVColors.danger(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load',
            style: GVTypography.heading(context),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _errorMessage,
              style: GVTypography.bodySecondary(context),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _hasError = false;
              });
              _loadSortedArticles(_sortBy);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GVColors.accent(context),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }
}
