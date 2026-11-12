import 'dart:typed_data';

/// A tensor handed to / returned from an ONNX session. Either float32 or int64.
class Tensor {
  Tensor.f32(this.shape, Float32List data)
      : floats = data,
        ints = null;
  Tensor.i64(this.shape, List<int> data)
      : ints = data,
        floats = null;

  final List<int> shape;
  final Float32List? floats;
  /// Plain ints: dart2js has no Int64List, so the runners build the 64-bit buffer themselves.
  final List<int>? ints;
}

/// Runs one of the model's three ONNX graphs (`text_encoder`, `flow_decoder`, `vocoder`). The engine only talks to this
/// interface, so the pipeline can be tested without a runtime, and the runtime can differ per platform (ONNX Runtime
/// Mobile on Android/iOS, ONNX Runtime Web in the browser).
abstract class OnnxRunner {
  /// Load the graphs from [modelDir] (a folder holding `onnx/*.onnx`), or from bundled assets.
  Future<void> load();

  /// Run [graph] with named inputs; outputs come back in the graph's output order.
  Future<List<Tensor>> run(String graph, Map<String, Tensor> inputs);

  Future<void> dispose();
}
