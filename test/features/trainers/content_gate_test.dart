import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/trainers/content_gate.dart';
import 'package:wiggle_move/features/trainers/trainers_provider.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/prefs.dart';
import 'package:wiggle_move/shared/widgets/async_states.dart';

import '../../support/fakes.dart';

Future<Widget> _gate(FakeContentRepository repo, String routineId) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      contentRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      home: ContentGate<Routine>(
        lookup: routineProvider(routineId),
        builder: (r) => Text('routine ${r.name}'),
        notFound: const Text('not found'),
      ),
    ),
  );
}

void main() {
  testWidgets('loading, then the item', (tester) async {
    final repo = FakeContentRepository()..gate = Completer<void>();
    await tester.pumpWidget(await _gate(repo, 'cardio-burn'));
    expect(find.byType(LoadingView), findsOneWidget);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('routine Cardio Burn'), findsOneWidget);
  });

  testWidgets('loaded without the item -> not found', (tester) async {
    await tester.pumpWidget(await _gate(FakeContentRepository(), 'nope'));
    await tester.pumpAndSettle();
    expect(find.text('not found'), findsOneWidget);
  });

  testWidgets('error -> ErrorView; Retry loads the item', (tester) async {
    final repo = FakeContentRepository()
      ..failWith = const RepositoryFailure(RepositoryFailure.network);
    await tester.pumpWidget(await _gate(repo, 'cardio-burn'));
    await tester.pumpAndSettle();
    expect(find.text(RepositoryFailure.network), findsOneWidget);
    repo.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('routine Cardio Burn'), findsOneWidget);
  });
}
