import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_cache.dart';
import 'audio_cache_factory.dart';
import 'indic_tiny/config.dart';
import 'indic_tiny/engine.dart';
import 'indic_tiny/runner_factory.dart';
import 'on_device_output.dart';
import 'sentence_reader.dart';
import 'system_voice_output.dart';
import 'tts_engine.dart';
import 'voice_pack/pack_manifest.dart';
import 'voice_pack/voice_pack_store.dart';
import 'voice_pack/voice_pack_store_factory.dart';

/// Which voice reads a story. `auto` = on-device model when its voice pack is installed, else the device voice, else the cloud.
enum NarrationEngine { auto, onDevice, system, cloud }

enum PackStatus { unknown, notInstalled, installing, installed, failed }

/// Settings + voice-pack state + reader factory for on-device narration. [readerFor] returns null when the story should go to
/// the cloud path (the app's existing server narration).
///
/// Memory: the ONNX sessions (about 91 MB of weights) are created on the first sentence, shared by every reader, and closed
/// [idleRelease] after the last reader stopped, so a listener who stops does not keep the model resident.
class NarrationController extends ChangeNotifier {
  NarrationController._({
    VoicePackStore? store,
    AudioCache? cache,
    this.idleRelease = const Duration(seconds: 90),
    Future<bool> Function()? systemVoiceAvailable,
    Future<TtsEngine> Function(VoicePackStore store)? engineBuilder,
    WavPlayer Function()? playerFactory,
    SentenceOutput Function()? systemOutputFactory,
  })  : store = store ?? createVoicePackStore(VoicePackManifest.indicTinyTelugu),
        _cache = cache ?? LayeredAudioCache(MemoryAudioCache(), createDiskAudioCache()),
        _systemAvailable = systemVoiceAvailable ?? _deviceHasTeluguVoice,
        _engineBuilder = engineBuilder ?? _buildEngine,
        _playerFactory = playerFactory ?? JustAudioWavPlayer.new,
        _systemOutput = systemOutputFactory ?? SystemVoiceOutput.new;

  static final NarrationController i = NarrationController._();

  /// For tests and for building a controller with fakes.
  @visibleForTesting
  factory NarrationController.test({
    required VoicePackStore store,
    required AudioCache cache,
    required Future<bool> Function() systemVoiceAvailable,
    required Future<TtsEngine> Function(VoicePackStore store) engineBuilder,
    required WavPlayer Function() playerFactory,
    required SentenceOutput Function() systemOutputFactory,
    Duration idleRelease = const Duration(seconds: 90),
  }) =>
      NarrationController._(
        store: store,
        cache: cache,
        idleRelease: idleRelease,
        systemVoiceAvailable: systemVoiceAvailable,
        engineBuilder: engineBuilder,
        playerFactory: playerFactory,
        systemOutputFactory: systemOutputFactory,
      );

  final VoicePackStore store;
  final AudioCache _cache;
  final Duration idleRelease;
  final Future<bool> Function() _systemAvailable;
  final Future<TtsEngine> Function(VoicePackStore store) _engineBuilder;
  final WavPlayer Function() _playerFactory;
  final SentenceOutput Function() _systemOutput;

  static const _kEngine = 'tts_engine';
  static const _kVoice = 'tts_voice';

  NarrationEngine engine = NarrationEngine.auto;

  /// Local review build only: false keeps text from ever reaching a browser's speech service (some browsers' Telugu voices are online).
  bool allowSystemVoice = true;
  String voice = 'female'; // 'female' | 'male'
  PackStatus packStatus = PackStatus.unknown;
  int packDone = 0;
  int packTotal = VoicePackManifest.indicTinyTelugu.totalBytes;
  String? packError;
  bool? _systemOk;
  CancelFlag? _cancel;

  static Future<bool> _deviceHasTeluguVoice() async {
    try {
      final ok = await FlutterTts().isLanguageAvailable('te-IN');
      return ok == true || ok == 1;
    } catch (_) {
      return false;
    }
  }

  static Future<TtsEngine> _buildEngine(VoicePackStore store) async {
    final config = IndicTinyConfig.fromJson(await store.readText('config.json'), await store.readText('onnx_manifest.json'));
    final runner = createOnnxRunner(await store.modelLocations(), threads: 2);
    return IndicTinyEngine(config: config, runner: runner);
  }

