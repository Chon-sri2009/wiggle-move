import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../prefs.dart';
import 'thai_strings.dart';

/// Languages the user can pick in Profile (and on the login screen).
enum AppLanguage {
  en('English', Locale('en')),
  th('ไทย', Locale('th'));

  const AppLanguage(this.nativeName, this.locale);

  /// Shown in the picker, always in the language itself.
  final String nativeName;
  final Locale locale;

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (l) => l.name == code,
    orElse: () => AppLanguage.en,
  );
}

/// Translates [english] (the source string is the key). Unknown strings and
/// English itself come back unchanged. `{name}` placeholders are filled from
/// [args]. Pure so it can be unit tested.
String translate(
  String english,
  AppLanguage language, [
  Map<String, Object?> args = const {},
]) {
  var out = language == AppLanguage.th
      ? (thaiStrings[english] ?? english)
      : english;
  args.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  return out;
}

/// The chosen language, stored on this device (works signed out too).
class LanguageNotifier extends Notifier<AppLanguage> {
  static const key = 'language_v1';

  @override
  AppLanguage build() =>
      AppLanguage.fromCode(ref.watch(sharedPrefsProvider).getString(key));

  Future<void> set(AppLanguage language) async {
    state = language;
    await ref.read(sharedPrefsProvider).setString(key, language.name);
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, AppLanguage>(
  LanguageNotifier.new,
);

/// Puts the language into the widget tree so `context.tr(...)` works in any
/// widget and rebuilds it when the language changes.
class AppLanguageScope extends InheritedWidget {
  const AppLanguageScope({
    super.key,
    required this.language,
    required super.child,
  });

  final AppLanguage language;

  /// English when there is no scope (tests that pump a bare widget).
  static AppLanguage of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppLanguageScope>()
          ?.language ??
      AppLanguage.en;

  @override
  bool updateShouldNotify(AppLanguageScope old) => old.language != language;
}

extension AppTranslate on BuildContext {
  /// [english] in the user's language; see [translate].
  String tr(String english, [Map<String, Object?> args = const {}]) =>
      translate(english, AppLanguageScope.of(this), args);

  /// "1 move" / "3 moves": [one] when [n] is 1, else [other] (with `{n}`).
  /// Thai has no plural; its table gives both forms the same wording.
  String trCount(String one, String other, int n) =>
      n == 1 ? tr(one) : tr(other, {'n': n});

  /// A length of time as `24s`, `2m 10s` or `32m 55s` (Thai units from the
  /// table).
  String durationLabel(int ms) {
    final total = (ms / 1000).round();
    final m = total ~/ 60, s = total % 60;
    if (m == 0) return tr('{n}s', {'n': s});
    if (s == 0) return tr('{m}m', {'m': m});
    return tr('{m}m {s}s', {'m': m, 's': s});
  }
}

/// English / ไทย choice, applied at once and remembered.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider);
    return Semantics(
      label: context.tr('Language'),
      child: SegmentedButton<AppLanguage>(
        showSelectedIcon: false,
        segments: [
          for (final l in AppLanguage.values)
            ButtonSegment(value: l, label: Text(l.nativeName)),
        ],
        selected: {current},
        onSelectionChanged: (s) =>
            ref.read(languageProvider.notifier).set(s.first),
      ),
    );
  }
}
