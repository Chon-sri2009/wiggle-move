import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move_app1/app/app.dart';
import 'package:wiggle_move_app1/features/leaderboard/leaderboard_store.dart';

Future<Widget> _app() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const WiggleMoveApp(),
  );
}

void main() {
  testWidgets('home lists trainers and opens their routines', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();
    expect(find.text('Coach Mia'), findsOneWidget);
    expect(find.text('Coach Jay'), findsOneWidget);

    await tester.tap(find.text('Coach Mia'));
    await tester.pumpAndSettle();
    expect(find.text('Pop Starter'), findsOneWidget);
    expect(find.text('Disco Fever'), findsOneWidget);
  });

  testWidgets('leaderboard shows empty state', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Leaderboard'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No scores yet'), findsOneWidget);
  });

  test('rankEntries keeps best score per player and sorts descending', () {
    LeaderboardEntry e(String n, int s, [String r = 'a']) => LeaderboardEntry(
      playerName: n,
      routineId: r,
      score: s,
      playedAt: DateTime(2026),
    );
    final ranked = rankEntries([
      e('Ann', 60),
      e('Ann', 80),
      e('Bo', 70),
      e('Bo', 90, 'b'),
    ], routineId: 'a');
    expect(ranked.map((x) => '${x.playerName}:${x.score}'), [
      'Ann:80',
      'Bo:70',
    ]);
  });
}
