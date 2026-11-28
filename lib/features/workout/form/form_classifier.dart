import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'frame_preprocess.dart';

/// Runs the trained form model on one preprocessed frame.
abstract class FormClassifier {
  /// Class names, in the order of the probabilities [classify] returns.
  List<String> get labels;

  /// [input] is `modelInputSize`² x 3 RGB floats (see `preprocessFrame`);
  /// returns one probability per label.
  List<double> classify(Float32List input);

  void close();
}

const _modelAsset = 'assets/models/pose_classifier.tflite';
const _labelsAsset = 'assets/models/pose_labels.json';

/// The Teachable Machine pose model (PoseNet MobileNetV1 0.75 + classifier
/// head), converted to one TFLite file with `tool/pose_model/`.
class TfliteFormClassifier implements FormClassifier {
  TfliteFormClassifier._(this._interpreter, this.labels);

  final Interpreter _interpreter;

  @override
  final List<String> labels;

  static Future<TfliteFormClassifier> load() async {
    final labels = (jsonDecode(
      await rootBundle.loadString(_labelsAsset),
    ) as List<dynamic>).cast<String>();
    final interpreter = await Interpreter.fromAsset(
      _modelAsset,
      options: InterpreterOptions()..threads = 2,
    );
    final outputs = interpreter.getOutputTensor(0).shape.last;
    if (outputs != labels.length) {
      interpreter.close();
      throw StateError(
        'Model has $outputs classes, labels file has ${labels.length}',
      );
    }
    return TfliteFormClassifier._(interpreter, labels);
  }

  @override
  List<double> classify(Float32List input) {
    assert(input.length == modelInputSize * modelInputSize * 3);
    _interpreter.getInputTensor(0).data = input.buffer.asUint8List(
      input.offsetInBytes,
      input.lengthInBytes,
    );
    _interpreter.invoke();
    final bytes = _interpreter.getOutputTensor(0).data;
    final probs = Float32List.fromList(
      bytes.buffer.asFloat32List(bytes.offsetInBytes, labels.length),
    );
    return probs;
  }

  @override
  void close() => _interpreter.close();
}
