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

  // ── Getters ─────────────────────────────────────────────────────────────────
  String get defaultVoice => _defaultVoice;
  ThemeMode get themeMode => _themeMode;
  double get playbackSpeed => _playbackSpeed;

  // ── Setters ─────────────────────────────────────────────────────────────────
  void setDefaultVoice(String v) {
    if (_defaultVoice == v) return;
    _defaultVoice = v;
    notifyListeners();
    _save();
  }

  void setThemeMode(ThemeMode m) {
    if (_themeMode == m) return;
    _themeMode = m;
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
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_filename');
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _defaultVoice = json['defaultVoice'] as String? ?? _defaultVoice;
      _themeMode = _themeFromString(json['themeMode'] as String?);
      _playbackSpeed = (json['playbackSpeed'] as num?)?.toDouble() ?? _playbackSpeed;
    } catch (_) {}
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
