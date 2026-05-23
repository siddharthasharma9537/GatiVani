/// Common test fixtures and test data generators for all services
class ServiceFixtures {
  /// Sample audio URLs for testing
  static const List<String> sampleAudioUrls = [
    'https://audio.example.com/article1.mp3',
    'https://audio.example.com/article2.mp3',
    'https://audio.example.com/article3.mp3',
  ];

  /// Sample image URLs for testing
  static const List<String> sampleImageUrls = [
    'https://images.example.com/article1.jpg',
    'https://images.example.com/article2.jpg',
    'https://images.example.com/article3.jpg',
  ];

  /// Sample error messages for various scenarios
  static const Map<String, String> errorMessages = {
    'network': 'Network connection failed',
    'timeout': 'Request timed out',
    'authentication': 'Authentication failed',
    'notFound': 'Resource not found',
    'serverError': 'Internal server error',
    'invalidInput': 'Invalid input provided',
    'quotaExceeded': 'API quota exceeded',
    'rateLimited': 'Too many requests',
  };

  /// Standard HTTP status codes for testing error handling
  static const Map<int, String> httpStatusCodes = {
    200: 'OK',
    201: 'Created',
    204: 'No Content',
    400: 'Bad Request',
    401: 'Unauthorized',
    403: 'Forbidden',
    404: 'Not Found',
    429: 'Too Many Requests',
    500: 'Internal Server Error',
    502: 'Bad Gateway',
    503: 'Service Unavailable',
    504: 'Gateway Timeout',
  };

  /// Mock API response structures
  static const Map<String, dynamic> mockApiResponses = {
    'ttsSuccess': {
      'status': 'success',
      'audios': [
        {
          'audioContent': 'https://audio.example.com/output.mp3',
          'duration': 120,
        }
      ],
    },
    'ocrSuccess': {
      'status': 'success',
      'result': {
        'text': 'Extracted text from image',
        'confidence': 0.95,
      },
    },
    'summarizeSuccess': {
      'status': 'success',
      'text': 'This is a summary of the article.',
    },
  };

  /// Generate test data structures
  static Map<String, dynamic> generateTTSResponse({
    required String audioUrl,
    int duration = 120,
  }) {
    return {
      'status': 'success',
      'audios': [
        {
          'audioContent': audioUrl,
          'duration': duration,
        }
      ],
    };
  }

  static Map<String, dynamic> generateOCRResponse({
    required String text,
    double confidence = 0.95,
  }) {
    return {
      'status': 'success',
      'result': {
        'text': text,
        'confidence': confidence,
      },
    };
  }

  /// Test data for concurrent operation stress testing
  static List<String> generateBatchTexts(int count, {String prefix = 'Text'}) {
    return List.generate(count, (i) => '$prefix $i');
  }

  /// Performance benchmark reference values
  static const Map<String, int> performanceBenchmarks = {
    'ocrProcessing': 3000, // ms
    'ttsGeneration': 5000, // ms
    'summarization': 5000, // ms
    'batchProcessing': 10000, // ms
  };

  /// Cache key patterns for testing
  static const Map<String, String> cacheKeyPatterns = {
    'article': 'article_{id}',
    'audio': 'audio_{articleId}_{language}',
    'summary': 'summary_{articleId}_{language}',
    'metadata': 'metadata_{resourceId}',
  };

  /// Language codes for i18n testing
  static const Map<String, String> supportedLanguages = {
    'te': 'Telugu',
    'en': 'English',
    'hi': 'Hindi',
  };

  /// Test file paths (non-existent, for unit testing)
  static const Map<String, String> testFilePaths = {
    'audio': '/tmp/test_audio.mp3',
    'image': '/tmp/test_image.jpg',
    'document': '/tmp/test_document.pdf',
    'deepPath': '/tmp/nested/path/to/file.mp3',
  };

  /// Timeout values for different operations
  static const Map<String, Duration> operationTimeouts = {
    'network': Duration(seconds: 30),
    'file': Duration(seconds: 60),
    'ai': Duration(seconds: 45),
    'batch': Duration(minutes: 2),
  };

  /// Database transaction scenarios
  static const List<String> transactionScenarios = [
    'successful_commit',
    'successful_rollback',
    'concurrent_updates',
    'deadlock_recovery',
    'timeout_handling',
  ];

  /// Test event names for analytics
  static const List<String> analyticsEventNames = [
    'app_launched',
    'article_viewed',
    'article_shared',
    'audio_played',
    'audio_downloaded',
    'search_performed',
    'settings_changed',
    'error_occurred',
  ];

  /// Mock user preferences
  static const Map<String, dynamic> defaultUserPreferences = {
    'language': 'te',
    'autoPlayAudio': true,
    'audioSpeed': 1.0,
    'cacheEnabled': true,
    'analyticsEnabled': true,
    'notificationsEnabled': true,
    'darkModeEnabled': false,
  };

  /// Test notification payloads
  static const Map<String, dynamic> testNotificationPayloads = {
    'article': {
      'title': 'New Article Published',
      'body': 'Check out this breaking news',
      'source': 'Andhra Jyothi',
      'timestamp': 1234567890,
    },
    'reminder': {
      'title': 'Daily News Reminder',
      'body': 'Don\'t miss today\'s important updates',
      'type': 'daily_reminder',
    },
  };

  /// Response time expectations (in milliseconds)
  static const Map<String, int> expectedResponseTimes = {
    'instantaneous': 100,
    'fast': 500,
    'moderate': 2000,
    'slow': 5000,
    'verySlow': 10000,
  };

  /// Memory usage constraints
  static const Map<String, int> memoryConstraints = {
    'cacheSize': 100 * 1024 * 1024, // 100 MB
    'maxArticles': 1000,
    'maxAudioFiles': 50,
  };

  /// Batch operation sizes for stress testing
  static const Map<String, int> batchOperationSizes = {
    'small': 10,
    'medium': 50,
    'large': 100,
    'veryLarge': 500,
  };

  /// Error recovery retry configurations
  static const Map<String, int> retryConfigurations = {
    'maxRetries': 3,
    'initialDelay': 1000, // ms
    'maxDelay': 10000, // ms
    'backoffMultiplier': 2,
  };

  /// Test data cleanup intervals
  static const Map<String, Duration> cleanupIntervals = {
    'cache': Duration(minutes: 30),
    'logs': Duration(days: 7),
    'temp': Duration(days: 1),
    'analytics': Duration(days: 30),
  };

  /// Simulate various network conditions
  static const Map<String, int> networkConditions = {
    '4g': 20, // Mbps
    '3g': 2, // Mbps
    'wifi': 100, // Mbps
    'slow': 0.5, // Mbps
  };

  /// Create realistic delays based on network conditions
  static Duration getNetworkDelay(int speed, int sizeInBytes) {
    final delayMs = (sizeInBytes / (speed * 1024 * 1024)) * 8 * 1000;
    return Duration(milliseconds: delayMs.toInt());
  }

  /// Generate random test data
  static String generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(chars[DateTime.now().millisecond % chars.length]);
    }
    return buffer.toString();
  }

  /// Generate random numeric ID
  static int generateRandomId() {
    return DateTime.now().millisecondsSinceEpoch % 1000000;
  }

  /// Verify mock response structure
  static bool isValidMockResponse(Map<String, dynamic> response) {
    return response.containsKey('status') &&
        response.containsKey('data') ||
        response.containsKey('error');
  }
}
