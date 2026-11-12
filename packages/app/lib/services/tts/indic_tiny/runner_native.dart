import 'flutter_onnx_runner.dart';
import 'onnx_runner.dart';

/// Android / iOS: ONNX Runtime Mobile through flutter_onnxruntime.
OnnxRunner createOnnxRunner(Map<String, String> locations, {int threads = 2}) => FlutterOnnxRunner(locations, threads: threads);
