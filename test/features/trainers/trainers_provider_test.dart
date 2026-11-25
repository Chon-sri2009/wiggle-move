import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/features/trainers/trainers_provider.dart';
import 'package:wiggle_move/shared/backend/content_cache.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/content_providers.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../../support/fakes.dart';

const _network = RepositoryFailure(RepositoryFailure.network);

/// Only the first built-in trainer: distinguishable from the full list.
final _cachedOnly = [builtInTrainers.first];

Future<(ProviderContainer, SharedPreferences)> _container(
  FakeContentRepository repo, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(instance),
      contentRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  return (c, instance);
}

Future<Map<String, Object>> _cachePrefs(List<Trainer> trainers) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await ContentCache(prefs).save(trainers, now: DateTime.utc(2026));
  return {ContentCache.key: prefs.getString(ContentCache.key)!};
}

List<String> _ids(TrainersState? s) => [
  for (final t in s?.trainers ?? const <Trainer>[]) t.id,
];

void main() {
  group('ContentCache', () {
    test('round-trips trainers and savedAt', () async {
      final (_, prefs) = await _container(FakeContentRepository());
      final cache = ContentCache(prefs);
      expect(cache.read(), isNull);
      await cache.save(builtInTrainers, now: DateTime.utc(2026, 1, 2));
      final read = cache.read()!;
      expect(read.savedAt, DateTime.utc(2026, 1, 2));
      expect(
        jsonEncode(trainersToJson(read.trainers)),
        jsonEncode(trainersToJson(builtInTrainers)),
      );
    });

    test('corrupt cache reads as none and is discarded', () async {
      for (final raw in ['not json', '{"trainers": [{"id": 1}]}', '[]']) {
        final (_, prefs) = await _container(
          FakeContentRepository(),
          prefs: {ContentCache.key: raw},
        );
        expect(ContentCache(prefs).read(), isNull, reason: raw);
        expect(prefs.getString(ContentCache.key), isNull, reason: raw);
      }
    });
  });

  group('trainersProvider', () {
    test('no cache: fetches remotely and saves the cache', () async {
      final repo = FakeContentRepository();
      final (c, prefs) = await _container(repo);
      final s = await c.read(trainersProvider.future);
      expect(_ids(s), ['mia', 'jay']);
      expect(s.isStale, isFalse);
      expect(ContentCache(prefs).read()!.trainers, hasLength(2));
    });

    test(
      'cache hit emits cached data at once, then the remote update',
      () async {
        final repo = FakeContentRepository()..gate = Completer<void>();
        final (c, prefs) = await _container(
          repo,
          prefs: await _cachePrefs(_cachedOnly),
        );
        final sub = c.listen(trainersProvider, (_, _) {});
        expect(_ids(sub.read().value), ['mia']);
        expect(repo.fetches, 1);

        repo.gate!.complete();
        await pumpEventQueue();
        expect(_ids(sub.read().value), ['mia', 'jay']);
        expect(sub.read().value!.isStale, isFalse);
        expect(ContentCache(prefs).read()!.trainers, hasLength(2));
      },
    );

    test('remote failure keeps cached data and marks it stale', () async {
      final repo = FakeContentRepository()..failWith = _network;
      final (c, prefs) = await _container(
        repo,
        prefs: await _cachePrefs(_cachedOnly),
      );
      final sub = c.listen(trainersProvider, (_, _) {});
      await pumpEventQueue();
      final s = sub.read().value!;
      expect(_ids(s), ['mia']);
      expect(s.isStale, isTrue);
      expect(s.refreshError!.message, RepositoryFailure.network);
      // The cache is left as it was.
      expect(ContentCache(prefs).read()!.trainers, hasLength(1));

      // A later refresh that succeeds clears the stale flag.
      repo.failWith = null;
      await c.read(trainersProvider.notifier).refresh();
      expect(_ids(sub.read().value), ['mia', 'jay']);
      expect(sub.read().value!.isStale, isFalse);
    });

    test('no cache + failure -> error; retry succeeds', () async {
      final repo = FakeContentRepository()..failWith = StateError('raw');
      final (c, _) = await _container(repo);
      final sub = c.listen(trainersProvider, (_, _) {});
      await expectLater(
        c.read(trainersProvider.future),
        throwsA(
          isA<RepositoryFailure>().having(
            (f) => f.message,
            'message',
            RepositoryFailure.generic,
          ),
        ),
      );
      expect(sub.read().hasError, isTrue);

      repo.failWith = null;
      await c.read(trainersProvider.notifier).refresh();
      expect(_ids(sub.read().value), ['mia', 'jay']);
    });

    test('corrupt cache is ignored and remote content is used', () async {
      final repo = FakeContentRepository();
      final (c, prefs) = await _container(
        repo,
        prefs: {ContentCache.key: '{"saved_at": "x", "trainers": 5}'},
      );
      final s = await c.read(trainersProvider.future);
      expect(_ids(s), ['mia', 'jay']);
      expect(ContentCache(prefs).read(), isNotNull);
    });

    test('trainerProvider / routineProvider look up loaded content', () async {
      final (c, _) = await _container(FakeContentRepository());
      expect(c.read(trainerProvider('mia')), isNull); // still loading
      await c.read(trainersProvider.future);
      expect(c.read(trainerProvider('mia'))!.name, 'Coach Mia');
      expect(c.read(trainerProvider('nope')), isNull);
      expect(c.read(routineProvider('cardio-burn'))!.name, 'Cardio Burn');
      expect(c.read(routineProvider('nope')), isNull);
    });
  });
}
