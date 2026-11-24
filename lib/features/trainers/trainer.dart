import 'package:flutter/material.dart';

import '../scoring/move_scorer.dart';

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
}
