import 'dart:js_interop';
import 'package:web/web.dart' as web;

// Browser Media Session API → OS lock-screen / notification / headphone media
// controls and now-playing metadata. Wired to the playback service so the
// hardware buttons and lock screen drive playback on web.

void initMediaSession({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrev,
  required void Function() onSeekForward,
  required void Function() onSeekBackward,
}) {
  try {
    final ms = web.window.navigator.mediaSession;
    void set(String action, void Function() cb) {
      ms.setActionHandler(action, ((JSObject _) => cb()).toJS);
    }

    set('play', onPlay);
    set('pause', onPause);
    set('nexttrack', onNext);
    set('previoustrack', onPrev);
    set('seekforward', onSeekForward);
    set('seekbackward', onSeekBackward);
  } catch (_) {}
}

void updateMediaSession({
  required String title,
  required String artist,
  required bool playing,
}) {
  try {
    final ms = web.window.navigator.mediaSession;
    ms.metadata = web.MediaMetadata(web.MediaMetadataInit(
      title: title,
      artist: artist,
      album: 'Gativani',
    ));
    ms.playbackState = playing ? 'playing' : 'paused';
  } catch (_) {}
}
