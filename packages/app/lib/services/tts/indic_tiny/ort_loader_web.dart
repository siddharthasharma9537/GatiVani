import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// ONNX Runtime Web version the plugin talks to. Pinned: the voice pack's graphs were exported with onnxruntime 1.31.
const _ortWebUrl = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.31.1/dist/ort.min.js';

Future<void>? _loading;

/// Load `ort` (ONNX Runtime Web) on first use, so visitors who never use the on-device voice never download it.
Future<void> ensureOrtLoaded() {
  if ((web.window as JSObject).has('ort')) return Future.value();
  return _loading ??= () async {
    final done = Completer<void>();
    final s = web.document.createElement('script') as web.HTMLScriptElement
      ..src = _ortWebUrl
      ..async = true;
    s.onload = ((web.Event _) => done.complete()).toJS;
    s.onerror = ((web.Event _) => done.completeError(StateError('could not load ONNX Runtime Web'))).toJS;
    web.document.head!.append(s);
    try {
      await done.future;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }();
}
