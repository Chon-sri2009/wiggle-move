import 'dart:ui' show Color;

import '../pose/pose_math.dart';

// Content models (trainers -> routines -> moves) and their JSON codec.
//
// `fromRow` reads the nested PostgREST shape of
// `trainers.select('*, routines(*, moves(*))')` and sorts children by
// `sort_order` / `idx`. `toJson` / `fromJson` are the on-device cache format
// (children already in order). Any malformed input throws [FormatException].

class Move {
  const Move({
    required this.name,
    required this.instruction,
    required this.target,
    this.durationMs = 4000,
  });
  final String name;
  final String instruction;
  final MoveTarget target;
  final int durationMs;

  factory Move.fromJson(Object? json) => _parse('move', () {
    final m = _map(json);
    return Move(
      name: m['name'] as String,
      instruction: m['instruction'] as String,
      durationMs: _positiveInt(m['duration_ms']),
      target: targetFromJson(m['target_angles']),
    );
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'instruction': instruction,
    'duration_ms': durationMs,
    'target_angles': targetToJson(target),
  };
}

class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.level,
    required this.moves,
  });
  final String id;
  final String name;
  final String level;
  final List<Move> moves;

  int get durationMs => moves.fold(0, (sum, m) => sum + m.durationMs);

  factory Routine.fromRow(Object? row) => _routine(row, sorted: true);

  factory Routine.fromJson(Object? json) => _routine(json, sorted: false);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'level': level,
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
  });
  final String id;
  final String name;
  final String style;
  final Color color;
  final List<Routine> routines;

  /// One `trainers` row with embedded `routines(*, moves(*))`.
  factory Trainer.fromRow(Object? row) => _trainer(row, sorted: true);

  factory Trainer.fromJson(Object? json) => _trainer(json, sorted: false);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'style': style,
    'color': color.toARGB32(),
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
    moves: [
      for (final mv in sorted ? _sortedBy(moves, 'idx') : moves)
        Move.fromJson(mv),
    ],
  );
});

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
