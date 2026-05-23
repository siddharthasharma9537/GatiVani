import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../models/article.dart';
import 'player_screen.dart';

/// Search screen for finding articles by keyword.
/// Implements full-text search with pagination and result display.
class SearchScreen extends StatefulWidget {
  final String? initialQuery;

  const SearchScreen({
    Key? key,
    this.initialQuery,
  }) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late TextEditingController _searchController;
  List<UploadedArticle> _searchResults = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentOffset = 0;
  int _totalResults = 0;
  String _lastQuery = '';
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      Future.delayed(Duration.zero, () => _performSearch(widget.initialQuery!));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query, {int offset = 0}) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasError = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      // TODO: Replace with actual API call
      // final response = await http.get(
      //   Uri.parse('http://localhost:8788/api/articles/search')
      //       .replace(queryParameters: {
      //     'q': query,
      //     'limit': _pageSize.toString(),
      //     'offset': offset.toString(),
      //   }),
      // );
      //
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body);
      //   setState(() {
      //     if (offset == 0) {
      //       _searchResults = (data['articles'] as List)
      //           .map((a) => UploadedArticle.fromJson(a))
      //           .toList();
      //     } else {
      //       _searchResults.addAll((data['articles'] as List)
      //           .map((a) => UploadedArticle.fromJson(a))
      //           .toList());
      //     }
      //     _totalResults = data['total'] ?? 0;
      //     _lastQuery = query;
      //     _currentOffset = offset;
      //     _isLoading = false;
      //   });
      // } else {
      //   throw Exception('Failed to search articles');
      // }

      // Mock data for demonstration
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _searchResults = _generateMockSearchResults(query, offset);
        _totalResults = 150;
        _lastQuery = query;
        _currentOffset = offset;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Search failed: $e';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _currentOffset = 0;
      });
      return;
    }

    if (query != _lastQuery) {
      _currentOffset = 0;
    }
    // Debounce search
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _searchController.text == query) {
        _performSearch(query);
      }
    });
  }

  void _loadMore() {
    if (_lastQuery.isNotEmpty && !_isLoading) {
      _performSearch(_lastQuery, offset: _currentOffset + _pageSize);
    }
  }

  void _playArticle(UploadedArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          article: article,
          queue: _searchResults,
        ),
      ),
    );
  }

  List<UploadedArticle> _generateMockSearchResults(String query, int offset) {
    final mockArticles = [
      UploadedArticle(
        id: '1',
        title: 'Cricket Match Report: India vs Australia',
        content: 'The India cricket team defeated Australia in a thrilling match...',
        source: 'The Hindu',
        storageUrl: '',
        category: 'Sports',
        audioUrl: 'https://example.com/audio1.mp3',
        extractedAt: DateTime.now(),
      ),
      UploadedArticle(
        id: '2',
        title: 'Cricket Tournament Begins in Delhi',
        content: 'The annual cricket tournament kicked off today in Delhi...',
        source: 'Times of India',
        storageUrl: '',
        category: 'Sports',
        audioUrl: 'https://example.com/audio2.mp3',
        extractedAt: DateTime.now(),
      ),
      UploadedArticle(
        id: '3',
        title: 'New Cricket Stadium Opens',
        content: 'A state-of-the-art cricket stadium was inaugurated today...',
        source: 'The Hindu',
        storageUrl: '',
        category: 'Sports',
        audioUrl: 'https://example.com/audio3.mp3',
        extractedAt: DateTime.now(),
      ),
    ];

    return mockArticles
        .where((a) =>
            a.title.toLowerCase().contains(query.toLowerCase()) ||
            a.content.toLowerCase().contains(query.toLowerCase()))
        .skip(offset)
        .take(_pageSize)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          _buildSearchInput(context),
          Expanded(
            child: _searchResults.isEmpty && !_isLoading && _lastQuery.isEmpty
                ? _buildEmptyState(context)
                : _searchResults.isEmpty && !_isLoading && _lastQuery.isNotEmpty
                    ? _buildNoResultsState(context)
                    : _buildSearchResults(context),
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
        'Search Articles',
        style: GVTypography.title(context),
      ),
      centerTitle: false,
    );
  }

  Widget _buildSearchInput(BuildContext context) {
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
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search by title or content...',
          hintStyle: TextStyle(color: GVColors.textTertiary(context)),
          prefixIcon: Icon(
            Icons.search_outlined,
            size: 20,
            color: GVColors.textSecondary(context),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? InkWell(
                  onTap: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                      _currentOffset = 0;
                    });
                  },
                  child: Icon(
                    Icons.clear_outlined,
                    size: 20,
                    color: GVColors.textSecondary(context),
                  ),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GVRadius.md),
            borderSide: BorderSide(
              color: GVColors.borderSecondary(context),
              width: 0.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GVRadius.md),
            borderSide: BorderSide(
              color: GVColors.borderSecondary(context),
              width: 0.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GVRadius.md),
            borderSide: BorderSide(
              color: GVColors.accent(context),
              width: 1,
            ),
          ),
          filled: true,
          fillColor: GVColors.bgPrimary(context),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        style: GVTypography.body(context),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_outlined,
            size: 48,
            color: GVColors.textTertiary(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Start searching',
            style: GVTypography.heading(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a keyword to find articles',
            style: GVTypography.bodySecondary(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
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
            'No results found',
            style: GVTypography.heading(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: GVTypography.bodySecondary(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _searchResults.length + (_totalResults > _currentOffset + _pageSize ? 1 : 0),
          separatorBuilder: (_, __) => Divider(
            height: 0.5,
            thickness: 0.5,
            color: GVColors.borderTertiary(context),
            indent: 16,
            endIndent: 16,
          ),
          itemBuilder: (context, index) {
            if (index == _searchResults.length) {
              return _buildLoadMoreButton(context);
            }
            return _buildSearchResultCard(context, _searchResults[index]);
          },
        ),
        if (_isLoading && _currentOffset == 0)
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
        if (_hasError)
          Container(
            color: GVColors.bgPrimary(context).withValues(alpha: 0.9),
            child: Center(
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
                    'Search failed',
                    style: GVTypography.heading(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    style: GVTypography.bodySecondary(context),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchResultCard(BuildContext context, UploadedArticle article) {
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        article.source,
                        style: TextStyle(
                          fontSize: 11,
                          color: GVColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: GVColors.accentBg(context),
                          borderRadius: BorderRadius.circular(GVRadius.pill),
                        ),
                        child: Text(
                          article.category,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: GVColors.accent(context),
                          ),
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
                  'Load More Results',
                  style: TextStyle(
                    color: GVColors.accent(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }
}
