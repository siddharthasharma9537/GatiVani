import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Cache key for one sentence: text + voice + voice-pack version (a new model version must not reuse old audio). Speed is not
/// part of the key: sentences are always generated at 1.0x and the player changes the speed.
String audioCacheKey({required String text, required String voice, required String version}) =>
    sha256.convert(utf8.encode('$version\u0000$voice\u0000$text')).toString();

abstract class AudioCache {
  Future<Uint8List?> get(String key);
  Future<void> put(String key, Uint8List wav);
  Future<void> clear();
}

/// Least-recently-used cache in memory, capped in bytes (the whole web build, and the first layer on devices).
class MemoryAudioCache implements AudioCache {
  MemoryAudioCache({this.maxBytes = 24 * 1024 * 1024});
  final int maxBytes;
  final LinkedHashMap<String, Uint8List> _m = LinkedHashMap();
  int _bytes = 0;

  int get bytes => _bytes;
  int get length => _m.length;

  @override
  Future<Uint8List?> get(String key) async {
    final v = _m.remove(key);
    if (v != null) _m[key] = v; // most recent last
    return v;
  }

  @override
  Future<void> put(String key, Uint8List wav) async {
    final old = _m.remove(key);
    if (old != null) _bytes -= old.length;
    if (wav.length > maxBytes) return;
    _m[key] = wav;
    _bytes += wav.length;
    while (_bytes > maxBytes && _m.isNotEmpty) {
      final k = _m.keys.first;
      _bytes -= _m.remove(k)!.length;
    }
  }

  @override
  Future<void> clear() async {
    _m.clear();
    _bytes = 0;
  }
}

/// Memory in front of a second (disk) cache.
class LayeredAudioCache implements AudioCache {
  LayeredAudioCache(this.memory, this.disk);
  final AudioCache memory;
  final AudioCache disk;

  @override
  Future<Uint8List?> get(String key) async {
    final m = await memory.get(key);
    if (m != null) return m;
    final d = await disk.get(key);
    if (d != null) await memory.put(key, d);
    return d;
  }

  @override
  Future<void> put(String key, Uint8List wav) async {
    await memory.put(key, wav);
    await disk.put(key, wav);
  }

  @override
  Future<void> clear() async {
    await memory.clear();
    await disk.clear();
  }
}
