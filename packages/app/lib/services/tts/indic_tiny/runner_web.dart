import 'onnx_runner.dart';
import 'web_ort_runner.dart';

/// Browser: ONNX Runtime Web directly (int64 inputs need BigInt64Array).
OnnxRunner createOnnxRunner(Map<String, String> locations, {int threads = 2}) => WebOrtRunner(locations, threads: threads);
