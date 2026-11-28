// ignore_for_file: avoid_print
// Checks the pure-Dart engine against the original tfjs outputs written by
// `ref.js`. Run from the project root:
//   dart run tool/pose_model/parity_engine.dart <scratch>/ref/out
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wiggle_move/features/workout/form/posenet_engine.dart';

void main(List<String> args) {
  final dir = Directory(args.single);
  final engine = PoseNetEngine.fromBytes(
    File('assets/models/posenet_075_stride16.bin').readAsBytesSync(),
    File('assets/models/form_head.bin').readAsBytesSync(),
  );
  var worstFeat = 0.0, worstProb = 0.0;
  for (final f
      in dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.resized.f32'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path))) {
    final name = f.uri.pathSegments.last.split('.').first;
    final input = Float32List.sublistView(f.readAsBytesSync());
    final refFeat = Float32List.sublistView(
      File('${dir.path}/$name.feat.f32').readAsBytesSync(),
    );
    final refProbs = (jsonDecode(
      File('${dir.path}/$name.probs.json').readAsStringSync(),
    ) as List).cast<num>();
    final sw = Stopwatch()..start();
    final features = engine.featuresOf(input);
    final probs = engine.classify(features);
    sw.stop();
    var df = 0.0, dp = 0.0;
    for (var i = 0; i < features.length; i++) {
      final d = (features[i] - refFeat[i]).abs();
      if (d > df) df = d;
    }
    for (var i = 0; i < probs.length; i++) {
      final d = (probs[i] - refProbs[i]).abs();
      if (d > dp) dp = d;
    }
    if (df > worstFeat) worstFeat = df;
    if (dp > worstProb) worstProb = dp;
    print(
      '$name feat maxdiff ${df.toStringAsExponential(2)} prob maxdiff ${dp.toStringAsExponential(2)} ${sw.elapsedMilliseconds} ms',
    );
  }
  print('WORST feat $worstFeat prob $worstProb');
}
