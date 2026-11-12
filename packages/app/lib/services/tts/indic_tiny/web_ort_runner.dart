import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'onnx_runner.dart';
import 'ort_loader_web.dart';

/// [OnnxRunner] straight on ONNX Runtime Web (`ort`), used in the browser instead of `flutter_onnxruntime`: that plugin cannot
/// create int64 tensors on the web (dart2js has no Int64List), and the text encoder takes int64 token ids. Here they are built
/// as a JavaScript BigInt64Array. [locations] are blob or http URLs of the .onnx files.
class WebOrtRunner implements OnnxRunner {
  WebOrtRunner(this.locations, {this.threads = 2});

  final Map<String, String> locations;
  final int threads;
  final Map<String, JSObject> _sessions = {};

  JSObject get _ort => globalContext['ort'] as JSObject;

  @override
  Future<void> load() async {
    for (final g in locations.keys) {
      await _session(g);
    }
  }

  Future<JSObject> _session(String graph) async {
    final existing = _sessions[graph];
    if (existing != null) return existing;
    await ensureOrtLoaded();
    final url = locations[graph];
    if (url == null) throw ArgumentError('Unknown graph $graph');
    ((_ort['env'] as JSObject)['wasm'] as JSObject)['numThreads'] = threads.toJS;
    final opts = JSObject();
    opts['executionProviders'] = ['wasm'.toJS].toJS;
    final create = (_ort['InferenceSession'] as JSObject).callMethod<JSPromise<JSObject>>('create'.toJS, url.toJS, opts);
    return _sessions[graph] = await create.toDart;
  }

  JSObject _tensor(Tensor t) {
    final ctor = _ort['Tensor'] as JSFunction;
    final dims = t.shape.map((d) => d.toJS).toList().toJS;
    if (t.floats != null) {
      return ctor.callAsConstructorVarArgs<JSObject>(['float32'.toJS, t.floats!.toJS, dims]);
    }
    final ints = t.ints!;
    final big = (globalContext['BigInt64Array'] as JSFunction).callAsConstructor<JSObject>(ints.length.toJS);
    for (var i = 0; i < ints.length; i++) {
      big.setProperty(i.toJS, globalContext.callMethod<JSAny>('BigInt'.toJS, ints[i].toJS));
    }
    return ctor.callAsConstructorVarArgs<JSObject>(['int64'.toJS, big, dims]);
  }

  @override
  Future<List<Tensor>> run(String graph, Map<String, Tensor> inputs) async {
    final session = await _session(graph);
    final feeds = JSObject();
    final made = <JSObject>[];
    try {
      for (final e in inputs.entries) {
        final t = _tensor(e.value);
        made.add(t);
        feeds[e.key] = t;
      }
      final out = await session.callMethod<JSPromise<JSObject>>('run'.toJS, feeds).toDart;
      final names = (session['outputNames'] as JSArray<JSString>).toDart.map((n) => n.toDart).toList();
      final result = <Tensor>[];
      for (final n in names) {
        final t = out[n] as JSObject;
        final dims = (t['dims'] as JSArray<JSNumber>).toDart.map((d) => d.toDartInt).toList();
        final data = (t['data'] as JSFloat32Array).toDart;
        result.add(Tensor.f32(dims, Float32List.fromList(data))); // copy: the tensor's memory is freed below
        t.callMethod<JSAny?>('dispose'.toJS);
      }
      return result;
    } finally {
      for (final t in made) {
        t.callMethod<JSAny?>('dispose'.toJS);
      }
    }
  }

  @override
  Future<void> dispose() async {
    for (final s in _sessions.values) {
      await s.callMethod<JSPromise<JSAny?>>('release'.toJS).toDart;
    }
    _sessions.clear();
  }
}
