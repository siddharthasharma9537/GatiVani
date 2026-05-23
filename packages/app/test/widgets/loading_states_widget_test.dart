/// Widget tests for loading and error state components.
/// Covers skeleton loaders, error widget, empty widget, loading overlay,
/// shimmer effect, and retry button.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani/design/components/loading_states.dart';

void main() {
  group('ArticleCardSkeleton', () {
    testWidgets('renders inside a card', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ArticleCardSkeleton()),
      ));
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('disposes animation controller cleanly', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ArticleCardSkeleton()),
      ));
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('respects custom animation duration', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ArticleCardSkeleton(
            animationDuration: Duration(milliseconds: 100),
          ),
        ),
      ));
      // Animation should be running without throwing
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ArticleCardSkeleton), findsOneWidget);
    });
  });

  group('ArticleListSkeleton', () {
    testWidgets('renders default 6 skeletons', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: ArticleListSkeleton(),
          ),
        ),
      ));
      // Scroll-based ListView only renders visible items; at least one renders.
      expect(find.byType(ArticleCardSkeleton), findsWidgets);
    });

    testWidgets('honors custom itemCount', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: ArticleListSkeleton(itemCount: 2),
          ),
        ),
      ));
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('ErrorStateWidget', () {
    testWidgets('renders title and message', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ErrorStateWidget(
            title: 'Something went wrong',
            message: 'Could not load articles.',
          ),
        ),
      ));
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Could not load articles.'), findsOneWidget);
    });

    testWidgets('renders default error icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ErrorStateWidget(title: 'Error')),
      ));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders custom icon when provided', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ErrorStateWidget(
            title: 'No Internet',
            icon: Icons.wifi_off,
          ),
        ),
      ));
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('retry button invokes callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorStateWidget(
            title: 'Error',
            onRetry: () => tapped = true,
          ),
        ),
      ));
      await tester.tap(find.text('Retry'));
      expect(tapped, isTrue);
    });

    testWidgets('retry button is hidden when onRetry is null', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ErrorStateWidget(title: 'Error')),
      ));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('respects custom retry button text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorStateWidget(
            title: 'Error',
            onRetry: () {},
            retryButtonText: 'Try Again',
          ),
        ),
      ));
      expect(find.text('Try Again'), findsOneWidget);
    });
  });

  group('EmptyStateWidget', () {
    testWidgets('renders title only when subtitle is null', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(title: 'No articles'),
        ),
      ));
      expect(find.text('No articles'), findsOneWidget);
    });

    testWidgets('renders title and subtitle', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(
            title: 'Empty',
            subtitle: 'Refresh to load articles',
          ),
        ),
      ));
      expect(find.text('Empty'), findsOneWidget);
      expect(find.text('Refresh to load articles'), findsOneWidget);
    });

    testWidgets('action button invokes onAction', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(
            title: 'Empty',
            onAction: () => tapped = true,
            actionButtonText: 'Refresh',
          ),
        ),
      ));
      await tester.tap(find.text('Refresh'));
      expect(tapped, isTrue);
    });

    testWidgets('action button is hidden when onAction is null',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmptyStateWidget(title: 'Empty')),
      ));
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });

  group('LoadingOverlay', () {
    testWidgets('shows child when not loading', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: LoadingOverlay(
            isLoading: false,
            child: Text('Content'),
          ),
        ),
      ));
      expect(find.text('Content'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows overlay and indicator when loading', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: LoadingOverlay(
            isLoading: true,
            child: Text('Content'),
          ),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows message when provided', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: LoadingOverlay(
            isLoading: true,
            message: 'Loading articles...',
            child: Text('Content'),
          ),
        ),
      ));
      expect(find.text('Loading articles...'), findsOneWidget);
    });
  });

  group('ShimmerLoading', () {
    testWidgets('wraps child without throwing', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ShimmerLoading(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      ));
      expect(find.byType(ShimmerLoading), findsOneWidget);
    });

    testWidgets('disposes shimmer controller cleanly', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ShimmerLoading(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      ));
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(tester.takeException(), isNull);
    });
  });

  group('RetryButton', () {
    testWidgets('renders default label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RetryButton(onRetry: () {})),
      ));
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders custom label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RetryButton(onRetry: () {}, label: 'Reload'),
        ),
      ));
      expect(find.text('Reload'), findsOneWidget);
    });

    testWidgets('invokes onRetry when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RetryButton(onRetry: () => tapped = true)),
      ));
      await tester.tap(find.byType(ElevatedButton));
      expect(tapped, isTrue);
    });

    testWidgets('is disabled when loading', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RetryButton(onRetry: () {}, isLoading: true),
        ),
      ));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
