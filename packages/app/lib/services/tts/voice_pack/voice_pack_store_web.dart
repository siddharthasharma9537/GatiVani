import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'pack_manifest.dart';
import 'voice_pack_store.dart';

VoicePackStore createVoicePackStore(VoicePackManifest manifest) => WebVoicePackStore(manifest);

/// Browser: the files live in Cache Storage (one cache per pack version); ONNX Runtime Web opens them through blob URLs.
/// A browser cannot resume a download, so a dropped download starts that file again; each file is held in memory once
/// (the largest is 54 MB) to be hashed before it is stored.
class WebVoicePackStore implements VoicePackStore {
  WebVoicePackStore(this.manifest);

  @override
  final VoicePackManifest manifest;

  static const _markerUrl = 'https://voicepack.invalid/verified';
  final Map<String, String> _blobUrls = {};

  String get _prefix => 'voice-pack-${manifest.id}-';
  String get _cacheName => '$_prefix${manifest.version}';

  Future<web.Cache> _cache() => web.window.caches.open(_cacheName).toDart;

  Future<web.Response?> _match(web.Cache c, String url) async {
    final r = await c.match(url.toJS).toDart;
    return r.isDefinedAndNotNull ? r as web.Response : null;
  }

  @override
  Future<bool> isInstalled() async {
    if (!(await web.window.caches.has(_cacheName).toDart).toDart) return false;
    final c = await _cache();
    if (await _match(c, _markerUrl) == null) return false;
    for (final f in manifest.files) {
      if (await _match(c, manifest.urlFor(f).toString()) == null) return false;
    }
    return true;
  }

  @override
  Future<int> installedBytes() async => await isInstalled() ? manifest.totalBytes : 0;

  @override
  Future<int?> freeBytes() async {
    try {
      final e = await web.window.navigator.storage.estimate().toDart;
      final quota = e.quota, usage = e.usage;
      return (quota - usage).floor();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> install({void Function(int done, int total)? onProgress, CancelFlag? cancel}) async {
    final free = await freeBytes();
    const margin = 64 * 1024 * 1024;
    if (free != null && free < manifest.totalBytes + margin) {
      throw InsufficientSpaceException(manifest.totalBytes + margin, free);
    }
    final total = manifest.totalBytes;
    final cache = await _cache();
    var finished = 0;
    onProgress?.call(0, total);
    final client = http.Client();
    try {
      for (final f in manifest.files) {
        if (cancel?.cancelled ?? false) throw DownloadCancelled();
        final url = manifest.urlFor(f).toString();
        if (await _match(cache, url) == null) {
          final resp = await client.send(http.Request('GET', manifest.urlFor(f)));
          if (resp.statusCode != 200) throw StateError('HTTP ${resp.statusCode} for ${f.name}');
          final b = BytesBuilder(copy: false);
          await for (final chunk in resp.stream) {
            if (cancel?.cancelled ?? false) throw DownloadCancelled();
            b.add(chunk);
            onProgress?.call(finished + b.length, total);
          }
          final bytes = b.takeBytes();
          final actual = sha256.convert(bytes).toString();
          if (bytes.length != f.bytes || actual != f.sha256) throw HashMismatch(f.name, f.sha256, actual);
          await cache.put(url.toJS, web.Response(Uint8List.fromList(bytes).toJS)).toDart;
        }
        finished += f.bytes;
        onProgress?.call(finished, total);
      }
    } finally {
      client.close();
    }
    await cache.put(_markerUrl.toJS, web.Response(manifest.revision.toJS)).toDart;
    final keys = (await web.window.caches.keys().toDart).toDart.map((k) => k.toDart);
    for (final k in keys) {
      if (k.startsWith(_prefix) && k != _cacheName) await web.window.caches.delete(k).toDart;
    }
  }

  @override
  Future<void> delete() async {
    for (final u in _blobUrls.values) {
      web.URL.revokeObjectURL(u);
    }
    _blobUrls.clear();
    final keys = (await web.window.caches.keys().toDart).toDart.map((k) => k.toDart);
    for (final k in keys) {
      if (k.startsWith(_prefix)) await web.window.caches.delete(k).toDart;
    }
  }

  @override
  Future<String> readText(String name) async {
    final r = await _match(await _cache(), manifest.urlFor(manifest.file(name)).toString());
    if (r == null) throw StateError('Voice pack file $name is not installed');
    return (await r.text().toDart).toDart;
  }

  @override
  Future<Map<String, String>> modelLocations() async {
    final cache = await _cache();
    final out = <String, String>{};
    for (final g in const ['text_encoder', 'flow_decoder', 'vocoder']) {
      final name = '$g.onnx';
      out[g] = _blobUrls[name] ??= await () async {
        final r = await _match(cache, manifest.urlFor(manifest.file(name)).toString());
        if (r == null) throw StateError('Voice pack file $name is not installed');
        return web.URL.createObjectURL(await r.blob().toDart);
      }();
    }
    return out;
  }
}
