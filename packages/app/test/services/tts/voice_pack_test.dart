import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/services/tts/voice_pack/pack_manifest.dart';
import 'package:gativani_app/services/tts/voice_pack/resumable_download.dart';
import 'package:gativani_app/services/tts/voice_pack/voice_pack_store.dart';
import 'package:gativani_app/services/tts/voice_pack/voice_pack_store_io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Uint8List _bytes(int n, int seed) => Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xff));
String _sha(List<int> b) => sha256.convert(b).toString();

/// A fake Hugging Face: serves [files] by path, honours Range unless [ignoreRange], and can cut a response short once.
MockClient _server(Map<String, Uint8List> files,
    {bool ignoreRange = false, int? dropAfter, List<String>? log, Map<String, Uint8List>? corrupt}) {
  var dropped = false;
  return MockClient.streaming((req, _) async {
    final key = req.url.path.split('/resolve/').last.split('/').skip(1).join('/');
    log?.add('${req.url.path} ${req.headers['Range'] ?? ''}');
    final data = corrupt?[key] ?? files[key];
    if (data == null) return http.StreamedResponse(const Stream.empty(), 404);
    var start = 0;
    var status = 200;
    final range = req.headers['Range'];
    if (range != null && !ignoreRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      status = 206;
    }
    var body = data.sublist(start);
    if (dropAfter != null && !dropped && start == 0) {
      dropped = true;
      final cut = body.sublist(0, dropAfter);
      return http.StreamedResponse(
          Stream<List<int>>.fromFutures([Future.value(cut), Future.error(const SocketException('connection lost'))]), 200);
    }
    return http.StreamedResponse(Stream.value(body), status);
  });
}

