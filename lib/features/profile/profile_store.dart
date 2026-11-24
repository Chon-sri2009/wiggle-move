import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../leaderboard/leaderboard_store.dart';

const _onboardedKey = 'onboarded';
const _goalsKey = 'profile_goals';
const _stylesKey = 'profile_styles';
const _levelKey = 'profile_level';

/// Answers from the personalization flow.
class Profile {
  const Profile({
    this.goals = const [],
    this.styles = const [],
    this.level,
    this.onboarded = false,
  });
  final List<String> goals;
  final List<String> styles;
  final String? level;
  final bool onboarded;
}

class ProfileNotifier extends Notifier<Profile> {
  @override
  Profile build() {
    final prefs = ref.read(sharedPrefsProvider);
    return Profile(
      goals: prefs.getStringList(_goalsKey) ?? const [],
      styles: prefs.getStringList(_stylesKey) ?? const [],
      level: prefs.getString(_levelKey),
      onboarded: prefs.getBool(_onboardedKey) ?? false,
    );
  }

  Future<void> complete({
    required List<String> goals,
    required List<String> styles,
    required String level,
  }) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setStringList(_goalsKey, goals);
    await prefs.setStringList(_stylesKey, styles);
    await prefs.setString(_levelKey, level);
    await prefs.setBool(_onboardedKey, true);
    state = Profile(
      goals: goals,
      styles: styles,
      level: level,
      onboarded: true,
    );
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);
