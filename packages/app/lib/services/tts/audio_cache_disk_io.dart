import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'audio_cache.dart';

AudioCache createDiskAudioCache({int maxBytes = 120 * 1024 * 1024}) => DiskAudioCache(maxBytes: maxBytes);

/// WAV files in the app's cache folder, capped in bytes; the least recently used files go first. The OS may also clear this
/// folder when storage is low, which only costs a re-synthesis.
class DiskAudioCache implements AudioCache {
  DiskAudioCache({this.maxBytes = 120 * 1024 * 1024, Directory? dir}) : _dir = dir;
  final int maxBytes;
  final Directory? _dir;

  Future<Directory> _d() async {
    final d = _dir ?? Directory('${(await getApplicationCacheDirectory()).path}/tts_audio');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  @override
  Future<Uint8List?> get(String key) async {
    final f = File('${(await _d()).path}/$key.wav');
    if (!await f.exists()) return null;
    try {
      final b = await f.readAsBytes();
      await f.setLastModified(DateTime.now()); // recently used
      return b;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> put(String key, Uint8List wav) async {
    if (wav.length > maxBytes) return;
    final d = await _d();
    final tmp = File('${d.path}/$key.tmp');
    await tmp.writeAsBytes(wav, flush: true);
    await tmp.rename('${d.path}/$key.wav');
    await _evict(d);
  }

  Future<void> _evict(Directory d) async {
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.wav')) {
        final st = await e.stat();
        files.add((e, st.size, st.modified));
        total += st.size;
      }
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final f in files) {
      if (total <= maxBytes) break;
      await f.$1.delete();
      total -= f.$2;
    }
  }

  @override
  Future<void> clear() async {
    final d = _dir ?? Directory('${(await getApplicationCacheDirectory()).path}/tts_audio');
    if (await d.exists()) await d.delete(recursive: true);
  }
}
