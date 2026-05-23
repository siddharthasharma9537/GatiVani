import 'package:flutter/material.dart';
import '../models/article.dart';
import 'article_list_screen.dart';

/// Example integration showing how to use ArticleListScreen with existing screens.
///
/// This file demonstrates:
/// 1. Navigating from home screen to article list
/// 2. Fetching articles from API
/// 3. Handling empty/error states
/// 4. Integration with existing UI components

class ArticleListIntegrationExample {
  // Example 1: Simple navigation from home screen
  static void navigateToArticleList(BuildContext context) {
    final exampleArticles = [
      UploadedArticle(
        id: '1',
        title: 'Political Updates: AP Government Announces New Policies',
        content: 'The Andhra Pradesh government announced several new policies today aimed at improving education...',
        source: 'The Hindu',
        storageUrl: 'https://example.com/article1.jpg',
        category: 'Government',
        audioUrl: 'https://example.com/audio/article1.mp3',
        extractedAt: DateTime.now(),
      ),
      UploadedArticle(
        id: '2',
        title: 'Business Report: Tech Sector Growth Surges',
        content: 'The technology sector in Telangana has experienced significant growth this quarter...',
        source: 'Business Line',
        storageUrl: 'https://example.com/article2.jpg',
        category: 'Business',
        audioUrl: 'https://example.com/audio/article2.mp3',
        extractedAt: DateTime.now(),
      ),
      UploadedArticle(
        id: '3',
        title: 'Health Ministry Launches Vaccination Campaign',
        content: 'The state health ministry launched a comprehensive vaccination program targeting rural areas...',
        source: 'The Hindu',
        storageUrl: '',
        category: 'Health',
        audioUrl: '', // This article is still processing
        extractedAt: DateTime.now(),
      ),
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleListScreen(
          newspaperTitle: 'The Hindu',
          newspaperDate: 'May 23, 2026',
          language: 'Telugu',
          articles: exampleArticles,
        ),
      ),
    );
  }

  // Example 2: Fetch articles from API
  static Future<List<UploadedArticle>> fetchArticlesFromAPI({
    required String newspaperTitle,
    required String date,
  }) async {
    // TODO: Replace with actual API call
    // final response = await http.get(Uri.parse(
    //   '${ApiConfig.baseUrl}/newspapers/$newspaperTitle/articles?date=$date'
    // ));
    // return (json.decode(response.body) as List)
    //     .map((a) => UploadedArticle.fromFirestore(a))
    //     .toList();

    // Mock implementation
    await Future.delayed(const Duration(seconds: 1));
    return [
      UploadedArticle(
        id: '1',
        title: 'Breaking: Major announcement from state government',
        content: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit...',
        source: newspaperTitle,
        storageUrl: '',
        category: 'News',
        audioUrl: 'https://example.com/audio1.mp3',
        extractedAt: DateTime.now(),
      ),
    ];
  }

  // Example 3: Using in a button tap
  static Widget navigateButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => navigateToArticleList(context),
      icon: const Icon(Icons.article),
      label: const Text('View All Articles'),
    );
  }

  // Example 4: Conditional navigation based on newspaper metadata
  static void navigateWithMetadata(
    BuildContext context,
    Map<String, String> newspaper, {
    List<UploadedArticle>? articles,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleListScreen(
          newspaperTitle: newspaper['title'] ?? 'Unknown',
          newspaperDate: newspaper['date'] ?? 'Today',
          language: newspaper['language'] ?? 'Telugu',
          articles: articles ?? [],
        ),
      ),
    );
  }

  // Example 5: Update home screen to use article list
  static Widget buildArticleRowWithNavigation(
    BuildContext context,
    Map<String, String> item, {
    required List<UploadedArticle> articles,
  }) {
    return InkWell(
      onTap: () => navigateWithMetadata(context, item, articles: articles),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.article_outlined, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item['subtitle'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item['duration'] ?? '0:00',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  // Example 6: Navigation with loading state
  static void navigateWithLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading articles...'),
            ],
          ),
        ),
      ),
    );

    // Simulate API call
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context); // Close loading dialog

      fetchArticlesFromAPI(
        newspaperTitle: 'The Hindu',
        date: '2026-05-23',
      ).then((articles) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArticleListScreen(
              newspaperTitle: 'The Hindu',
              newspaperDate: 'May 23, 2026',
              language: 'Telugu',
              articles: articles,
            ),
          ),
        );
      });
    });
  }

  // Example 7: Error handling
  static void navigateWithErrorHandling(BuildContext context) async {
    try {
      final articles = await fetchArticlesFromAPI(
        newspaperTitle: 'The Hindu',
        date: '2026-05-23',
      );

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleListScreen(
            newspaperTitle: 'The Hindu',
            newspaperDate: 'May 23, 2026',
            language: 'Telugu',
            articles: articles,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading articles: $e')),
      );
    }
  }
}

// Example usage in a widget
class ExampleHomeScreen extends StatelessWidget {
  const ExampleHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GatiVani Home')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () =>
                  ArticleListIntegrationExample.navigateToArticleList(context),
              icon: const Icon(Icons.article),
              label: const Text('View Articles'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () =>
                  ArticleListIntegrationExample.navigateWithLoading(context),
              icon: const Icon(Icons.cloud_download),
              label: const Text('Load with Progress'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => ArticleListIntegrationExample
                  .navigateWithErrorHandling(context),
              icon: const Icon(Icons.error_outline),
              label: const Text('Load with Error Handling'),
            ),
          ),
        ],
      ),
    );
  }
}
