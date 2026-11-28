import 'dart:ui' show Color;

import '../pose/pose_math.dart';

// Content models (trainers -> routines -> moves) and their JSON codec.
//
// `fromRow` reads the nested PostgREST shape of
// `trainers.select('*, routines(*, moves(*))')` and sorts children by
// `sort_order` / `idx`. `toJson` / `fromJson` are the on-device cache format
// (children already in order). Any malformed input throws [FormatException].

/// How reps of a move are counted: [joint]'s angle must reach [low] and come
/// back up to [high] ([RepCounter]); [target] reps make a full set of it.
class RepSpec {
  const RepSpec({
    required this.target,
    required this.joint,
    required this.low,
    required this.high,
  });
  final int target;
  final Joint joint;
  final double low;
  final double high;
}

class Move {
  const Move({
    required this.name,
    required this.instruction,
    required this.target,
    this.durationMs = 4000,
    this.rep,
  });
  final String name;
  final String instruction;
  final MoveTarget target;
  final int durationMs;

  /// Null for a timed pose; set for a counted (cardio) move, where
  /// [durationMs] is the time allowed per set.
  final RepSpec? rep;

  factory Move.fromJson(Object? json) => _parse('move', () {
    final m = _map(json);
    return Move(
      name: m['name'] as String,
      instruction: m['instruction'] as String,
      durationMs: _positiveInt(m['duration_ms']),
      target: targetFromJson(m['target_angles']),
      rep: _repFrom(m),
    );
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'instruction': instruction,
    'duration_ms': durationMs,
    'target_angles': targetToJson(target),
    if (rep case final r?) ...{
      'reps': r.target,
      'rep_joint': r.joint.name,
      'rep_low': r.low,
      'rep_high': r.high,
    },
  };
}

class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.level,
    required this.moves,
    this.category = dance,
    this.sets = 1,
    this.restMs = 0,
    this.met = 3.5,
    this.videoPath,
  });
  static const dance = 'dance';
  static const cardio = 'cardio';
  static const categories = [dance, cardio];

  final String id;
  final String name;
  final String level;
  final List<Move> moves;

  /// [dance] or [cardio] (matches `routines.category`).
  final String category;

  /// How many times the move list is played, with [restMs] between sets.
  final int sets;
  final int restMs;

  /// Intensity for the calorie estimate (see `estimateCalories`).
  final double met;

  /// Object path in the `routine-videos` bucket (see `routineVideoUrl`); null
  /// = no demonstration video.
  final String? videoPath;

  bool get isCardio => category == cardio;

  /// One set: the sum of the moves (equals `routines.duration_ms`).
  int get durationMs => moves.fold(0, (sum, m) => sum + m.durationMs);

  /// The whole play: every set plus the rests between them.
  int get totalDurationMs => durationMs * sets + restMs * (sets - 1);

  factory Routine.fromRow(Object? row) => _routine(row, sorted: true);

  factory Routine.fromJson(Object? json) => _routine(json, sorted: false);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'level': level,
    'category': category,
    'sets': sets,
    'rest_ms': restMs,
    'met': met,
    if (videoPath != null) 'video_path': videoPath,
    'moves': [for (final m in moves) m.toJson()],
  };
}

class Trainer {
  const Trainer({
    required this.id,
    required this.name,
    required this.style,
    required this.color,
    required this.routines,
    this.photoPath,
  });
  final String id;
  final String name;
  final String style;
  final Color color;
  final List<Routine> routines;

  /// Object path in the `trainer-photos` Storage bucket (see
  /// `trainerPhotoUrl`); null = no photo, the avatar shows the initial.
  final String? photoPath;

  /// One `trainers` row with embedded `routines(*, moves(*))`.
  factory Trainer.fromRow(Object? row) => _trainer(row, sorted: true);

  factory Trainer.fromJson(Object? json) => _trainer(json, sorted: false);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'style': style,
    'color': color.toARGB32(),
    if (photoPath != null) 'photo_path': photoPath,
    'routines': [for (final r in routines) r.toJson()],
  };
}

/// All trainers from the PostgREST response, ordered by `sort_order`.
List<Trainer> trainersFromRows(Object? rows) => _parse('trainers', () {
  final list = _sortedBy(_list(rows), 'sort_order');
  return [for (final row in list) Trainer.fromRow(row)];
});

List<Trainer> trainersFromJson(Object? json) => _parse(
  'trainers',
  () => [for (final t in _list(json)) Trainer.fromJson(t)],
);

List<Map<String, Object?>> trainersToJson(List<Trainer> trainers) => [
  for (final t in trainers) t.toJson(),
];

