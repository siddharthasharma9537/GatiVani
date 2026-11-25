/// One prepared-audio story (a `paper_story_audio` row; contract: sohum-contracts
/// docs/PAPER_AUDIO_SHAPE.md). Holds an R2 object key only: never a URL, never audio.
class PaperAudioStory {
  const PaperAudioStory({
    required this.edition,
    required this.date,
    required this.storyId,
    required this.rank,
    required this.page,
    required this.headline,
    required this.objectKey,
    required this.bytes,
    required this.durationSeconds,
  });

  final String edition, date, storyId, headline, objectKey;
  final int rank, page, bytes;
  final double durationSeconds;

  static final _key = RegExp(
      r'^paper/[A-Z][A-Z0-9-]*/[0-9]{2}-[0-9]{2}-[0-9]{4}/[0-9]{3}_[a-z0-9][a-z0-9_-]*\.m4a$');

  factory PaperAudioStory.fromJson(Map<String, dynamic> j) {
    final key = j['object_key'];
    if (key is! String || !_key.hasMatch(key)) {
      throw const FormatException('Bad audio key');
    }
    final rank = j['rank'], page = j['page'], bytes = j['bytes'];
    final seconds = j['duration_seconds'];
    if (rank is! int || rank < 1 || page is! int || page < 1) {
      throw const FormatException('Bad audio row');
    }
    if (bytes is! num || bytes < 1 || seconds is! num || seconds <= 0) {
      throw const FormatException('Bad audio row');
    }
    return PaperAudioStory(
      edition: j['edition'] as String,
      date: j['source_date'] as String,
      storyId: j['story_id'] as String,
      rank: rank,
      page: page,
      headline: j['headline'] as String,
      objectKey: key,
      bytes: bytes.toInt(),
      durationSeconds: seconds.toDouble(),
    );
  }

  /// The path under the Worker: `<edition>/<dd-mm-yyyy>/<file>` taken from the key.
  String get workerPath => objectKey.substring('paper/'.length);
}

/// The day's playlist, always in `rank` order.
class PaperAudioPlaylist {
  PaperAudioPlaylist(Iterable<PaperAudioStory> stories)
      : stories = (stories.toList()..sort((a, b) => a.rank.compareTo(b.rank)));
  final List<PaperAudioStory> stories;

  int indexOf(String storyId) =>
      stories.indexWhere((s) => s.storyId == storyId);
  PaperAudioStory? next(String storyId) {
    final i = indexOf(storyId);
    return i < 0 || i + 1 >= stories.length ? null : stories[i + 1];
  }

  PaperAudioStory? previous(String storyId) {
    final i = indexOf(storyId);
    return i <= 0 ? null : stories[i - 1];
  }

  double get totalSeconds =>
      stories.fold(0.0, (sum, s) => sum + s.durationSeconds);
}
