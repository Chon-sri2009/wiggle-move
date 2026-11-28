import 'package:flutter/material.dart';

class ProfileOption {
  const ProfileOption(this.label, this.icon, [this.subtitle]);
  final String label;
  final IconData icon;
  final String? subtitle;
}

const goalOptions = [
  ProfileOption('Burn Calories', Icons.local_fire_department),
  ProfileOption('Build Strength', Icons.front_hand),
  ProfileOption('Improve Fitness', Icons.monitor_heart),
  ProfileOption('Improve Flexibility', Icons.directions_run),
  ProfileOption('Weight Management', Icons.monitor_weight),
  ProfileOption('Stay Healthy', Icons.health_and_safety),
];

const styleOptions = [
  ProfileOption('Dance Workout', Icons.accessibility_new),
  ProfileOption('Cardio', Icons.favorite),
  ProfileOption('Bodyweight', Icons.fitness_center),
  ProfileOption('Stretching', Icons.eco),
];

const levelOptions = [
  ProfileOption('Beginner', Icons.child_care, "I'm just getting started."),
  ProfileOption(
    'Intermediate',
    Icons.accessibility_new,
    'I work out occasionally.',
  ),
  ProfileOption('Advanced', Icons.person, 'I know various workout techniques.'),
];

/// Preset avatars (stored as-is in `profiles.avatar`).
const avatarChoices = ['🐰', '🦊', '🐼', '🐯', '🐸', '🦄', '🐙', '🌟'];

/// Longest display name the `profiles` table accepts.
const maxDisplayName = 40;

/// Null when [value] is an acceptable display name.
String? validateDisplayName(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Enter a name';
  if (v.length > maxDisplayName) {
    return 'Use $maxDisplayName characters or fewer';
  }
  return null;
}