/// `moves.target_angles`: `{"leftShoulder": 165, ...}` keyed by [Joint.name].
MoveTarget targetFromJson(Object? json) => _parse('target_angles', () {
  final m = _map(json);
  if (m.isEmpty) throw const FormatException('no target angles');
  return MoveTarget({
    for (final e in m.entries)
      Joint.values.byName(e.key): (e.value as num).toDouble(),
  });
});

Map<String, Object?> targetToJson(MoveTarget target) => {
  for (final e in target.angles.entries) e.key.name: e.value,
};

Trainer _trainer(Object? json, {required bool sorted}) => _parse('trainer', () {
  final m = _map(json);
  final color = m['color'] as int;
  if (color < 0 || color > 0xFFFFFFFF) {
    throw const FormatException('color out of range');
  }
  final name = m['name'] as String;
  // The UI derives the avatar initial from the name.
  if (name.trim().isEmpty) throw const FormatException('blank trainer name');
  final routines = _list(m['routines']);
  return Trainer(
    id: m['id'] as String,
    name: name,
    style: m['style'] as String,
    color: Color(color),
    photoPath: _optionalString(m['photo_path']),
    routines: [
      for (final r in sorted ? _sortedBy(routines, 'sort_order') : routines)
        _routine(r, sorted: sorted),
    ],
  );
});

Routine _routine(Object? json, {required bool sorted}) => _parse('routine', () {
  final m = _map(json);
  final moves = _list(m['moves']);
  // The DB does not require move rows; a workout needs at least one.
  if (moves.isEmpty) throw const FormatException('routine has no moves');
  return Routine(
    id: m['id'] as String,
    name: m['name'] as String,
    level: m['level'] as String,
    // Missing keys (old cache, or a DB without the cardio migration) mean a
    // plain single-set dance routine; a wrong type or value still throws.
    category: _category(m['category']),
    sets: _intOr(m['sets'], 1, min: 1),
    restMs: _intOr(m['rest_ms'], 0, min: 0),
    met: _metOr(m['met']),
    videoPath: _optionalString(m['video_path']),
    moves: [
      for (final mv in sorted ? _sortedBy(moves, 'idx') : moves)
        Move.fromJson(mv),
    ],
  );
});

RepSpec? _repFrom(Map<String, Object?> m) {
  final reps = m['reps'];
  if (reps == null) {
    if (m['rep_joint'] != null ||
        m['rep_low'] != null ||
        m['rep_high'] != null) {
      throw const FormatException('rep fields without reps');
    }
    return null;
  }
  final low = (m['rep_low'] as num).toDouble();
  final high = (m['rep_high'] as num).toDouble();
  if (low >= high) {
    throw const FormatException('rep_low must be below rep_high');
  }
  return RepSpec(
    target: _positiveInt(reps),
    joint: Joint.values.byName(m['rep_joint'] as String),
    low: low,
    high: high,
  );
}

String _category(Object? v) {
  if (v == null) return Routine.dance;
  if (v is String && Routine.categories.contains(v)) return v;
  throw const FormatException('unknown category');
}

int _intOr(Object? v, int fallback, {required int min}) {
  if (v == null) return fallback;
  final i = v as int;
  if (i < min) throw const FormatException('out of range');
  return i;
}

double _metOr(Object? v) {
  if (v == null) return 3.5;
  final d = (v as num).toDouble();
  if (d <= 0 || d > 20) throw const FormatException('met out of range');
  return d;
}

/// Runs [body], turning cast/lookup errors into [FormatException].
T _parse<T>(String what, T Function() body) {
  try {
    return body();
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('malformed $what: ${e.runtimeType}');
  }
}

Map<String, Object?> _map(Object? json) =>
    (json as Map).cast<String, Object?>();

List<Object?> _list(Object? json) => (json as List).cast<Object?>();

/// A string, or null when absent/empty; any other type is malformed.
String? _optionalString(Object? v) {
  if (v == null) return null;
  final s = v as String;
  return s.isEmpty ? null : s;
}

int _positiveInt(Object? value) {
  final v = value as int;
  if (v <= 0) throw const FormatException('must be positive');
  return v;
}

/// Sorted by [key], then by `id` (when present) so ties are deterministic.
List<Object?> _sortedBy(List<Object?> rows, String key) => [...rows]
  ..sort((a, b) {
    final ma = _map(a), mb = _map(b);
    final byKey = (ma[key] as int).compareTo(mb[key] as int);
    if (byKey != 0) return byKey;
    return ((ma['id'] as String?) ?? '').compareTo((mb['id'] as String?) ?? '');
  });
