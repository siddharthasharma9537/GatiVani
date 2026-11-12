import 'audio_cache.dart';

/// The browser build keeps audio in memory only (a page reload re-synthesises).
AudioCache createDiskAudioCache({int maxBytes = 0}) => MemoryAudioCache(maxBytes: 8 * 1024 * 1024);
