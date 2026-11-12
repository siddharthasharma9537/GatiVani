import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'pack_manifest.dart';
import 'resumable_download.dart';
import 'voice_pack_store.dart';

VoicePackStore createVoicePackStore(VoicePackManifest manifest) => IoVoicePackStore(manifest);

/// Android / iOS (and desktop): files under `<app support>/voice_packs/<id>/<version>/`. A `.verified` marker is written only
/// after every file passed its SHA-256, so a half-installed pack is never loaded.
class IoVoicePackStore implements VoicePackStore {
  IoVoicePackStore(this.manifest, {Directory? root, http.Client? client, Future<int?> Function(String path)? freeSpace})
      : _root = root,
        _client = client,
        _freeSpace = freeSpace ?? _deviceFreeBytes;

  @override
  final VoicePackManifest manifest;
  final Directory? _root;
  final http.Client? _client;
  final Future<int?> Function(String path) _freeSpace;

  static Future<int?> _deviceFreeBytes(String path) async {
    try {
      final mb = await DiskSpacePlus().getFreeDiskSpaceForPath(path);
      return mb == null ? null : (mb * 1024 * 1024).floor();
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _packRoot() async {
    final base = _root ?? Directory('${(await getApplicationSupportDirectory()).path}/voice_packs');
    return Directory('${base.path}/${manifest.id}');
  }

  Future<Directory> _dir() async => Directory('${(await _packRoot()).path}/${manifest.version}');

  @override
  Future<bool> isInstalled() async {
    final d = await _dir();
    final marker = File('${d.path}/.verified');
    if (!await marker.exists()) return false;
    for (final f in manifest.files) {
      final file = File('${d.path}/${f.name}');
      if (!await file.exists() || await file.length() != f.bytes) return false;
    }
    return true;
  }

  @override
  Future<int> installedBytes() async => await isInstalled() ? manifest.totalBytes : 0;

  @override
  Future<int?> freeBytes() async {
    final r = await _packRoot();
    await r.create(recursive: true);
    return _freeSpace(r.path);
  }

  @override
  Future<void> install({void Function(int done, int total)? onProgress, CancelFlag? cancel}) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    // Bytes already on disk (finished files and partial downloads) do not need free space again.
    var have = 0;
    for (final f in manifest.files) {
      final done = File('${dir.path}/${f.name}');
      final part = File('${done.path}.part');
      if (await done.exists()) {
        have += f.bytes;
      } else if (await part.exists()) {
        have += await part.length();
      }
    }
    final need = manifest.totalBytes - have;
    final free = await freeBytes();
    // Needs headroom for the file being moved into place plus a margin for the app's own cache and the audio cache.
    const margin = 64 * 1024 * 1024;
    if (free != null && free < need + margin) throw InsufficientSpaceException(need + margin, free);

    final total = manifest.totalBytes;
    var finished = 0; // bytes of files completed (or already present and verified) so far
    onProgress?.call(0, total);
    final client = _client ?? http.Client();
    try {
      for (final f in manifest.files) {
        if (cancel?.cancelled ?? false) throw DownloadCancelled();
        final dest = File('${dir.path}/${f.name}');
        final part = File('${dest.path}.part');
        final resumed = await part.exists() ? await part.length() : 0;
        var received = 0;
        await downloadVerified(
          client: client,
          url: manifest.urlFor(f),
          file: f,
          dest: dest,
          cancel: cancel,
          onBytes: (n) {
            received += n;
            onProgress?.call(finished + resumed + received, total);
          },
        );
        finished += f.bytes;
        onProgress?.call(finished, total);
      }
    } finally {
      if (_client == null) client.close();
    }
    await File('${dir.path}/.verified').writeAsString(manifest.revision);
    // The new version is verified: drop older versions.
    final root = await _packRoot();
    await for (final e in root.list()) {
      if (e is Directory && e.path != dir.path) await e.delete(recursive: true);
    }
  }

  @override
  Future<void> delete() async {
    final r = await _packRoot();
    if (await r.exists()) await r.delete(recursive: true);
  }

  @override
  Future<String> readText(String name) async => File('${(await _dir()).path}/$name').readAsString();

  @override
  Future<Map<String, String>> modelLocations() async {
    final d = await _dir();
    return {
      for (final g in const ['text_encoder', 'flow_decoder', 'vocoder']) g: '${d.path}/$g.onnx',
    };
  }
}
