import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feedback the user feels (and, later, hears) during a workout. The screen
/// only calls these; a sound implementation can replace [HapticCues] through
/// [workoutCuesProvider] without touching the screen.
abstract class WorkoutCues {
  /// Each countdown number before the workout starts.
  void countdownTick();

  /// The workout starts.
  void go();

  /// A new move, set or rest begins.
  void segmentChanged();

  /// One more rep was counted.
  void repCounted();

  /// The routine is finished.
  void finished();
}

class HapticCues implements WorkoutCues {
  const HapticCues();

  @override
  void countdownTick() => HapticFeedback.selectionClick();

  @override
  void go() => HapticFeedback.mediumImpact();

  @override
  void segmentChanged() => HapticFeedback.lightImpact();

  @override
  void repCounted() => HapticFeedback.selectionClick();

  @override
  void finished() => HapticFeedback.heavyImpact();
}

final workoutCuesProvider = Provider<WorkoutCues>((_) => const HapticCues());
