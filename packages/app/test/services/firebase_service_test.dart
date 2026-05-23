/// Unit tests for FirebaseService
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:gativani/services/firebase_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../mocks/mock_services.dart';

void main() {
  group('FirebaseService', () {
    // Note: Full Firebase initialization requires Firebase emulator setup
    // These tests demonstrate the test structure and mocking strategy

    test('singleton pattern returns same instance', () {
      final service1 = FirebaseService();
      final service2 = FirebaseService();
      expect(identical(service1, service2), true);
    });

    group('Analytics', () {
      late FakeFirebaseService service;

      setUp(() {
        service = FakeFirebaseService();
      });

      test('logEvent records event name', () async {
        await service.logEvent('test_event');
        expect(service.loggedEvents.contains('test_event'), true);
      });

      test('logEvent with parameters records event', () async {
        await service.logEvent(
          'article_viewed',
          parameters: {'source': 'test', 'article_id': '123'},
        );
        expect(service.loggedEvents.contains('article_viewed'), true);
      });

      test('logEvent handles multiple events', () async {
        await service.logEvent('event1');
        await service.logEvent('event2');
        await service.logEvent('event3');
        expect(service.loggedEvents.length, 3);
      });

      test('logScreenView records screen name', () async {
        await service.logScreenView('home_screen');
        expect(service.loggedScreens.contains('home_screen'), true);
      });

      test('logScreenView handles multiple screens', () async {
        await service.logScreenView('screen1');
        await service.logScreenView('screen2');
        await service.logScreenView('screen3');
        expect(service.loggedScreens.length, 3);
      });
    });

    group('FCM Token', () {
      late FakeFirebaseService service;

      setUp(() {
        service = FakeFirebaseService();
      });

      test('getFCMToken returns non-null token', () async {
        service.initialize();
        final token = await service.getFCMToken();
        expect(token, isNotNull);
        expect(token, isNotEmpty);
      });

      test('getFCMToken returns valid token format', () async {
        service.initialize();
        final token = await service.getFCMToken();
        expect(token, isA<String>());
        expect(token!.length, greaterThan(0));
      });
    });

    group('Initialization', () {
      test('initialize sets initialized flag', () async {
        final service = FakeFirebaseService();
        expect(service.initialized, false);
        await service.initialize();
        expect(service.initialized, true);
      });
    });

    group('Error Handling', () {
      test('Firebase initialization exception has proper message', () {
        final exception = FirebaseInitializationException('Test error');
        expect(exception.message, equals('Test error'));
        expect(exception.toString(), contains('FirebaseInitializationException'));
      });

      test('Firebase initialization exception is Exception', () {
        final exception = FirebaseInitializationException('Test error');
        expect(exception, isA<Exception>());
      });
    });

    group('Mock Service Integration', () {
      late MockFirebaseService mockService;

      setUp(() {
        mockService = MockFirebaseService();
      });

      test('mock service can be initialized', () async {
        await mockService.initialize();
        verify(mockService.initialize).called(1);
      });

      test('mock service logEvent can be called multiple times', () async {
        await mockService.logEvent('event1');
        await mockService.logEvent('event2');
        verify(mockService.logEvent('event1')).called(1);
        verify(mockService.logEvent('event2')).called(1);
      });

      test('mock service getFCMToken returns test token', () async {
        final token = await mockService.getFCMToken();
        expect(token, equals('test-fcm-token'));
      });

      test('mock service logScreenView can be called', () async {
        await mockService.logScreenView('test_screen');
        verify(mockService.logScreenView('test_screen')).called(1);
      });
    });

    group('Analytics State Management', () {
      late FakeFirebaseService service;

      setUp(() {
        service = FakeFirebaseService();
      });

      test('clear event logs for fresh state', () async {
        await service.logEvent('event1');
        await service.logEvent('event2');
        service.loggedEvents.clear();
        expect(service.loggedEvents.isEmpty, true);
      });

      test('event logs maintain order', () async {
        await service.logEvent('first');
        await service.logEvent('second');
        await service.logEvent('third');
        expect(
          service.loggedEvents,
          equals(['first', 'second', 'third']),
        );
      });
    });

    group('Exception Handling', () {
      test('FirebaseInitializationException with empty message', () {
        final exception = FirebaseInitializationException('');
        expect(exception.message, isEmpty);
      });

      test('FirebaseInitializationException with long message', () {
        final longMessage = 'x' * 1000;
        final exception = FirebaseInitializationException(longMessage);
        expect(exception.message.length, equals(1000));
      });

      test('FirebaseInitializationException with special characters', () {
        final exception = FirebaseInitializationException('Error: @#\$%');
        expect(exception.message, contains('@'));
        expect(exception.message, contains('#'));
      });
    });
  });
}
