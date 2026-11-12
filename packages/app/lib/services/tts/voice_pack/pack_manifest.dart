/// One file of the voice pack: where it lives in the pinned Hugging Face revision, how big it is, and its SHA-256.
class PackFile {
  const PackFile(this.name, this.path, this.bytes, this.sha256);

  /// Name on disk inside the pack folder.
  final String name;

  /// Path inside the Hugging Face repository.
  final String path;
  final int bytes;
  final String sha256;
}

/// The voice pack the app downloads after install: Indic Tiny TTS Telugu (female + male), three ONNX graphs and the config.
///
/// Everything is pinned: the Hugging Face commit, every file's size and SHA-256. A file that does not match is deleted and
/// the install fails; nothing unverified is ever loaded.
class VoicePackManifest {
  const VoicePackManifest({
    required this.id,
    required this.version,
    required this.repo,
    required this.revision,
    required this.files,
  });

  final String id;

  /// Folder name under the pack id; bump together with [revision] so an old pack is kept until the new one is verified.
  final String version;
  final String repo;
  final String revision;
  final List<PackFile> files;

  int get totalBytes => files.fold(0, (a, f) => a + f.bytes);

  Uri urlFor(PackFile f) => Uri.parse('https://huggingface.co/$repo/resolve/$revision/${f.path}');

  PackFile file(String name) => files.firstWhere((f) => f.name == name);

  /// Indic Tiny TTS Telugu, Hugging Face commit 55cfc683… (2026-11-04). Hashes were measured on the downloaded files.
  static const indicTinyTelugu = VoicePackManifest(
    id: 'indic-tiny-te',
    version: '1-55cfc683',
    repo: 'sulabhkatiyar/indic-tiny-tts-telugu',
    revision: '55cfc683fafb55326a0a01932a3b2bb4374c4fc0',
    files: [
      PackFile('config.json', 'config.json', 3067, 'f745efbe7681ead8abed6be5b6ca4dc21762c870fa37810c0a06ed61bbb507f4'),
      PackFile('onnx_manifest.json', 'onnx/onnx_manifest.json', 3114,
          '9279ccdf26a12edbd138388b2ccf5f61237dee1063ed9eff885c76053efd61a6'),
      PackFile('LICENSE.md', 'LICENSE.md', 3333, '2e840a66bc2671deac72f5aff077e2385390ea2ef6de704c26aa0389372ee380'),
      PackFile('text_encoder.onnx', 'onnx/text_encoder.onnx', 17692254,
          '728d9c2529e00d30de480c598369fad24919f83cd0ac44994a64724bbd3e3839'),
      PackFile('flow_decoder.onnx', 'onnx/flow_decoder.onnx', 19169253,
          'a523c39fe6b5df3a8cc76953fce9572ea6b7d3b8677d9232a4d5968fec75c40d'),
      PackFile('vocoder.onnx', 'onnx/vocoder.onnx', 54150036,
          '44d36238a761750447038895ab194e2378f6f4ba2c2d089a4766fa52810ef353'),
    ],
  );
}

/// Attribution text for the credits screen (CC-BY-4.0 requires credit to the model and to the Rasa dataset).
const voicePackCredits = '''Telugu on-device voice: Indic Tiny TTS Telugu by Sulabh Katiyar (https://huggingface.co/sulabhkatiyar/indic-tiny-tts-telugu), licensed CC-BY-4.0 (https://creativecommons.org/licenses/by/4.0/). The model code is MIT.
Voices trained on the Telugu part of the Rasa dataset by AI4Bharat (CC-BY-4.0, https://huggingface.co/datasets/ai4bharat/Rasa): Praveen Srinivasa Varadhan, Ashwin Sankar, Giri Raju and Mitesh M. Khapra, "Rasa: Building Expressive Speech Synthesis Systems for Indian Languages in Low-resource Settings", INTERSPEECH 2024. Changes by the model author: audio resampled to 24 kHz, some clips removed, text normalised.
Vocoder: Vocos (charactr/vocos-mel-24khz), MIT licence. Number-to-words tables: indic_numtowords by AI4Bharat, MIT licence.
GatiVani changes: the model is run unchanged in ONNX Runtime (MIT); the app adds its own Telugu text normaliser.''';
