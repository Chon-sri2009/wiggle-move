import 'package:flutter/foundation.dart' show listEquals;

/// Answers from the personalization flow, stored in the `profiles` row.
class Profile {
  const Profile({
    this.goals = const [],
    this.styles = const [],
    this.level,
    this.avatar,
    this.onboarded = false,
  });

  /// Reads a `profiles` row (Postgres `text[]` arrives as `List<dynamic>`).
  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
    goals: List<String>.from(row['goals'] as List? ?? const []),
    styles: List<String>.from(row['styles'] as List? ?? const []),
    level: row['level'] as String?,
    avatar: row['avatar'] as String?,
    onboarded: row['onboarded'] as bool? ?? false,
  );

  final List<String> goals;
  final List<String> styles;
  final String? level;

  /// One of `avatarChoices` (a preset emoji), or null for the initial.
  final String? avatar;
  final bool onboarded;

  /// The columns written on save; all are in the client UPDATE grant.
  Map<String, Object?> toRow() => {
    'goals': goals,
    'styles': styles,
    'level': level,
    'avatar': avatar,
    'onboarded': onboarded,
  };

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      listEquals(other.goals, goals) &&
      listEquals(other.styles, styles) &&
      other.level == level &&
      other.avatar == avatar &&
      other.onboarded == onboarded;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(goals),
    Object.hashAll(styles),
    level,
    avatar,
    onboarded,
  );

  @override
  String toString() =>
      'Profile(goals: $goals, styles: $styles, level: $level, '
      'avatar: $avatar, onboarded: $onboarded)';
}
