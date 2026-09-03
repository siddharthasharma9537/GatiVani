// Browser speech synthesis for short text — the ₹0 lane.
//
// Ticker headlines are ~80–120 characters and there are a couple of hundred a
// day. Sending them to a server voice means a synthesis call, an R2 object and
// a cache row for something read once, in two seconds, and never again. The
// browser already has a Telugu voice on most Android devices (the Google
// Speech Services engine) and on most desktop Chrome, and it costs nothing,
// starts instantly, and needs no network round trip.
//
// Everything longer — Live articles, explainers, edition text — goes to the
// server free lane instead, where the result is cached once and shared by every
// listener. See docs/ORCHESTRATION_PLAN.md §2.4.
//
// Availability is genuinely uneven, which is why `hasLocalVoice` exists and
// callers must fall back: iOS Safari has no te-IN voice, and a desktop Linux
// Chrome without speech-dispatcher has none at all. Never assume this worked.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

JSObject? get _synth {
  final win = web.window as JSObject;
  final s = win.getProperty('speechSynthesis'.toJS);
  return s.isUndefinedOrNull ? null : s as JSObject;
}

bool get localSpeechAvailable => _synth != null;

String _bcp47(String lang) => lang == 'te' ? 'te-IN' : (lang == 'hi' ? 'hi-IN' : 'en-IN');

/// Voices load asynchronously in Chrome: the first `getVoices()` after page
/// load routinely returns an empty list, and the real list arrives with a
/// `voiceschanged` event. Polling briefly is the pragmatic way to survive that
/// without wiring a listener into every caller.
Future<List<JSObject>> _voices({int attempts = 10}) async {
  final synth = _synth;
  if (synth == null) return const [];
  for (var i = 0; i < attempts; i++) {
    final list = synth.callMethod('getVoices'.toJS) as JSArray?;
    if (list != null) {
      final len = (list.getProperty('length'.toJS) as JSNumber?)?.toDartInt ?? 0;
      if (len > 0) {
        return [
          for (var j = 0; j < len; j++) list.getProperty(j.toJS) as JSObject,
        ];
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return const [];
}

JSObject? _pickVoice(List<JSObject> voices, String target) {
  final lower = target.toLowerCase();
  final short = lower.split('-').first;
  JSObject? looseMatch;
  for (final v in voices) {
    final lang = ((v.getProperty('lang'.toJS) as JSString?)?.toDart ?? '')
        .toLowerCase()
        .replaceAll('_', '-');
    if (lang == lower) return v; // exact locale wins
    if (looseMatch == null && lang.split('-').first == short) looseMatch = v;
  }
  return looseMatch;
}

/// Whether this browser can speak [lang] locally. Callers must use the server
/// free lane when this is false.
Future<bool> hasLocalVoice(String lang) async {
  if (_synth == null) return false;
  return _pickVoice(await _voices(), _bcp47(lang)) != null;
}

/// Speak [text] with the local voice. Resolves when speech ends (or errors).
///
/// Cancels anything already speaking: two overlapping headlines are worse than
/// a clipped one, and Chrome queues rather than replaces by default.
Future<void> speakLocally({
  required String text,
  required String lang,
  double rate = 1.0,
  void Function()? onDone,
}) async {
  final synth = _synth;
  if (synth == null || text.trim().isEmpty) {
    onDone?.call();
    return;
  }

  final target = _bcp47(lang);
  final voice = _pickVoice(await _voices(), target);
  if (voice == null) {
    // No voice: report done so the caller can fall back rather than hang.
    onDone?.call();
    return;
  }

  try {
    synth.callMethod('cancel'.toJS);
  } catch (_) {}

  final ctor = (web.window as JSObject).getProperty('SpeechSynthesisUtterance'.toJS);
  if (ctor.isUndefinedOrNull) {
    onDone?.call();
    return;
  }

  final utterance =
      (ctor as JSFunction).callAsConstructorVarArgs<JSObject>([text.toJS]);
  utterance.setProperty('voice'.toJS, voice);
  utterance.setProperty('lang'.toJS, target.toJS);
  utterance.setProperty('rate'.toJS, rate.toJS);

  final completer = Completer<void>();
  void finish() {
    if (!completer.isCompleted) {
      completer.complete();
      onDone?.call();
    }
  }

  utterance.setProperty('onend'.toJS, ((JSAny? _) => finish()).toJS);
  utterance.setProperty('onerror'.toJS, ((JSAny? _) => finish()).toJS);

  try {
    synth.callMethod('speak'.toJS, utterance);
  } catch (_) {
    finish();
    return;
  }

  // Chrome drops `onend` on the floor often enough that waiting on it alone
  // can hang forever. Cap the wait at a generous multiple of the expected
  // read time — this lane only ever speaks short strings.
  final ceiling = Duration(
    milliseconds: 4000 + (text.length * 120 ~/ rate).clamp(0, 60000),
  );
  return completer.future.timeout(ceiling, onTimeout: finish);
}

void stopLocalSpeech() {
  try {
    _synth?.callMethod('cancel'.toJS);
  } catch (_) {}
}
