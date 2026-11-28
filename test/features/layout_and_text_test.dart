import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/app/app.dart';
import 'package:wiggle_move/features/history/history_screen.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/offline_auth_repository.dart';
import 'package:wiggle_move/shared/backend/offline_content_repository.dart';
import 'package:wiggle_move/shared/backend/offline_profile_repository.dart';
import 'package:wiggle_move/shared/backend/profile_providers.dart';
import 'package:wiggle_move/shared/l10n/app_language.dart';
import 'package:wiggle_move/shared/prefs.dart';

Future<Widget> _app(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final i = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(i),
      authRepositoryProvider.overrideWithValue(OfflineAuthRepository(i)),
      profileRepositoryProvider.overrideWithValue(OfflineProfileRepository(i)),
      contentRepositoryProvider.overrideWithValue(
        const OfflineContentRepository(),
      ),
    ],
    child: const WiggleMoveApp(),
  );
}

void _phone(WidgetTester t, {double text = 1}) {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
}

void main() {
  for (final text in [1.0, 2.0]) {
    testWidgets('goals step has no overflow at text scale $text', (t) async {
      _phone(t, text: text);
      await t.pumpWidget(await _app({'player_name': 'Ann'}));
      await t.pumpAndSettle();
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Weight Management'), findsOneWidget);
    });

    testWidgets('login has no overflow at text scale $text', (t) async {
      _phone(t, text: text);
      await t.pumpWidget(await _app({}));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Forgot your password?'), findsOneWidget);
    });
  }

  testWidgets('Thai onboarding titles are translated', (t) async {
    _phone(t);
    await t.pumpWidget(await _app({'player_name': 'Ann', 'language_v1': 'th'}));
    await t.pumpAndSettle();
    await t.tap(find.text('เริ่ม'));
    await t.pumpAndSettle();
    expect(find.text('Your Fitness Goal'), findsNothing);
    expect(find.text('เป้าหมายการออกกำลังกายของคุณ'), findsOneWidget);
  });

  group('durations and counts', () {
    Future<BuildContext> ctx(WidgetTester t, AppLanguage l) async {
      late BuildContext c;
      await t.pumpWidget(
        AppLanguageScope(
          language: l,
          child: Builder(
            builder: (context) {
              c = context;
              return const SizedBox();
            },
          ),
        ),
      );
      return c;
    }

    testWidgets('durationLabel in English', (t) async {
      final c = await ctx(t, AppLanguage.en);
      expect(c.durationLabel(24000), '24s');
      expect(c.durationLabel(130000), '2m 10s');
      expect(c.durationLabel(120000), '2m');
      expect(c.durationLabel(1975033), '32m 55s');
    });

    testWidgets('durationLabel and counts in Thai', (t) async {
      final c = await ctx(t, AppLanguage.th);
      expect(c.durationLabel(130000), '2 นาที 10 วินาที');
      expect(c.trCount('1 move', '{n} moves', 6), '6 ท่า');
    });

    testWidgets('singular and plural in English', (t) async {
      final c = await ctx(t, AppLanguage.en);
      expect(c.trCount('1 move', '{n} moves', 1), '1 move');
      expect(c.trCount('1 move', '{n} moves', 6), '6 moves');
    });
  });

  test('history dates: Thai month names and Buddhist-era year', () {
    final at = DateTime(2026, 11, 26, 14, 5);
    expect(formatPlayedAt(at), 'Nov 26, 2026 · 14:05');
    expect(
      formatPlayedAt(at, language: AppLanguage.th),
      '26 พ.ย. 2569 · 14:05',
    );
  });
}
