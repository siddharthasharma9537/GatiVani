import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // Home district (English key into kDistricts), null = no preference.
  // Biases Live stories and surfaces the edition's district news.
  String? _district;
  // News Language: which language the Live feed's CONTENT is sourced/narrated
  // in ('te' | 'hi') — distinct from `_lang`, which only switches UI chrome.
  String _newsLanguage = 'te';
  // Feed ordering/filter shared by the Live and Paper lists (session-only,
  // set from the filter dropdown or by Vāni acting on a location query):
  // sort 'location' pins district-matching stories first; districtOnly
  // hides everything else.
  String _feedSort = 'location'; // 'location' | 'latest'
  bool _districtOnly = false;
  // Personal alerts: topic ids from kAlertTopics the user watches (exam
  // results, govt job notifications…), and when they last opened the Alerts
  // screen — anything newer counts as unread for the menu badge.
  Set<String> _alertTopics = {};
  DateTime? _alertsSeenAt;

  // ── Getters ─────────────────────────────────────────────────────────────────
  String get defaultVoice => _defaultVoice;
  ThemeMode get themeMode => _themeMode;
  double get playbackSpeed => _playbackSpeed;
  String get lang => _lang;
  bool get isTelugu => _lang == 'te';
  String? get district => _district;
  String get newsLanguage => _newsLanguage;
  String get feedSort => _feedSort;
  bool get districtOnly => _districtOnly;
  Set<String> get alertTopics => Set.unmodifiable(_alertTopics);
  DateTime? get alertsSeenAt => _alertsSeenAt;

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

  /// null clears the preference.
  void setDistrict(String? d) {
    if (_district == d) return;
    _district = (d == null || d.isEmpty) ? null : d;
    if (_district == null) _districtOnly = false;
    notifyListeners();
    _save();
  }

  void setNewsLanguage(String l) {
    if (_newsLanguage == l || (l != 'te' && l != 'hi')) return;
    _newsLanguage = l;
    notifyListeners();
    _save();
  }

  void setFeedSort(String s) {
    if (_feedSort == s || (s != 'location' && s != 'latest')) return;
    _feedSort = s;
    notifyListeners();
  }

  void setDistrictOnly(bool v) {
    if (_districtOnly == v) return;
    _districtOnly = v;
    notifyListeners();
  }

  void toggleAlertTopic(String id) {
    _alertTopics.contains(id)
        ? _alertTopics.remove(id)
        : _alertTopics.add(id);
    notifyListeners();
    _save();
  }

  /// Everything currently shown has been seen — clears the menu badge.
  void markAlertsSeen() {
    _alertsSeenAt = DateTime.now();
    notifyListeners();
    _save();
  }

  // ── Persistence ──────────────────────────────────────────────────────────────
  // SharedPreferences is cross-platform: localStorage on web, native key-value
  // store on iOS/Android — so settings persist everywhere with one code path
  // (web used to be in-memory only, which reset theme/language every reload).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _defaultVoice = prefs.getString('defaultVoice') ?? _defaultVoice;
      _themeMode = _themeFromString(prefs.getString('themeMode'));
      _playbackSpeed = prefs.getDouble('playbackSpeed') ?? _playbackSpeed;
      _lang = prefs.getString('lang') ?? _lang;
      final d = prefs.getString('district');
      _district = (d == null || d.isEmpty) ? null : d;
      _newsLanguage = prefs.getString('newsLanguage') ?? _newsLanguage;
      _alertTopics = (prefs.getStringList('alertTopics') ?? []).toSet();
      final seen = prefs.getString('alertsSeenAt');
      _alertsSeenAt = seen == null ? null : DateTime.tryParse(seen);
    } catch (_) {}
    // Arm the day/night flip for the resolved mode.
    _scheduleDaylightFlip();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('defaultVoice', _defaultVoice);
      await prefs.setString('themeMode', _themeToString(_themeMode));
      await prefs.setDouble('playbackSpeed', _playbackSpeed);
      await prefs.setString('lang', _lang);
      await prefs.setString('district', _district ?? '');
      await prefs.setString('newsLanguage', _newsLanguage);
      await prefs.setStringList('alertTopics', _alertTopics.toList());
      await prefs.setString(
          'alertsSeenAt', _alertsSeenAt?.toIso8601String() ?? '');
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
