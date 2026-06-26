import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// App-wide user settings, persisted as JSON to ApplicationDocumentsDirectory.
/// On web, settings are kept in-memory only.
class SettingsProvider extends ChangeNotifier {
  // ── Defaults ────────────────────────────────────────────────────────────────
  String _defaultVoice = 'priya';
  ThemeMode _themeMode = ThemeMode.system;
  double _playbackSpeed = 1.0;
  // UI language: 'en' (default) | 'te'. Controls all app chrome — header,
  // tiles, chips, masthead, menu. Article content is always Telugu.
  String _lang = 'en';

  // ── Getters ─────────────────────────────────────────────────────────────────
  String get defaultVoice => _defaultVoice;
  ThemeMode get themeMode => _themeMode;
  double get playbackSpeed => _playbackSpeed;
  String get lang => _lang;
  bool get isTelugu => _lang == 'te';

  // ── "Auto" theme: light by day, dark at night ──────────────────────────────
  // ThemeMode.system is repurposed as a daylight-driven auto mode (a fixed local
  // clock window, no location needed): light during the day, dark after.
  static const int _dayStartHour = 6; // 6:00 → switch to light
  static const int _dayEndHour = 18; // 18:00 → switch to dark
  Timer? _daylightTimer;

  bool get isDaylightNow {
    final h = DateTime.now().hour;
    return h >= _dayStartHour && h < _dayEndHour;
  }

  /// What the app should actually render. In auto (system) mode this resolves to
  /// light/dark by time of day; otherwise it's the explicit choice.
  ThemeMode get effectiveThemeMode => _themeMode == ThemeMode.system
      ? (isDaylightNow ? ThemeMode.light : ThemeMode.dark)
      : _themeMode;

  // Flip the theme live when the day/night boundary passes (no app restart).
  void _scheduleDaylightFlip() {
    _daylightTimer?.cancel();
    if (_themeMode != ThemeMode.system) return;
    final now = DateTime.now();
    final next = [
      DateTime(now.year, now.month, now.day, _dayStartHour),
      DateTime(now.year, now.month, now.day, _dayEndHour),
      DateTime(now.year, now.month, now.day + 1, _dayStartHour),
    ].firstWhere((d) => d.isAfter(now));
    _daylightTimer = Timer(next.difference(now), () {
      notifyListeners();
      _scheduleDaylightFlip();
    });
  }

  // ── Setters ─────────────────────────────────────────────────────────────────
  void setLanguage(String l) {
    if (_lang == l || (l != 'en' && l != 'te')) return;
    _lang = l;
    notifyListeners();
    _save();
  }

  void toggleLanguage() => setLanguage(_lang == 'en' ? 'te' : 'en');

  void setDefaultVoice(String v) {
    if (_defaultVoice == v) return;
    _defaultVoice = v;
    notifyListeners();
    _save();
  }

  void setThemeMode(ThemeMode m) {
    if (_themeMode == m) return;
    _themeMode = m;
    _scheduleDaylightFlip(); // (re)arm or cancel the day/night flip
    notifyListeners();
    _save();
  }

  void setPlaybackSpeed(double s) {
    if (_playbackSpeed == s) return;
    _playbackSpeed = s;
    notifyListeners();
    _save();
  }

  // ── Persistence ──────────────────────────────────────────────────────────────
  static const _filename = 'gativani_settings.json';

  Future<void> load() async {
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_filename');
        if (await file.exists()) {
          final json =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          _defaultVoice = json['defaultVoice'] as String? ?? _defaultVoice;
          _themeMode = _themeFromString(json['themeMode'] as String?);
          _playbackSpeed =
              (json['playbackSpeed'] as num?)?.toDouble() ?? _playbackSpeed;
          _lang = json['lang'] as String? ?? _lang;
        }
      } catch (_) {}
    }
    // Arm the day/night flip for the resolved mode (also runs on web).
    _scheduleDaylightFlip();
  }

  Future<void> _save() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_filename');
      await file.writeAsString(jsonEncode({
        'defaultVoice': _defaultVoice,
        'themeMode': _themeToString(_themeMode),
        'playbackSpeed': _playbackSpeed,
        'lang': _lang,
      }));
    } catch (_) {}
  }

  // ── Downloads storage helpers ────────────────────────────────────────────────
  Future<({int fileCount, int bytes})> downloadStats() async {
    if (kIsWeb) return (fileCount: 0, bytes: 0);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${dir.path}/gativani_audio');
      if (!await audioDir.exists()) return (fileCount: 0, bytes: 0);
      final files = await audioDir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final total = await files.fold<Future<int>>(
        Future.value(0),
        (acc, f) async => (await acc) + (await f.length()),
      );
      return (fileCount: files.length, bytes: total);
    } catch (_) {
      return (fileCount: 0, bytes: 0);
    }
  }

  Future<void> clearDownloads() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${dir.path}/gativani_audio');
      if (await audioDir.exists()) await audioDir.delete(recursive: true);
    } catch (_) {}
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  ThemeMode _themeFromString(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  String _themeToString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      };
}
