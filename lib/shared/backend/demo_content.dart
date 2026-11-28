import 'dart:ui' show Color;

import '../pose/pose_math.dart';
import 'content_models.dart';

/// Offline-only demo of "follow the trainer video": the workout plays
/// `assets/videos/squat_reference.mp4` and judges the user against the
/// trainer's moves in it (`referenceAssets` in features/workout/reference).
/// Not part of `builtInTrainers`, so it is not in `supabase/seed.sql`.
///
/// The target below is only the fallback for frames the video timeline cannot
/// judge. The move lasts as long as the clip (3 min 10 s).
const demoRoutineId = 'video-squat-demo';
const squatVideoDurationMs = 189720;

/// The 33-minute full-body cardio workout (the team's own video). The move
/// lasts as long as the clip; the trainer's pose at each moment comes from
/// `assets/reference/workout30.timeline.json`.
const workoutVideoRoutineId = 'video-workout-30';
const workoutVideoDurationMs = 1975033;

final demoTrainer = Trainer(
  id: 'video-coach',
  name: 'Video Coach (demo)',
  style: 'Follow the video',
  color: const Color(0xFF1ADBC1),
  routines: [
    Routine(
      id: demoRoutineId,
      name: 'Follow the video: Squat',
      level: 'Medium',
      category: Routine.cardio,
      sets: 1,
      restMs: 8000,
      met: 5,
      moves: [
        Move(
          name: 'Squat with the video',
          instruction: 'Copy the trainer on screen',
          durationMs: squatVideoDurationMs,
          target: MoveTarget({Joint.leftKnee: 100, Joint.rightKnee: 100}),
        ),
      ],
    ),
    Routine(
      id: workoutVideoRoutineId,
      name: 'Follow the video: 30 min cardio',
      level: 'Medium',
      category: Routine.cardio,
      met: 6,
      moves: [
        Move(
          name: 'Follow the trainer',
          instruction: 'Copy the trainer on screen for the whole workout',
          durationMs: workoutVideoDurationMs,
          // Only the fallback for frames the video timeline cannot judge.
          target: MoveTarget({Joint.leftKnee: 170, Joint.rightKnee: 170}),
        ),
      ],
    ),
  ],
);
