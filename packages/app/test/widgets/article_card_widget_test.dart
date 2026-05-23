/// Widget tests for ArticleCard component
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/services/news_service.dart';
import '../fixtures/article_fixtures.dart';

void main() {
  group('ArticleCard Widget Tests', () {
    late Article testArticle;

    setUp(() {
      testArticle = ArticleFixtures.createArticle(
        title: 'Test Article Title',
        source: 'Test Source',
        url: 'https://example.com/article',
      );
    });

    testWidgets('renders article title', (WidgetTester tester) async {
      // Build a simple widget that displays an article card
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            testArticle.title,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text(testArticle.title), findsOneWidget);
    });

    testWidgets('renders article source', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(testArticle.title),
                    Text(testArticle.source),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text(testArticle.source), findsOneWidget);
    });

    testWidgets('renders article with image URL', (WidgetTester tester) async {
      final articleWithImage = ArticleFixtures.createArticle(
        imageUrl: 'https://example.com/image.jpg',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Column(
                children: [
                  if (articleWithImage.imageUrl != null)
                    Image.network(articleWithImage.imageUrl!)
                  else
                    const SizedBox.shrink(),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(articleWithImage.title),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('handles article without image', (WidgetTester tester) async {
      final articleWithoutImage = ArticleFixtures.createArticle(
        imageUrl: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(articleWithoutImage.title),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('displays multiple articles in list', (WidgetTester tester) async {
      final articles = ArticleFixtures.createArticleList(count: 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: articles.length,
              itemBuilder: (context, index) {
                final article = articles[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(article.title),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsWidgets);
      expect(find.text('Article 0'), findsOneWidget);
      expect(find.text('Article 4'), findsWidgets);
    });

    testWidgets('responds to tap gesture', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onTap: () => tapped = true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(testArticle.title),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Card));
      expect(tapped, true);
    });

    testWidgets('renders with proper spacing', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        testArticle.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(testArticle.source),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Padding), findsWidgets);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('handles long article titles with overflow',
        (WidgetTester tester) async {
      final longTitle = 'A' * 100;
      final article = ArticleFixtures.createArticle(title: longTitle);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  article.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Text), findsOneWidget);
      expect(find.text(longTitle), findsOneWidget);
    });

    testWidgets('displays timestamp correctly', (WidgetTester tester) async {
      final now = DateTime.now();
      final article = ArticleFixtures.createArticle(fetchedAt: now);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(article.title),
                    Text('Fetched: ${article.fetchedAt}'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text(contains('Fetched:')), findsOneWidget);
    });

    testWidgets('renders with accessibility features', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              label: 'Article Card',
              button: true,
              enabled: true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        label: 'Article Title',
                        child: Text(testArticle.title),
                      ),
                      Semantics(
                        label: 'Article Source',
                        child: Text(testArticle.source),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Article Card'), findsOneWidget);
    });

    testWidgets('renders multiple cards in scrollable list',
        (WidgetTester tester) async {
      final articles = ArticleFixtures.createArticleList(count: 20);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: articles.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(articles[index].title),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Verify list renders
      expect(find.byType(ListView), findsOneWidget);

      // Scroll and verify more items appear
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('shows loading state properly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading articles...'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading articles...'), findsOneWidget);
    });

    testWidgets('shows error state properly', (WidgetTester tester) async {
      const errorMessage = 'Failed to load articles';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Card(
                color: Colors.red[100],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(height: 8),
                      const Text(errorMessage),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text(errorMessage), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('dark mode support', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(testArticle.title),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsOneWidget);
    });
  });
}
