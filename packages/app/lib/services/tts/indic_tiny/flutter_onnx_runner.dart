import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'onnx_runner.dart';
import 'ort_loader.dart';

/// [OnnxRunner] on `flutter_onnxruntime` (MIT): ONNX Runtime Mobile on Android/iOS, ONNX Runtime Web in the browser.
///
/// [locations] maps graph name -> file path (native) or URL (web). Sessions are created lazily on first use and kept; one
/// [dispose] closes them all. CPU execution provider only: the graphs are small, and a GPU/NNAPI/CoreML provider would add
/// start-up cost and numerical differences on budget phones that were not measured.
class FlutterOnnxRunner implements OnnxRunner {
  FlutterOnnxRunner(this.locations, {this.threads = 2});

  final Map<String, String> locations;
  final int threads;
  final Map<String, OrtSession> _sessions = {};
  final OnnxRuntime _ort = OnnxRuntime();

  @override
  Future<void> load() async {
    for (final g in locations.keys) {
      await _session(g);
    }
  }

  Future<OrtSession> _session(String graph) async {
    final existing = _sessions[graph];
    if (existing != null) return existing;
    await ensureOrtLoaded();
    final path = locations[graph];
    if (path == null) throw ArgumentError('Unknown graph $graph');
    final s = await _ort.createSession(
      path,
      options: OrtSessionOptions(
        intraOpNumThreads: threads,
        interOpNumThreads: 1,
        providers: [OrtProvider.CPU],
      ),
    );
    return _sessions[graph] = s;
  }

  @override
  Future<List<Tensor>> run(String graph, Map<String, Tensor> inputs) async {
    final session = await _session(graph);
    final ins = <String, OrtValue>{};
    Map<String, OrtValue>? outs;
    try {
      for (final e in inputs.entries) {
        final t = e.value;
        ins[e.key] = t.floats != null
            ? await OrtValue.fromList(t.floats!, t.shape)
            : await OrtValue.fromList(Int64List.fromList(t.ints!), t.shape);
      }
      outs = await session.run(ins);
      final result = <Tensor>[];
      for (final name in session.outputNames) {
        final v = outs[name]!;
        final flat = await v.asFlattenedList();
        result.add(Tensor.f32(v.shape, Float32List.fromList(flat.map((x) => (x as num).toDouble()).toList())));
      }
      return result;
    } finally {
      for (final v in ins.values) {
        await v.dispose();
      }
      if (outs != null) {
        for (final v in outs.values) {
          await v.dispose();
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    for (final s in _sessions.values) {
      await s.close();
    }
    _sessions.clear();
  }
}
