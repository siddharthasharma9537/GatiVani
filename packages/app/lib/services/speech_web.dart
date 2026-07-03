// Browser SpeechRecognition (Chrome/Edge/Safari) for Vāni's voice input.
// One-shot: listens for a single utterance, returns the transcript. Telugu
// uses te-IN — Chrome's recognizer handles Telugu + code-switched English.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

JSObject? _rec;

JSAny? get _ctor {
  final win = web.window as JSObject;
  final std = win.getProperty('SpeechRecognition'.toJS);
  if (!std.isUndefinedOrNull) return std;
  final webkit = win.getProperty('webkitSpeechRecognition'.toJS);
  return webkit.isUndefinedOrNull ? null : webkit;
}

bool get speechAvailable => _ctor != null;

void startSpeech({
  required String lang,
  required void Function(String transcript) onResult,
  required void Function() onEnd,
}) {
  final c = _ctor;
  if (c == null) {
    onEnd();
    return;
  }
  final rec = (c as JSFunction).callAsConstructor<JSObject>();
  _rec = rec;
  rec.setProperty('lang'.toJS, (lang == 'te' ? 'te-IN' : 'en-IN').toJS);
  rec.setProperty('interimResults'.toJS, false.toJS);
  rec.setProperty('maxAlternatives'.toJS, 1.toJS);
  rec.setProperty(
      'onresult'.toJS,
      ((JSObject event) {
        try {
          final results = event.getProperty('results'.toJS) as JSObject;
          final r0 =
              results.callMethod('item'.toJS, 0.toJS) as JSObject;
          final alt = r0.callMethod('item'.toJS, 0.toJS) as JSObject;
          final t =
              (alt.getProperty('transcript'.toJS) as JSString?)?.toDart ?? '';
          if (t.trim().isNotEmpty) onResult(t.trim());
        } catch (_) {}
      }).toJS);
  rec.setProperty('onend'.toJS, ((JSAny? e) => onEnd()).toJS);
  rec.setProperty('onerror'.toJS, ((JSAny? e) => onEnd()).toJS);
  rec.callMethod('start'.toJS);
}

void stopSpeech() {
  try {
    _rec?.callMethod('stop'.toJS);
  } catch (_) {}
}
