import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/newspaper_article.dart';
import '../models/playlist.dart';

/// User-created playlists — local-only (device-scoped), same
/// SharedPreferences + singleton ChangeNotifier pattern as DownloadsStore
/// and ReactionsStore. See those for why (no per-user auth token wired
/// into requests yet, so nothing here can safely sync per-account).
class PlaylistsStore extends ChangeNotifier {
  PlaylistsStore._();
  static final PlaylistsStore i = PlaylistsStore._();

  static const _prefsKey = 'playlists_v1';
  static final _rand = Random();

  /// Fixed id so ReactionsStore can always find it, even across the rename
  /// the user is free to give it like any other playlist.
  static const likedPlaylistId = 'liked';

  final List<Playlist> _playlists = [];
  bool _loaded = false;

  List<Playlist> get all => List.unmodifiable(_playlists);

  Playlist? byId(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Whether an article is saved to any playlist — playlists store a full
  /// article snapshot, so this means it's kept indefinitely regardless of
  /// the 24h temporary content cache on recent_plays (see
  /// PlaybackService._saveProgress / DocumentService.resolvePlayedArticle).
  bool isInAnyPlaylist(String articleId) =>
      _playlists.any((p) => p.contains(articleId));

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      // No key at all means this device has never had playlists persisted —
      // seed the defaults once. A later empty `[]` (user deleted everything)
      // still has the key, so this never re-seeds after that.
      if (raw == null) {
        _seedDefaults();
        notifyListeners();
        await _save();
        return;
      }
      if (raw.isEmpty) return;
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      _playlists
        ..clear()
        ..addAll(list.map(Playlist.fromJson));
      notifyListeners();
    } catch (_) {}
  }

  void _seedDefaults() {
    final now = DateTime.now();
    _playlists.addAll([
      Playlist(id: _newId(), name: 'My Favorites', createdAt: now),
      Playlist(id: _newId(), name: 'Read Later', createdAt: now),
      Playlist(id: likedPlaylistId, name: 'Liked', createdAt: now),
    ]);
  }

  // 1 << 31 (not 1 << 32): dart2js's `<<` on web doesn't reproduce VM 64-bit
  // shift semantics at the 32-bit boundary, and Random.nextInt rejects the
  // result — throwing here silently killed every create()/rename() call on
  // web with no console trace (no runZonedGuarded in main.dart to surface it).
  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_rand.nextInt(1 << 31)}';

  Future<Playlist> create(String name) async {
    await ensureLoaded();
    final p = Playlist(
        id: _newId(), name: name.trim(), createdAt: DateTime.now());
    _playlists.insert(0, p);
    notifyListeners();
    await _save();
    return p;
  }

  Future<void> rename(String playlistId, String newName) async {
    await ensureLoaded();
    final p = byId(playlistId);
    if (p == null || newName.trim().isEmpty) return;
    p.name = newName.trim();
    notifyListeners();
    await _save();
  }

  Future<void> delete(String playlistId) async {
    await ensureLoaded();
    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
    await _save();
  }

  /// Adds to the front (most-recently-added first); no-op if already present.
  Future<void> addArticle(String playlistId, NewspaperArticle article) async {
    await ensureLoaded();
    final p = byId(playlistId);
    if (p == null || p.contains(article.id)) return;
    p.articles.insert(0, article);
    notifyListeners();
    await _save();
  }

  Future<void> removeArticle(String playlistId, String articleId) async {
    await ensureLoaded();
    final p = byId(playlistId);
    if (p == null) return;
    p.articles.removeWhere((a) => a.id == articleId);
    notifyListeners();
    await _save();
  }

  Future<void> reorder(String playlistId, int oldIndex, int newIndex) async {
    await ensureLoaded();
    final p = byId(playlistId);
    if (p == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = p.articles.removeAt(oldIndex);
    p.articles.insert(newIndex, item);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, json.encode(_playlists.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }
}
