import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/newspaper_article.dart';

enum ReactionKind { like, dislike }

/// One reaction: which way, plus a light snapshot of the article (title/
/// category/etc.) so "Liked stories" can render in For You even when the
/// original article isn't loaded in memory anymore — same reasoning as
/// DownloadsStore keeping a full record instead of just an id.
class ReactionRecord {
  ReactionRecord(
      {required this.article, required this.kind, required this.reactedAt});

  final NewspaperArticle article;
  final ReactionKind kind;
  final DateTime reactedAt;

  Map<String, dynamic> toJson() => {
        'id': article.id,
        'title': article.title,
        'content': article.content,
        'preview': article.preview,
        'category': article.category,
        'estimatedDurationSeconds': article.estimatedDurationSeconds,
        'page': article.page,
        'language': article.language,
        'kind': kind.name,
        'reactedAt': reactedAt.toIso8601String(),
      };

  factory ReactionRecord.fromJson(Map<String, dynamic> j) => ReactionRecord(
        article: NewspaperArticle.fromJson(j),
        kind: (j['kind'] as String?) == 'dislike'
            ? ReactionKind.dislike
            : ReactionKind.like,
        reactedAt:
            DateTime.tryParse(j['reactedAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// Captures "did the user like or dislike this story" — a lightweight
/// interest signal, distinct from Downloads (offline copies) and Playlists
/// (deliberate collections). Local-only (device-scoped): mirrors
/// DownloadsStore's SharedPreferences + singleton ChangeNotifier pattern,
/// since nothing in the app currently forwards a real per-user auth token to
/// Supabase (everything runs on the shared anon key) — a synced version
/// would need that wiring first.
///
/// Dislike is tracked only for now, not used to filter feeds — see
/// project memory for why.
class ReactionsStore extends ChangeNotifier {
  ReactionsStore._();
  static final ReactionsStore i = ReactionsStore._();

  static const _prefsKey = 'reactions_v1';
  static const _maxRecords = 300;

  // Keyed by article id for O(1) lookup from cards/menus/player.
  final Map<String, ReactionRecord> _byId = {};
  bool _loaded = false;

  ReactionKind? reactionFor(String articleId) => _byId[articleId]?.kind;

  /// Liked stories, newest first — what "Liked stories" in For You reads.
  List<ReactionRecord> get liked => _byId.values
      .where((r) => r.kind == ReactionKind.like)
      .toList()
    ..sort((a, b) => b.reactedAt.compareTo(a.reactedAt));

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      _byId.clear();
      for (final j in list) {
        final r = ReactionRecord.fromJson(j);
        _byId[r.article.id] = r;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Tapping the same reaction again clears it (toggle-off); tapping the
  /// other one switches it — a story can't be both liked and disliked.
  Future<void> setReaction(NewspaperArticle article, ReactionKind kind) async {
    await ensureLoaded();
    final current = _byId[article.id]?.kind;
    if (current == kind) {
      _byId.remove(article.id);
    } else {
      _byId[article.id] =
          ReactionRecord(article: article, kind: kind, reactedAt: DateTime.now());
      if (_byId.length > _maxRecords) {
        // Evict the oldest reaction across both kinds.
        final oldest = _byId.values.reduce(
            (a, b) => a.reactedAt.isBefore(b.reactedAt) ? a : b);
        _byId.remove(oldest.article.id);
      }
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey,
          json.encode(_byId.values.map((r) => r.toJson()).toList()));
    } catch (_) {}
  }
}