VoicePackManifest _manifest(Map<String, Uint8List> files) => VoicePackManifest(
      id: 'test',
      version: '1',
      repo: 'o/r',
      revision: 'abc',
      files: [for (final e in files.entries) PackFile(e.key, e.key, e.value.length, _sha(e.value))],
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('voicepack_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the shipped manifest is pinned to a commit and lists three graphs with sha256', () {
    const m = VoicePackManifest.indicTinyTelugu;
    expect(m.revision, matches(RegExp(r'^[0-9a-f]{40}$')));
    for (final f in m.files) {
      expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
    expect(m.files.map((f) => f.name), containsAll(['text_encoder.onnx', 'flow_decoder.onnx', 'vocoder.onnx', 'config.json']));
    expect(m.urlFor(m.file('vocoder.onnx')).toString(),
        'https://huggingface.co/sulabhkatiyar/indic-tiny-tts-telugu/resolve/${m.revision}/onnx/vocoder.onnx');
    expect(voicePackCredits, contains('CC-BY-4.0'));
    expect(voicePackCredits, contains('Rasa'));
  });

  test('downloads and verifies; a second run does not download again', () async {
    final data = _bytes(5000, 1);
    final f = PackFile('a.bin', 'a.bin', data.length, _sha(data));
    final log = <String>[];
    final c = _server({'a.bin': data}, log: log);
    final dest = File('${tmp.path}/a.bin');
    var got = 0;
    await downloadVerified(client: c, url: Uri.parse('https://x/o/r/resolve/abc/a.bin'), file: f, dest: dest, onBytes: (n) => got += n);
    expect(await dest.readAsBytes(), data);
    expect(got, data.length);
    expect(File('${dest.path}.part').existsSync(), false);
    await downloadVerified(client: c, url: Uri.parse('https://x/o/r/resolve/abc/a.bin'), file: f, dest: dest);
    expect(log.length, 1);
  });

  test('resumes a partial download with a Range request', () async {
    final data = _bytes(8000, 2);
    final f = PackFile('a.bin', 'a.bin', data.length, _sha(data));
    final log = <String>[];
    final dest = File('${tmp.path}/a.bin');
    File('${dest.path}.part').writeAsBytesSync(data.sublist(0, 3000));
    var got = 0;
    await downloadVerified(
        client: _server({'a.bin': data}, log: log),
        url: Uri.parse('https://x/o/r/resolve/abc/a.bin'),
        file: f,
        dest: dest,
        onBytes: (n) => got += n);
    expect(log.single, endsWith('bytes=3000-'));
    expect(got, 5000);
    expect(await dest.readAsBytes(), data);
  });

  test('a server that ignores Range restarts the file instead of corrupting it', () async {
    final data = _bytes(6000, 3);
    final f = PackFile('a.bin', 'a.bin', data.length, _sha(data));
    final dest = File('${tmp.path}/a.bin');
    File('${dest.path}.part').writeAsBytesSync(data.sublist(0, 2000));
    await downloadVerified(
        client: _server({'a.bin': data}, ignoreRange: true), url: Uri.parse('https://x/o/r/resolve/abc/a.bin'), file: f, dest: dest);
    expect(await dest.readAsBytes(), data);
  });

  test('a dropped connection is retried and resumed', () async {
    final data = _bytes(9000, 4);
    final f = PackFile('a.bin', 'a.bin', data.length, _sha(data));
    final log = <String>[];
    final dest = File('${tmp.path}/a.bin');
    await downloadVerified(
        client: _server({'a.bin': data}, dropAfter: 4000, log: log),
        url: Uri.parse('https://x/o/r/resolve/abc/a.bin'),
        file: f,
        dest: dest);
    expect(await dest.readAsBytes(), data);
    expect(log.length, 2);
    expect(log.last, endsWith('bytes=4000-'));
  });

  test('a corrupted file fails verification and is removed', () async {
    final data = _bytes(3000, 5);
    final bad = Uint8List.fromList(data)..[10] ^= 0xff;
    final f = PackFile('a.bin', 'a.bin', data.length, _sha(data));
    final dest = File('${tmp.path}/a.bin');
    await expectLater(
        downloadVerified(
            client: _server({'a.bin': data}, corrupt: {'a.bin': bad}), url: Uri.parse('https://x/o/r/resolve/abc/a.bin'), file: f, dest: dest),
        throwsA(isA<HashMismatch>()));
    expect(dest.existsSync(), false);
    expect(File('${dest.path}.part').existsSync(), false);
  });

  test('cancel keeps the partial file so the next run resumes', () async {
    final data = _bytes(3000, 6);
    final f = PackFile('a.bin', 'a.bin', data.length, _sha(data));
    final dest = File('${tmp.path}/a.bin');
    final cancel = CancelFlag()..cancelled = true;
    await expectLater(
        downloadVerified(
            client: _server({'a.bin': data}), url: Uri.parse('https://x/o/r/resolve/abc/a.bin'), file: f, dest: dest, cancel: cancel),
        throwsA(isA<DownloadCancelled>()));
    expect(dest.existsSync(), false);
  });

  group('store', () {
    final files = {
      'config.json': Uint8List.fromList(utf8.encode('{"a":1}')),
      'text_encoder.onnx': _bytes(4000, 7),
      'flow_decoder.onnx': _bytes(5000, 8),
      'vocoder.onnx': _bytes(6000, 9),
    };

    IoVoicePackStore store(http.Client c, {int free = 1 << 40}) =>
        IoVoicePackStore(_manifest(files), root: tmp, client: c, freeSpace: (_) async => free);

    test('install, progress, verified marker, locations, delete', () async {
      final s = store(_server(files));
      expect(await s.isInstalled(), false);
      final seen = <int>[];
      await s.install(onProgress: (d, t) => seen.add(d));
      expect(await s.isInstalled(), true);
      expect(seen.first, 0);
      expect(seen.last, _manifest(files).totalBytes);
      expect(seen, orderedEquals([...seen]..sort()));
      expect(await s.readText('config.json'), '{"a":1}');
      final loc = await s.modelLocations();
      expect(loc.keys, containsAll(['text_encoder', 'flow_decoder', 'vocoder']));
      expect(File(loc['vocoder']!).existsSync(), true);
      await s.delete();
      expect(await s.isInstalled(), false);
    });

    test('refuses when storage is short, before downloading anything', () async {
      final log = <String>[];
      final s = store(_server(files, log: log), free: 1000);
      await expectLater(s.install(), throwsA(isA<InsufficientSpaceException>()));
      expect(log, isEmpty);
    });

    test('an interrupted install is not "installed" and resumes on the next call', () async {
      final cancel = CancelFlag();
      final s = store(_server(files));
      await expectLater(s.install(onProgress: (d, t) => cancel.cancelled = d > 4000, cancel: cancel), throwsA(isA<DownloadCancelled>()));
      expect(await s.isInstalled(), false);
      await s.install();
      expect(await s.isInstalled(), true);
    });

    test('a new version replaces the old one only after it verified', () async {
      await store(_server(files)).install();
      final m2 = VoicePackManifest(id: 'test', version: '2', repo: 'o/r', revision: 'abc', files: _manifest(files).files);
      final s2 = IoVoicePackStore(m2, root: tmp, client: _server(files), freeSpace: (_) async => 1 << 40);
      await s2.install();
      expect(Directory('${tmp.path}/test/1').existsSync(), false);
      expect(await s2.isInstalled(), true);
    });
  });
}
