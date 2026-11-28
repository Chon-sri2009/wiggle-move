import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';
import 'profile_repository.dart';

// Same keys the pre-repository app used, so existing dev installs keep their
// answers.
const _onboardedKey = 'onboarded';
const _goalsKey = 'profile_goals';
const _stylesKey = 'profile_styles';
const _levelKey = 'profile_level';
const _avatarKey = 'profile_avatar';

/// On-device profile for `--dart-define=WM_OFFLINE=true`. One profile per
/// device: it is not tied to the offline account and survives sign-out.
class OfflineProfileRepository implements ProfileRepository {
  OfflineProfileRepository(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<Profile> load() async => Profile(
    goals: _prefs.getStringList(_goalsKey) ?? const [],
    styles: _prefs.getStringList(_stylesKey) ?? const [],
    level: _prefs.getString(_levelKey),
    avatar: _prefs.getString(_avatarKey),
    onboarded: _prefs.getBool(_onboardedKey) ?? false,
  );

  @override
  Future<void> save(Profile profile) async {
    await _prefs.setStringList(_goalsKey, profile.goals);
    await _prefs.setStringList(_stylesKey, profile.styles);
    final level = profile.level;
    if (level == null) {
      await _prefs.remove(_levelKey);
    } else {
      await _prefs.setString(_levelKey, level);
    }
    final avatar = profile.avatar;
    if (avatar == null) {
      await _prefs.remove(_avatarKey);
    } else {
      await _prefs.setString(_avatarKey, avatar);
    }
    await _prefs.setBool(_onboardedKey, profile.onboarded);
  }

  /// The offline name lives in the offline account (`OfflineAuthRepository`).
  @override
  Future<void> saveDisplayName(String name) async {}
}
