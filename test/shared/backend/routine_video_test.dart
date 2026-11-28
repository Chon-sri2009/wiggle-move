import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/routine_video.dart';
import 'package:wiggle_move/shared/backend/storage_url.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';

void main() {
  test('public storage URLs encode the path and tolerate a trailing slash', () {
    expect(
      publicStorageUrl('b', 'a/x y.mp4', base: 'https://p.supabase.co/'),
      'https://p.supabase.co/storage/v1/object/public/b/a/x%20y.mp4',
    );
  });

  test('no path or no backend means no URL', () {
    expect(routineVideoUrl(null, base: 'https://p'), isNull);
    expect(routineVideoUrl('', base: 'https://p'), isNull);
    expect(routineVideoUrl('a.mp4', base: ''), isNull);
    expect(
      routineVideoUrl('pop.mp4', base: 'https://p'),
      'https://p/storage/v1/object/public/routine-videos/pop.mp4',
    );
  });

  test('video_path round trips; empty is none; wrong type is malformed', () {
    final json = builtInTrainers.first.routines.first.toJson();
    expect(json.containsKey('video_path'), isFalse);
    expect(Routine.fromJson(json).videoPath, isNull);
    expect(Routine.fromJson({...json, 'video_path': ''}).videoPath, isNull);
    final r = Routine.fromJson({...json, 'video_path': 'pop.mp4'});
    expect(r.videoPath, 'pop.mp4');
    expect(Routine.fromJson(r.toJson()).videoPath, 'pop.mp4');
    expect(
      () => Routine.fromJson({...json, 'video_path': 3}),
      throwsFormatException,
    );
  });
}
