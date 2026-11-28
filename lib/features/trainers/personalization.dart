import '../../shared/backend/content_models.dart';
import '../../shared/backend/profile.dart';

// Home personalization: order trainers and routines by how well they fit the
// profile's level and styles. Nothing is hidden (a new routine must stay
// discoverable); the best fits come first and are marked "Recommended".
// Pure Dart, so it is unit-tested without Flutter.

/// Routine category a profile style asks for (`profile_options.dart` labels).
/// Styles with no content yet ('Bodyweight', 'Stretching') map to nothing.
const _styleCategory = {
  'Dance Workout': Routine.dance,
  'Cardio': Routine.cardio,
};

/// Position of a profile level / routine level on one difficulty scale.
const _profileLevelRank = {'Beginner': 0, 'Intermediate': 1, 'Advanced': 2};
const _routineLevelRank = {'Easy': 0, 'Medium': 1, 'Hard': 2};

/// Lower is a better fit. Unknown answers are neutral, so a profile with no
/// styles or level leaves the server order untouched.
int routineFit(Routine routine, Profile profile) {
  final categories = {for (final s in profile.styles) ?_styleCategory[s]};
  final styleMiss = categories.isEmpty || categories.contains(routine.category)
      ? 0
      : 10;
  final wanted = _profileLevelRank[profile.level];
  final has = _routineLevelRank[routine.level];
  final levelGap = wanted == null || has == null ? 0 : (wanted - has).abs();
  return styleMiss + levelGap;
}

/// Whether [routine] is a good fit on both counts (worth a badge). False when
/// the profile gives nothing to match on.
bool isRecommended(Routine routine, Profile profile) {
  final hasAnswers =
      profile.level != null || profile.styles.any(_styleCategory.containsKey);
  return hasAnswers && routineFit(routine, profile) == 0;
}

/// [routines] best fit first; equal fits keep their given order.
List<Routine> rankRoutines(List<Routine> routines, Profile profile) {
  final indexed = [
    for (final (i, r) in routines.indexed) (i, r, routineFit(r, profile)),
  ]..sort((a, b) => a.$3 != b.$3 ? a.$3.compareTo(b.$3) : a.$1.compareTo(b.$1));
  return [for (final e in indexed) e.$2];
}

/// [trainers] ordered by their best-fitting routine (equal fits keep their
/// given order). A trainer's own routines are ordered by [rankRoutines].
List<Trainer> rankTrainers(List<Trainer> trainers, Profile profile) {
  int best(Trainer t) => t.routines.isEmpty
      ? 1 << 20
      : t.routines
            .map((r) => routineFit(r, profile))
            .reduce((a, b) => a < b ? a : b);
  final indexed = [
    for (final (i, t) in trainers.indexed) (i, t, best(t)),
  ]..sort((a, b) => a.$3 != b.$3 ? a.$3.compareTo(b.$3) : a.$1.compareTo(b.$1));
  return [for (final e in indexed) e.$2];
}

/// Whether any routine of [trainer] is recommended.
bool trainerRecommended(Trainer trainer, Profile profile) =>
    trainer.routines.any((r) => isRecommended(r, profile));
