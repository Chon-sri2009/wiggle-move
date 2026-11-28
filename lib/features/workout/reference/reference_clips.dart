import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reference_clip.dart';

/// The trainer video of a routine and the timeline made from it.
class ReferenceAsset {
  const ReferenceAsset({required this.video, required this.timeline});
  final String video;
  final String timeline;
}

/// Routines that have a trainer video to follow, by routine id. Add an entry
/// after running `tool/pose_model/video_to_timeline.py` on the video (and
/// declare both files under `flutter: assets:`).
const referenceAssets = <String, ReferenceAsset>{
  'video-squat-demo': ReferenceAsset(
    video: 'assets/videos/squat_reference.mp4',
    timeline: 'assets/reference/squat.timeline.json',
  ),
  'video-workout-30': ReferenceAsset(
    video: 'assets/videos/workout30.mp4',
    timeline: 'assets/reference/workout30.timeline.json',
  ),
};

/// The timeline for a routine, or null when it has no trainer video.
final referenceClipProvider = FutureProvider.family<ReferenceClip?, String>((
  ref,
  routineId,
) async {
  final asset = referenceAssets[routineId];
  if (asset == null) return null;
  final json = jsonDecode(await rootBundle.loadString(asset.timeline));
  return ReferenceClip.fromJson(json);
});
