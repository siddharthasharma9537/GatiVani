// Non-web platforms: no browser SpeechRecognition — Vāni's mic hides and
// text input is the way in. (Native STT lands with the mobile builds.)
bool get speechAvailable => false;

void startSpeech({
  required String lang,
  required void Function(String transcript) onResult,
  required void Function() onEnd,
}) {}

void stopSpeech() {}
