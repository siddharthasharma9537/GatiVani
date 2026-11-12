import 'pack_manifest.dart';

/// Set [cancelled] to stop an install between chunks; the partial download is kept so the next install resumes.
class CancelFlag {
  bool cancelled = false;
}

class InsufficientSpaceException implements Exception {
  InsufficientSpaceException(this.neededBytes, this.freeBytes);
  final int neededBytes;
  final int freeBytes;
  @override
  String toString() => 'Not enough storage: need ${neededBytes ~/ (1024 * 1024)} MB, free ${freeBytes ~/ (1024 * 1024)} MB';
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelled';
}

class HashMismatch implements Exception {
  HashMismatch(this.file, this.expected, this.actual);
  final String file;
  final String expected;
  final String actual;
  @override
  String toString() => 'Voice pack file $file failed verification (expected SHA-256 $expected, got $actual)';
}

/// Where the voice pack lives on this platform: files in the app-support folder on Android/iOS, the browser's Cache Storage on
/// the web. Versioned: the folder name includes [VoicePackManifest.version], and an older version is removed only after the new
/// one is fully verified.
abstract class VoicePackStore {
  VoicePackManifest get manifest;

  /// True when every file of [manifest] is present and verified.
  Future<bool> isInstalled();

  /// Bytes the installed pack occupies (0 when not installed).
  Future<int> installedBytes();

  /// Free storage in bytes, or null when the platform cannot say.
  Future<int?> freeBytes();

  /// Download and verify everything not already on disk. [onProgress] gets (bytes done, bytes total) over the whole pack.
  /// Throws [InsufficientSpaceException], [DownloadCancelled] or [HashMismatch].
  Future<void> install({void Function(int done, int total)? onProgress, CancelFlag? cancel});

  /// Remove the pack, including partial downloads.
  Future<void> delete();

  /// Text of a small file of the pack (config.json, onnx_manifest.json, LICENSE.md).
  Future<String> readText(String name);

  /// Graph name -> what the ONNX runtime opens: a file path on Android/iOS, a blob URL on the web.
  Future<Map<String, String>> modelLocations();
}
