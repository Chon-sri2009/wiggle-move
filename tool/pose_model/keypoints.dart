// ignore_for_file: avoid_print
// Prints the decoded keypoints of a 257x257x3 float32 RGB file as JSON.
//   dart run tool/pose_model/keypoints.dart <file.resized.f32>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wiggle_move/features/workout/form/posenet_engine.dart';

void main(List<String> args) {
  final engine = PoseNetEngine.fromBytes(
    File('assets/models/posenet_075_stride16.bin').readAsBytesSync(),
    File('assets/models/form_head.bin').readAsBytesSync(),
  );
  final out = engine.run(
    Float32List.sublistView(File(args.single).readAsBytesSync()),
  );
  print(
    jsonEncode([
      for (final k in out.keypoints) [k.x, k.y, k.score],
    ]),
  );
}
