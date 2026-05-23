# GatiVani Monitoring & Observability

Comprehensive guide to monitoring, observability, and alerting for production systems.

## Table of Contents

1. [Overview](#overview)
2. [Firebase Services](#firebase-services)
3. [Error Tracking](#error-tracking)
4. [Performance Monitoring](#performance-monitoring)
5. [Analytics & User Behavior](#analytics--user-behavior)
6. [Dashboards](#dashboards)
7. [Alerting](#alerting)
8. [Incident Response](#incident-response)

---

## Overview

### Monitoring Stack

```
┌─────────────────────────────────────────────┐
│         GatiVani Flutter App                │
├──────────┬──────────┬──────────┬────────────┤
│Crashlytics│Performance│Analytics│ Logging  │
└──────────┴──────────┴──────────┴────────────┘
         │
    Firebase
    Console
         │
    ┌────┴────┐
    │  Slack  │ Notifications
    │ Webhook │
    └─────────┘
```

### Key Metrics

**Availability**
- App crashes/ANR rate
- API response times
- Network error rate

**Performance**
- App launch time
- Page load time
- Frame rate (jank percentage)
- Memory usage
- Battery drain

**Engagement**
- Daily/monthly active users
- Session duration
- Feature usage
- Retention rate
- Conversion rate

---

## Firebase Services

### Firebase Crashlytics

Monitor and fix crashes in real-time.

#### Setup

```dart
// lib/services/firebase_service.dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

Future<void> initializeCrashlytics() async {
  // Pass all uncaught errors to Crashlytics
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
  };

  // Pass all uncaught async exceptions
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack);
    return true;
  };

  // Enable collection in production only
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(kReleaseMode);
}
```

#### Log Errors

```dart
// Automatic - catches uncaught errors
// Manual logging
try {
  riskyOperation();
} catch (e, stackTrace) {
  FirebaseCrashlytics.instance.recordError(
    e,
    stackTrace,
    reason: 'risky_operation_failed',
    fatal: false,
  );
}

// Log custom messages
FirebaseCrashlytics.instance.log('User started article playback');
```

#### Set User Context

```dart
await FirebaseCrashlytics.instance.setUserIdentifier(userId);
await FirebaseCrashlytics.instance.setCustomKey(
  'newspaper_id',
  newspaperId,
);
```

#### Dashboard

Navigate to: Firebase Console → Crashlytics

View:
- Crash overview (count, trend)
- Top crashes by frequency
- Affected devices/versions
- Stack traces
- Custom metadata

### Firebase Analytics

Track user behavior and engagement.

#### Setup

```dart
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final _analytics = FirebaseAnalytics.instance;

  // Track screen views
  static Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  // Track custom events
  static Future<void> logArticleListened({
    required String newspaperId,
    required String articleId,
    required int durationSeconds,
    required double playbackSpeed,
  }) async {
    await _analytics.logEvent(
      name: 'article_listened',
      parameters: {
        'newspaper_id': newspaperId,
        'article_id': articleId,
        'duration_seconds': durationSeconds,
        'playback_speed': playbackSpeed,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // Track user properties
  static Future<void> setUserProperty(String name, String value) async {
    await _analytics.setUserProperty(name: name, value: value);
  }

  // Set user ID
  static Future<void> setUserId(String userId) async {
    await _analytics.setUserId(userId);
  }
}
```

#### Event Tracking

**Key events to track:**

```dart
// App lifecycle
'app_opened'
'app_backgrounded'
'app_closed'

// Newspaper browsing
'newspaper_viewed'
'newspaper_subscribed'
'newspaper_unsubscribed'

// Article interaction
'article_opened'
'article_shared'
'article_bookmarked'
'article_bookmarked_removed'

// Audio playback
'playback_started'
'playback_paused'
'playback_resumed'
'playback_completed'
'playback_speed_changed'

// User actions
'search_performed'
'filter_applied'
'settings_changed'
'notification_opened'

// Errors
'network_error'
'api_error'
'local_error'
```

#### Dashboard

Navigate to: Firebase Console → Analytics → Dashboard

View:
- Active users (real-time)
- User acquisition
- Engagement metrics
- Retention curves
- Custom events
- Conversion funnels

### Firebase Performance Monitoring

Monitor app performance metrics.

#### Setup

```dart
import 'package:firebase_performance/firebase_performance.dart';

class PerformanceService {
  static final _performance = FirebasePerformance.instance;

  // Trace custom operation
  static Future<void> traceArticleLoad(
    String articleId,
    Future<void> Function() operation,
  ) async {
    final trace = _performance.newTrace('article_load');
    await trace.start();
    
    try {
      trace.putAttribute('article_id', articleId);
      await operation();
    } finally {
      await trace.stop();
    }
  }

  // Trace network request
  static Future<void> traceApiCall(
    String endpoint,
    Future<http.Response> Function() request,
  ) async {
    final httpMetric = _performance.newHttpMetric(endpoint, 'GET');
    await httpMetric.start();
    
    try {
      final response = await request();
      httpMetric.responseCode = response.statusCode;
      httpMetric.responsePayloadSize = response.body.length;
    } finally {
      await httpMetric.stop();
    }
  }
}
```

#### Dashboard

Navigate to: Firebase Console → Performance

View:
- App startup time
- Screen rendering time
- Network requests
- Custom traces
- Device/OS breakdown

---

## Error Tracking

### Sentry Integration

Production error tracking with detailed context.

#### Setup

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'YOUR_SENTRY_DSN';
      options.environment = kReleaseMode ? 'production' : 'development';
      
      // Set trace sample rate
      options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
      
      // Attach stack traces
      options.attachStacktrace = true;
      
      // Capture performance
      options.enablePerformanceV2 = true;
    },
    appRunner: () => runApp(const MyApp()),
  );
}
```

#### Capture Exceptions

```dart
try {
  riskyOperation();
} catch (exception, stackTrace) {
  // Capture exception with context
  await Sentry.captureException(
    exception,
    stackTrace: stackTrace,
    withScope: (scope) {
      scope.setTag('operation', 'article_load');
      scope.setContext('article', {'id': articleId});
      scope.setLevel(SentryLevel.error);
    },
  );
}
```

#### Capture Messages

```dart
// Log informational messages
Sentry.captureMessage(
  'Article playback started',
  level: SentryLevel.info,
);
```

#### Dashboard

Navigate to: [sentry.io](https://sentry.io) → Your Project

View:
- Recent errors
- Error trends
- Issue details
- Performance metrics
- User sessions

---

## Performance Monitoring

### App Launch Performance

Track and optimize startup time.

```dart
class LaunchPerformance {
  static final Stopwatch _timer = Stopwatch();

  static void start() {
    _timer.start();
    FirebaseAnalytics.instance.logEvent(name: 'app_launch_start');
  }

  static Future<void> markMilestone(String name) async {
    FirebaseAnalytics.instance.logEvent(
      name: 'app_launch_milestone',
      parameters: {'milestone': name, 'elapsed_ms': _timer.elapsedMilliseconds},
    );
  }

  static Future<void> finish() async {
    _timer.stop();
    final launchTime = _timer.elapsedMilliseconds;
    
    await FirebaseAnalytics.instance.logEvent(
      name: 'app_launch_complete',
      parameters: {'launch_time_ms': launchTime},
    );

    if (launchTime > 3000) {
      // Alert if launch takes > 3 seconds
      await Sentry.captureMessage(
        'Slow app launch: ${launchTime}ms',
        level: SentryLevel.warning,
      );
    }
  }
}
```

### Network Performance

Monitor API response times.

```dart
class NetworkMonitor {
  static Future<T> trackRequest<T>({
    required String endpoint,
    required Future<T> Function() request,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final response = await request();
      
      final duration = stopwatch.elapsedMilliseconds;
      
      // Log performance
      if (duration > 3000) {
        Sentry.captureMessage(
          'Slow API request: $endpoint (${duration}ms)',
          level: SentryLevel.warning,
        );
      }
      
      return response;
    } finally {
      stopwatch.stop();
    }
  }
}
```

### Memory & Battery

Monitor resource usage.

```dart
import 'package:device_info_plus/device_info_plus.dart';

class ResourceMonitor {
  // Monitor memory usage
  static Future<void> checkMemory() async {
    // Use ProcessInfo or similar to check memory
    // Alert if usage is excessive
  }

  // Monitor battery drain
  static Future<void> checkBattery() async {
    // Check if heavy operations are draining battery
  }
}
```

---

## Analytics & User Behavior

### Funnel Analysis

Track user journey through key steps.

```dart
// User signup funnel
'signup_started' → 'signup_email_entered' → 'signup_verified' → 'signup_completed'

// Article listening funnel
'newspaper_opened' → 'article_preview_shown' → 'playback_started' → 'playback_completed'

// Subscription funnel
'subscription_modal_shown' → 'subscription_plan_viewed' → 'subscription_purchased'
```

### Cohort Analysis

Group users and track behavior.

```dart
// Create cohorts
- New users (signed up this week)
- Active users (played article in last 7 days)
- Churned users (no activity in 30 days)

// Track retention by cohort
- Day 1 retention: % returning on day 1
- Day 7 retention: % returning on day 7
- Day 30 retention: % returning on day 30
```

### Custom Events

Define business-critical events.

```dart
FirebaseAnalytics.instance.logEvent(
  name: 'newspaper_preference_changed',
  parameters: {
    'user_id': userId,
    'old_preference': oldNewspaperId,
    'new_preference': newNewspaperId,
    'timestamp': DateTime.now().toIso8601String(),
  },
);
```

---

## Dashboards

### Firebase Dashboard

**Setup custom dashboard:**

1. Firebase Console → Dashboard
2. Add cards for key metrics:
   - Active users (realtime)
   - Crash-free users %
   - Top crashes
   - User retention
   - Custom event rates

### Grafana Dashboard

**For advanced monitoring:**

1. Connect Firestore/Realtime Database to Grafana
2. Create panels for:
   - Error rates over time
   - Response time percentiles (p50, p95, p99)
   - User growth
   - Feature adoption
   - Revenue metrics (if applicable)

### Slack Integration

**Post metrics to Slack daily:**

```python
import requests

def post_daily_metrics():
    metrics = {
        'active_users_24h': 5234,
        'crash_free_users': '99.8%',
        'avg_session_duration': '4m 32s',
        'new_users': 342,
    }
    
    slack_message = {
        'text': 'Daily Metrics Report',
        'blocks': [
            {'type': 'section', 'text': {'type': 'mrkdwn', 'text': f"*Active Users:* {metrics['active_users_24h']}"}},
            {'type': 'section', 'text': {'type': 'mrkdwn', 'text': f"*Crash Free:* {metrics['crash_free_users']}"}},
        ]
    }
    
    requests.post(SLACK_WEBHOOK, json=slack_message)

# Schedule daily at 9 AM
schedule.every().day.at("09:00").do(post_daily_metrics)
```

---

## Alerting

### Alert Rules

**Critical (immediate notification):**
- Crash rate > 1%
- App ANR rate > 0.5%
- API error rate > 5%
- Downtime/unavailability

**Warning (daily digest):**
- Crash rate > 0.5% and < 1%
- API error rate > 2% and < 5%
- Performance degradation
- Unusual user behavior

### Slack Alerts

```yaml
# Example alert configuration
alerts:
  - name: "High Crash Rate"
    condition: "crash_rate > 0.01"
    action: "post_to_slack"
    severity: "critical"
    
  - name: "Slow API Response"
    condition: "p99_response_time > 3000"
    action: "post_to_slack"
    severity: "warning"
    
  - name: "Low Retention"
    condition: "day_1_retention < 0.30"
    action: "post_to_slack"
    severity: "info"
```

### Email Alerts

Configure in Firebase/Sentry settings:
- Critical errors → Team Slack
- Crash spikes → Email
- Performance degradation → Slack

---

## Incident Response

### On-Call Process

**On-Call Responsibilities:**
- Monitor Slack/email for critical alerts
- Respond to incidents within 15 minutes
- Investigate root cause
- Communicate status updates
- Document incident
- Post-mortem within 24 hours

### Incident Playbook

**High Crash Rate (> 1%)**

```
1. Alert triggered
   ↓
2. Check Crashlytics for crash details
   ↓
3. Identify affected app version/device
   ↓
4. Determine severity:
   - Critical: > 5% or blocking feature
   - High: 1-5% or major feature affected
   - Medium: 0.5-1% or minor feature
   ↓
5. Notify team on Slack
   ↓
6. Prepare hotfix if critical
   ↓
7. Test hotfix on staging
   ↓
8. Deploy to production
   ↓
9. Monitor crash rate
   ↓
10. Post-mortem within 24 hours
```

**API Errors > 5%**

```
1. Check API service status
2. Review error logs
3. Check database performance
4. Scale API if needed
5. Investigate root cause
6. Implement fix
7. Monitor error rate
8. Document lesson learned
```

### Post-Incident Review

**Template:**

```markdown
# Incident Report: [Title]

## Timeline
- HH:MM - Issue detected
- HH:MM - Alert fired
- HH:MM - Team notified
- HH:MM - Root cause identified
- HH:MM - Fix deployed
- HH:MM - Resolved

## Impact
- Duration: X minutes
- Users affected: X
- Features affected: [List]
- Severity: [Critical/High/Medium/Low]

## Root Cause
[Description]

## Resolution
[What was done to fix]

## Prevention
[What will prevent this in future]

## Action Items
- [ ] Item 1 (@Owner)
- [ ] Item 2 (@Owner)
```

---

## Dashboards Setup

### Real-time Dashboard

Display during business hours:
- Active users now
- Last hour's errors
- API status
- Current app version distribution
- Server health

### Daily Summary Report

Sent at 9 AM:
```
GatiVani Daily Metrics
Yesterday (2024-05-09)

📊 User Metrics
  Active Users: 12,450 (+5%)
  New Users: 342
  Day-1 Retention: 65%
  Avg Session: 4m 32s

🔴 Stability
  Crash-Free Users: 99.8%
  Crashes: 12 (0.1%)
  ANRs: 2 (0.02%)

⚡ Performance
  App Launch: 890ms (avg)
  API Response: 245ms (p95)
  Network Errors: 0.8%

📈 Features
  Articles Listened: 45,230
  Playback Resumed: 2,340
  Bookmarks Saved: 1,230
```

---

## References

- [Firebase Console](https://console.firebase.google.com)
- [Sentry Documentation](https://docs.sentry.io)
- [Firebase Crashlytics](https://firebase.google.com/docs/crashlytics)
- [Firebase Performance](https://firebase.google.com/docs/perf-mod)

