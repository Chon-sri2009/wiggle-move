import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/workout/form/keypoint_landmarks.dart';
import 'package:wiggle_move/features/workout/form/posenet_engine.dart';
import 'package:wiggle_move/shared/pose/pose_math.dart';

void main() {
  test('pure-Dart engine reproduces the TFLite/Keras model', () {
    // Reference values: the Keras port (itself checked against tfjs) on
    // input[i] = (i * 37) % 256.
    final ref = jsonDecode(
      File('test/features/workout/form/engine_fixture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final engine = PoseNetEngine.fromBytes(
      File('assets/models/posenet_075_stride16.bin').readAsBytesSync(),
      File('assets/models/form_head.bin').readAsBytesSync(),
    );
    final input = Float32List(257 * 257 * 3);
    for (var i = 0; i < input.length; i++) {
      input[i] = ((i * 37) % 256).toDouble();
    }
    final features = engine.featuresOf(input);
    final refFeat = (ref['feat'] as List<dynamic>).cast<num>();
    for (var i = 0; i < refFeat.length; i++) {
      expect(features[i * 211], closeTo(refFeat[i].toDouble(), 0.02));
    }
    final probs = engine.classify(features);
    final refProbs = (ref['probs'] as List<dynamic>).cast<num>();
    for (var i = 0; i < refProbs.length; i++) {
      expect(probs[i], closeTo(refProbs[i].toDouble(), 2e-3));
    }
    expect(features, hasLength(14739));
    expect(engine.decodeKeypoints(features), hasLength(17));
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('landmarksFromKeypoints', () {
    List<PoseKeypoint> kps({double score = 0.9}) => [
      for (final part in PosePart.values)
        PoseKeypoint(part.index.toDouble(), 2.0 * part.index, score),
    ];

    test('keeps sides when not mirrored', () {
      final p = landmarksFromKeypoints(kps(), mirrored: false);
      expect(p[Lm.leftShoulder]!.x, PosePart.leftShoulder.index);
      expect(p[Lm.rightKnee]!.x, PosePart.rightKnee.index);
    });

    test('swaps sides for a mirrored image', () {
      final p = landmarksFromKeypoints(kps(), mirrored: true);
      expect(p[Lm.leftShoulder]!.x, PosePart.rightShoulder.index);
      expect(p[Lm.rightAnkle]!.x, PosePart.leftAnkle.index);
    });

    test('drops low-score points and face parts', () {
      expect(landmarksFromKeypoints(kps(score: 0.1), mirrored: false), isEmpty);
      expect(landmarksFromKeypoints(kps(), mirrored: false), hasLength(12));
    });
  });
}
