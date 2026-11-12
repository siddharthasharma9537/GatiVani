import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'pack_manifest.dart';
import 'voice_pack_store.dart';

/// SHA-256 of a file, streamed (the 54 MB vocoder is never held in memory).
Future<String> sha256OfFile(File f) async => (await sha256.bind(f.openRead()).first).toString();

/// Download [file] to [dest], resuming from `<dest>.part` if it exists, and verify size and SHA-256 before moving it into
/// place. [onBytes] gets the number of NEW bytes received (not the resumed part), so the caller can add up progress.
/// A file already at [dest] that verifies is left alone. Retries a dropped connection up to [retries] times, resuming.
Future<void> downloadVerified({
  required http.Client client,
  required Uri url,
  required PackFile file,
  required File dest,
  void Function(int bytes)? onBytes,
  CancelFlag? cancel,
  int retries = 3,
}) async {
  if (await dest.exists()) {
    if (await dest.length() == file.bytes && await sha256OfFile(dest) == file.sha256) return;
    await dest.delete();
  }
  await dest.parent.create(recursive: true);
  final part = File('${dest.path}.part');
  var attempt = 0;
  while (true) {
    try {
      await _fetch(client, url, file, part, onBytes, cancel);
      break;
    } on DownloadCancelled {
      rethrow;
    } on HashMismatch {
      rethrow;
    } catch (_) {
      if (++attempt > retries) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
  }
  final actual = await sha256OfFile(part);
  if (await part.length() != file.bytes || actual != file.sha256) {
    await part.delete();
    throw HashMismatch(file.name, file.sha256, actual);
  }
  await part.rename(dest.path);
}

Future<void> _fetch(
    http.Client client, Uri url, PackFile file, File part, void Function(int)? onBytes, CancelFlag? cancel) async {
  var have = await part.exists() ? await part.length() : 0;
  if (have > file.bytes) {
    await part.delete();
    have = 0;
  }
  if (have == file.bytes) return; // fully downloaded earlier; verified by the caller
  final req = http.Request('GET', url);
  if (have > 0) req.headers['Range'] = 'bytes=$have-';
  final resp = await client.send(req);
  if (resp.statusCode != 200 && resp.statusCode != 206) {
    await resp.stream.drain<void>();
    throw HttpException('HTTP ${resp.statusCode} for ${file.name}');
  }
  // A 200 to a ranged request means the server ignored Range: start over.
  final resume = resp.statusCode == 206 && have > 0;
  final sink = part.openWrite(mode: resume ? FileMode.append : FileMode.write);
  try {
    await for (final chunk in resp.stream) {
      if (cancel?.cancelled ?? false) throw DownloadCancelled();
      sink.add(chunk);
      onBytes?.call(chunk.length);
    }
  } finally {
    await sink.flush();
    await sink.close();
  }
}