  /// Read the saved choices and look at the voice pack. Call once at start-up (or when the Voice settings open).
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      engine = NarrationEngine.values.firstWhere((e) => e.name == p.getString(_kEngine), orElse: () => NarrationEngine.auto);
      final v = p.getString(_kVoice);
      if (v == 'female' || v == 'male') voice = v!;
    } catch (_) {}
    if (packStatus != PackStatus.installing) {
      packStatus = await store.isInstalled() ? PackStatus.installed : PackStatus.notInstalled;
    }
    notifyListeners();
  }

  Future<void> setEngine(NarrationEngine e) async {
    engine = e;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_kEngine, e.name);
    } catch (_) {}
  }

  Future<void> setVoice(String v) async {
    voice = v;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_kVoice, v);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ voice pack
  Future<void> installPack() async {
    if (packStatus == PackStatus.installing) return;
    packStatus = PackStatus.installing;
    packError = null;
    packDone = 0;
    final cancel = _cancel = CancelFlag();
    notifyListeners();
    try {
      await store.install(
        cancel: cancel,
        onProgress: (d, t) {
          packDone = d;
          packTotal = t;
          notifyListeners();
        },
      );
      packStatus = PackStatus.installed;
    } on DownloadCancelled {
      packStatus = PackStatus.notInstalled;
    } catch (e) {
      packStatus = PackStatus.failed;
      packError = e.toString();
    }
    _cancel = null;
    notifyListeners();
  }

  void cancelInstall() => _cancel?.cancelled = true;

  Future<void> deletePack() async {
    await _releaseEngine();
    await store.delete();
    await _cache.clear();
    packStatus = PackStatus.notInstalled;
    packError = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ readers
  Future<bool> _hasSystemVoice() async => _systemOk ??= await _systemAvailable();

  int _readers = 0;
  Timer? _idle;
  Future<TtsEngine>? _engineFuture;
  TtsEngine? _engineOpen;

  Future<TtsEngine> _sharedEngine() {
    _idle?.cancel();
    return _engineFuture ??= _engineBuilder(store).then((e) => _engineOpen = e).catchError((Object e) {
      _engineFuture = null;
      throw e;
    });
  }

  Future<void> _releaseEngine() async {
    _idle?.cancel();
    final f = _engineFuture;
    _engineFuture = null;
    _engineOpen = null;
    if (f != null) {
      try {
        await (await f).dispose();
      } catch (_) {}
    }
  }

  void _readerClosed() {
    if (--_readers > 0) return;
    _readers = 0;
    _idle?.cancel();
    _idle = Timer(idleRelease, () => unawaited(_releaseEngine()));
  }

  /// A reader for [text], or null when the cloud path should narrate it.
  Future<SentenceReader?> readerFor(String text, {int startIndex = 0}) async {
    final installed = packStatus == PackStatus.installed || (packStatus == PackStatus.unknown && await store.isInstalled());
    final system = allowSystemVoice && engine != NarrationEngine.cloud && await _hasSystemVoice();
    SentenceOutput? primary;
    SentenceOutput? fallback;
    SentenceOutput onDevice() => OnDeviceOutput(
          engineFactory: () async => _SharedEngine(await _sharedEngine()),
          voice: voice,
          cache: _cache,
          packVersion: store.manifest.version,
          player: _playerFactory(),
        );
    switch (engine) {
      case NarrationEngine.cloud:
        return null;
      case NarrationEngine.system:
        if (!system) return null;
        primary = _systemOutput();
      case NarrationEngine.onDevice:
      case NarrationEngine.auto:
        if (installed) {
          primary = onDevice();
          if (system) fallback = _systemOutput();
        } else if (system) {
          primary = _systemOutput();
        } else {
          return null;
        }
    }
    _readers++;
    final r = _ClosingReader(primary: primary, fallback: fallback, onClosed: _readerClosed);
    r.load(text, startIndex: startIndex);
    return r;
  }

  @visibleForTesting
  bool get engineResident => _engineOpen != null;

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }
}

/// Tells the controller when a reader is gone so the shared model can be released.
class _ClosingReader extends SentenceReader {
  _ClosingReader({required super.primary, super.fallback, required this.onClosed});
  final void Function() onClosed;
  bool _closed = false;

  @override
  void dispose() {
    if (!_closed) {
      _closed = true;
      onClosed();
    }
    super.dispose();
  }
}

/// The shared engine as seen by one reader: disposing the reader must not close the model the next reader will use.
class _SharedEngine implements TtsEngine {
  _SharedEngine(this._e);
  final TtsEngine _e;
  @override
  String get id => _e.id;
  @override
  List<String> get voices => _e.voices;
  @override
  Future<void> init() => _e.init();
  @override
  Future<TtsAudio> synthesize(String text, {String? voice, double speed = 1.0}) =>
      _e.synthesize(text, voice: voice, speed: speed);
  @override
  Future<void> dispose() async {}
}
