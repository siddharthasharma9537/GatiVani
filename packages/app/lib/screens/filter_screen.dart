import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../models/article.dart';
import 'player_screen.dart';

/// Filter screen for browsing articles by section/category.
/// Displays available sections with article counts and allows filtering.
class FilterScreen extends StatefulWidget {
  final String? initialSection;

  const FilterScreen({
    Key? key,
    this.initialSection,
  }) : super(key: key);

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  List<SectionInfo> _sections = [];
  List<UploadedArticle> _filteredArticles = [];
  String? _selectedSection;
  bool _isLoading = false;
  bool _isLoadingArticles = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentOffset = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
    _loadSections();
    if (widget.initialSection != null) {
      Future.delayed(Duration.zero, () => _filterBySection(widget.initialSection!));
    }
  }

  Future<void> _loadSections() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('http://localhost:8788/api/articles/sections'),
      // );
      //
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body) as List;
      //   setState(() {
      //     _sections = data
      //         .map((s) => SectionInfo(
      //               section: s['section'],
      //               count: s['count'],
      //             ))
      //         .toList();
      //     _isLoading = false;
      //   });
      // } else {
      //   throw Exception('Failed to load sections');
      // }

      // Mock data for demonstration
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _sections = [
          SectionInfo(section: 'Politics', count: 45),
          SectionInfo(section: 'Sports', count: 78),
          SectionInfo(section: 'Business', count: 32),
          SectionInfo(section: 'Health', count: 25),
          SectionInfo(section: 'Technology', count: 38),
          SectionInfo(section: 'Entertainment', count: 42),
        ];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load sections: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _filterBySection(String section, {int offset = 0}) async {
    setState(() {
      _isLoadingArticles = true;
      _hasError = false;
      _selectedSection = section;
    });

    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('http://localhost:8788/api/articles/filter')
      //       .replace(queryParameters: {
      //     'section': section,
      //     'limit': _pageSize.toString(),
      //     'offset': offset.toString(),
      //   }),
      // );
      //
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body);
      //   setState(() {
      //     if (offset == 0) {
      //       _filteredArticles = (data['articles'] as List)
      //           .map((a) => UploadedArticle.fromJson(a))
      //           .toList();
      //     } else {
      //       _filteredArticles.addAll((data['articles'] as List)
      //           .map((a) => UploadedArticle.fromJson(a))
      //           .toList());
      //     }
      //     _currentOffset = offset;
      //     _isLoadingArticles = false;
      //   });
      // } else {
      //   throw Exception('Failed to filter articles');
      // }

      // Mock data for demonstration
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _filteredArticles = _generateMockFilteredArticles(section, offset);
        _currentOffset = offset;
        _isLoadingArticles = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to filter articles: $e';
        _isLoadingArticles = false;
      });
    }
  }

  void _loadMore() {
    if (_selectedSection != null && !_isLoadingArticles) {
      _filterBySection(_selectedSection!, offset: _currentOffset + _pageSize);
    }
  }

  void _playArticle(UploadedArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          article: article,
          queue: _filteredArticles,
        ),
      ),
    );
  }

  List<UploadedArticle> _generateMockFilteredArticles(String section, int offset) {
    final mockArticles = {
      'Politics': [
        UploadedArticle(
          id: '1',
          title: 'Election Results Announced',
          content: 'The election results were declared today with a record turnout...',
          source: 'The Hindu',
          storageUrl: '',
          category: 'Politics',
          audioUrl: 'https://example.com/audio1.mp3',
          extractedAt: DateTime.now(),
        ),
        UploadedArticle(
          id: '2',
          title: 'Parliament Session Begins',
          content: 'The new parliament session started with key policy discussions...',
          source: 'Times of India',
          storageUrl: '',
          category: 'Politics',
          audioUrl: 'https://example.com/audio2.mp3',
          extractedAt: DateTime.now(),
        ),
      ],
      'Sports': [
        UploadedArticle(
          id: '3',
          title: 'Cricket World Cup Qualifiers',
          content: 'India qualified for the cricket world cup with a dominant performance...',
          source: 'The Hindu',
          storageUrl: '',
          category: 'Sports',
          audioUrl: 'https://example.com/audio3.mp3',
          extractedAt: DateTime.now(),
        ),
        UploadedArticle(
          id: '4',
          title: 'Tennis Championship Finals',
          content: 'The tennis championship finals were held at the national center...',
          source: 'News Today',
          storageUrl: '',
          category: 'Sports',
          audioUrl: 'https://example.com/audio4.mp3',
          extractedAt: DateTime.now(),
        ),
      ],
      'Business': [
        UploadedArticle(
          id: '5',
          title: 'Stock Market Surge',
          content: 'The stock market reached all-time highs today with strong gains...',
          source: 'The Hindu',
          storageUrl: '',
          category: 'Business',
          audioUrl: 'https://example.com/audio5.mp3',
          extractedAt: DateTime.now(),
        ),
      ],
    };

    return (mockArticles[section] ?? []).skip(offset).take(_pageSize).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  GVColors.accent(context),
                ),
              ),
            )
          : _hasError
              ? _buildErrorState(context)
              : Column(
                  children: [
                    _buildSectionTabs(context),
                    Expanded(
                      child: _selectedSection == null
                          ? _buildSelectSectionState(context)
                          : _buildFilteredArticles(context),
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
        'Browse by Section',
        style: GVTypography.title(context),
      ),
      centerTitle: false,
    );
  }

  Widget _buildSectionTabs(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GVColors.bgSecondary(context),
        border: Border(
          bottom: BorderSide(
            color: GVColors.borderTertiary(context),
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: List.generate(
            _sections.length,
            (index) => _buildSectionTab(context, _sections[index]),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTab(BuildContext context, SectionInfo section) {
    final isSelected = _selectedSection == section.section;
    return InkWell(
      onTap: () => _filterBySection(section.section),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? GVColors.accent(context)
              : GVColors.bgTertiary(context),
          borderRadius: BorderRadius.circular(GVRadius.pill),
          border: isSelected
              ? null
              : Border.all(
                  color: GVColors.borderTertiary(context),
                  width: 0.5,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              section.section,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : GVColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${section.count} articles',
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
                    : GVColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectSectionState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.category_outlined,
            size: 48,
            color: GVColors.textTertiary(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a section',
            style: GVTypography.heading(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a category above to view articles',
            style: GVTypography.bodySecondary(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredArticles(BuildContext context) {
    return Stack(
      children: [
        _filteredArticles.isEmpty && !_isLoadingArticles
            ? _buildEmptyFilterState(context)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _filteredArticles.length +
                    (_currentOffset + _pageSize < 100 ? 1 : 0),
                separatorBuilder: (_, __) => Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: GVColors.borderTertiary(context),
                  indent: 16,
                  endIndent: 16,
                ),
                itemBuilder: (context, index) {
                  if (index == _filteredArticles.length) {
                    return _buildLoadMoreButton(context);
                  }
                  return _buildArticleCard(context, _filteredArticles[index]);
                },
              ),
        if (_isLoadingArticles && _currentOffset == 0)
          Container(
            color: GVColors.bgPrimary(context).withValues(alpha: 0.8),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  GVColors.accent(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyFilterState(BuildContext context) {
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
            'This section has no articles yet',
            style: GVTypography.bodySecondary(context),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleCard(BuildContext context, UploadedArticle article) {
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
                Icons.newspaper_outlined,
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
                  Text(
                    article.source,
                    style: TextStyle(
                      fontSize: 11,
                      color: GVColors.textSecondary(context),
                    ),
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
        child: _isLoadingArticles
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
              _loadSections();
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
}

class SectionInfo {
  final String section;
  final int count;

  SectionInfo({
    required this.section,
    required this.count,
  });
}
