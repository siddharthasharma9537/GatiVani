// Non-web platforms: no-op. (Native lock-screen/now-playing would use a
// platform audio service; web uses the browser Media Session API.)
void initMediaSession({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrev,
  required void Function() onSeekForward,
  required void Function() onSeekBackward,
}) {}

void updateMediaSession({
  required String title,
  required String artist,
  required bool playing,
}) {}
