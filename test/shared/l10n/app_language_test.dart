import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/shared/l10n/app_language.dart';
import 'package:wiggle_move/shared/l10n/thai_strings.dart';
import 'package:wiggle_move/shared/prefs.dart';

void main() {
  group('translate', () {
    test('English and unknown strings come back unchanged', () {
      expect(translate('Search', AppLanguage.en), 'Search');
      expect(translate('Not in the table', AppLanguage.th), 'Not in the table');
    });

    test('Thai uses the table and fills placeholders', () {
      expect(translate('Search', AppLanguage.th), 'ค้นหา');
      expect(
        translate('Hello, {name}', AppLanguage.th, {'name': 'Ann'}),
        'สวัสดี Ann',
      );
      expect(
        translate('Hello, {name}', AppLanguage.en, {'name': 'Ann'}),
        'Hello, Ann',
      );
    });

    test('every Thai value keeps the placeholders of its English key', () {
      final placeholder = RegExp(r'\{\w+\}');
      thaiStrings.forEach((en, th) {
        expect(th.trim(), isNotEmpty, reason: en);
        expect(
          placeholder.allMatches(th).map((m) => m[0]).toSet(),
          placeholder.allMatches(en).map((m) => m[0]).toSet(),
          reason: en,
        );
      });
    });
  });

  group('language setting', () {
    Future<ProviderContainer> container([
      Map<String, Object> seed = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(seed);
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('defaults to English', () async {
      final c = await container();
      expect(c.read(languageProvider), AppLanguage.en);
    });

    test('a saved choice is restored and a change is stored', () async {
      final c = await container({LanguageNotifier.key: 'th'});
      expect(c.read(languageProvider), AppLanguage.th);
      await c.read(languageProvider.notifier).set(AppLanguage.en);
      expect(c.read(languageProvider), AppLanguage.en);
      expect(c.read(sharedPrefsProvider).getString(LanguageNotifier.key), 'en');
    });

    test('an unknown saved value falls back to English', () async {
      final c = await container({LanguageNotifier.key: 'xx'});
      expect(c.read(languageProvider), AppLanguage.en);
    });

    testWidgets('picking ไทย switches context.tr at once', (tester) async {
      final c = await container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              home: AppLanguageScope(
                language: ref.watch(languageProvider),
                child: Scaffold(
                  body: Column(
                    children: [
                      const LanguagePicker(),
                      Builder(builder: (ctx) => Text(ctx.tr('Search'))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Search'), findsOneWidget);
      await tester.tap(find.text('ไทย'));
      await tester.pumpAndSettle();
      expect(find.text('ค้นหา'), findsOneWidget);
      expect(find.text('Search'), findsNothing);
    });
  });
}
