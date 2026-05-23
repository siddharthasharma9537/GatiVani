import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../models/article.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Reading History Screen
///
/// Displays articles that the user has previously read, retrieved from the backend.
/// Shows article metadata (title, section, timestamp), with options to:
/// - Play article audio
/// - Toggle favorite status
/// - View detailed article
class ReadingHistoryScreen extends StatefulWidget {
  final String apiBaseUrl;
  final String? jwtToken;
  final VoidCallback? onArticleSelected;

  const ReadingHistoryScreen({
    Key? key,
    required this.apiBaseUrl,
    this.jwtToken,
    this.onArticleSelected,
  }) : super(key: key);

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  List<Map<String, dynamic>> readingHistory = [];
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;
  int currentPage = 0;
  int pageSize = 20;
  int totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadReadingHistory();
  }

  Future<void> _loadReadingHistory({int offset = 0}) async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = null;
    });

    try {
      if (widget.jwtToken == null || widget.jwtToken!.isEmpty) {
        throw Exception('JWT token required for authenticated request');
      }

      final url = Uri.parse(
        '${widget.apiBaseUrl}/api/user/reading-history?limit=$pageSize&offset=$offset'
      );

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          readingHistory = List<Map<String, dynamic>>.from(data['data'] ?? []);
          totalCount = data['pagination']?['total'] ?? 0;
          isLoading = false;
          currentPage = offset ~/ pageSize;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          hasError = true;
          errorMessage = 'Unauthorized: Invalid or expired token';
          isLoading = false;
        });
      } else {
        final errorData = jsonDecode(response.body);
        setState(() {
          hasError = true;
          errorMessage = errorData['message'] ?? 'Failed to load reading history';
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          hasError = true;
          errorMessage = 'Error: ${e.toString()}';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String articleId, bool isFavorite) async {
    try {
      if (widget.jwtToken == null || widget.jwtToken!.isEmpty) {
        throw Exception('JWT token required');
      }

      final url = Uri.parse(
        '${widget.apiBaseUrl}/api/articles/$articleId/toggle-favorite'
      );

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({'isFavorite': !isFavorite}),
      );

      if (response.statusCode == 200) {
        // Reload the list to get updated favorite status
        _loadReadingHistory(offset: currentPage * pageSize);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle favorite')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _formatDateTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return 'Not read yet';
    }
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return dateTime.toString().split(' ')[0];
      }
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading History'),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading reading history...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppTheme.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load reading history',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? 'Unknown error',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _loadReadingHistory(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (readingHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: AppTheme.secondaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No reading history yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Articles you read will appear here',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: readingHistory.length + 1,
      itemBuilder: (context, index) {
        if (index == readingHistory.length) {
          return _buildPaginationControls();
        }

        final item = readingHistory[index];
        final article = item['articles'];
        final isFavorite = item['favorite'] ?? false;
        final readAt = item['read_at'] as String?;
        final articleId = item['article_id'] as String;

        return _buildArticleCard(
          article,
          isFavorite,
          readAt,
          articleId,
        );
      },
    );
  }

  Widget _buildArticleCard(
    Map<String, dynamic> article,
    bool isFavorite,
    String? readAt,
    String articleId,
  ) {
    final title = article['title'] ?? 'Untitled';
    final section = article['section'] ?? 'News';
    final imageUrl = article['image_url'] as String?;
    final audioUrl = article['audio_url'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          widget.onArticleSelected?.call();
          // Navigate or handle article selection
        },
        child: Column(
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Container(
                width: double.infinity,
                height: 200,
                color: AppTheme.backgroundColor,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppTheme.backgroundColor,
                      child: Icon(Icons.image_not_supported),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          section,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDateTime(readAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (audioUrl != null && audioUrl.isNotEmpty)
                        ElevatedButton.icon(
                          onPressed: () {
                            // Handle audio playback
                            print('Playing: $audioUrl');
                          },
                          icon: Icon(Icons.play_circle),
                          label: Text('Listen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? AppTheme.errorColor : Colors.grey,
                        ),
                        onPressed: () {
                          _toggleFavorite(articleId, isFavorite);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationControls() {
    final hasNextPage = (currentPage + 1) * pageSize < totalCount;
    final hasPrevPage = currentPage > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasPrevPage)
            ElevatedButton.icon(
              onPressed: () {
                _loadReadingHistory(offset: (currentPage - 1) * pageSize);
              },
              icon: Icon(Icons.arrow_back),
              label: Text('Previous'),
            )
          else
            ElevatedButton.icon(
              onPressed: null,
              icon: Icon(Icons.arrow_back),
              label: Text('Previous'),
            ),
          const SizedBox(width: 16),
          Text(
            'Page ${currentPage + 1} of ${(totalCount / pageSize).ceil()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 16),
          if (hasNextPage)
            ElevatedButton.icon(
              onPressed: () {
                _loadReadingHistory(offset: (currentPage + 1) * pageSize);
              },
              icon: Icon(Icons.arrow_forward),
              label: Text('Next'),
            )
          else
            ElevatedButton.icon(
              onPressed: null,
              icon: Icon(Icons.arrow_forward),
              label: Text('Next'),
            ),
        ],
      ),
    );
  }
}
