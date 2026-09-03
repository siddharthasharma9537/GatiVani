// Non-web platforms: no browser speech synthesis.
//
// The mobile builds fall through to the server free lane (Cloud TTS), which
// sounds better anyway. This stub exists so callers can ask "is there a free
// local voice?" without a platform check at every call site — mirroring the
// speech_stub / speech_web pair used for Vāni's microphone.

bool get localSpeechAvailable => false;

Future<bool> hasLocalVoice(String lang) async => false;

Future<void> speakLocally({
  required String text,
  required String lang,
  double rate = 1.0,
  void Function()? onDone,
}) async {
  onDone?.call();
}

void stopLocalSpeech() {}
