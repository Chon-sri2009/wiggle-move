import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wiggle_move/shared/backend/auth_providers.dart';
import 'package:wiggle_move/shared/backend/offline_sessions_repository.dart';
import 'package:wiggle_move/shared/backend/pending_submission_queue.dart';
import 'package:wiggle_move/shared/backend/sessions_providers.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/backend/supabase_sessions_repository.dart';
import 'package:wiggle_move/shared/prefs.dart';

import '../../support/fakes.dart';

SessionSubmission _s(int n, {String user = 'u1'}) => SessionSubmission(
  routineId: 'mia-pop',
  clientNonce: '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  durationMs: 24000,
  score: 50,
  playedAt: DateTime.utc(2026, 1, 1, 0, n),
  userId: user,
  results: const [MoveSubmission(moveIdx: 0, score: 50)],
);

/// Records invoke calls; answers with [respond].
class _FakeFunctions implements FunctionsClient {
  _FakeFunctions(this.respond);
  final Future<FunctionResponse> Function() respond;
  final calls = <(String, Object?)>[];

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
    Future<void>? abortSignal,
  }) {
    calls.add((functionName, body));
    return respond();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SupabaseSessionsRepository', () {
    test(
      'invokes submit_session with the payload and maps the answer',
      () async {
        final fn = _FakeFunctions(
          () async => const FunctionResponse(
            status: 200,
            data: {'session_id': 'x', 'score': 50, 'duplicate': true},
          ),
        );
        final out = await SupabaseSessionsRepository(fn).submit(_s(1));
        expect(fn.calls.single.$1, 'submit_session');
        expect(fn.calls.single.$2, _s(1).toPayload());
        expect((out as SubmitSaved).duplicate, isTrue);
      },
    );

    test(
      'HTTP errors and fetch failures are classified, never thrown',
      () async {
        Future<SubmitOutcome> run(Object error) =>
            SupabaseSessionsRepository(_FakeFunctions(() async => throw error))
                .submit(_s(1));
        expect(
          await run(const FunctionsHttpException(status: 400)),
          isA<SubmitRejected>(),
        );
        expect(
          await run(const FunctionsHttpException(status: 429)),
          isA<SubmitRetryable>(),
        );
        expect(
          await run(const FunctionsFetchException(details: 'x')),
          isA<SubmitRetryable>(),
        );
      },
    );

    test('a hung request times out as retryable', () async {
      final repo = SupabaseSessionsRepository(
        _FakeFunctions(() => Completer<FunctionResponse>().future),
        timeout: const Duration(milliseconds: 10),
      );
      expect(await repo.submit(_s(1)), isA<SubmitRetryable>());
    });
  });

  group('OfflineSessionsRepository', () {
    test('appends to the local leaderboard and reports saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = OfflineSessionsRepository(prefs, playerName: () => 'Ann');
      expect(await repo.submit(_s(1)), isA<SubmitSaved>());
      await repo.submit(_s(2));
      final list = jsonDecode(prefs.getString(localLeaderboardKey)!) as List;
      expect(list.length, 2);
      expect(list.first, {
        'playerName': 'Ann',
        'routineId': 'mia-pop',
        'score': 50,
        'playedAt': _s(1).playedAt.toIso8601String(),
      });
    });

    test('no player name: nothing stored, still saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = OfflineSessionsRepository(prefs, playerName: () => null);
      expect(await repo.submit(_s(1)), isA<SubmitSaved>());
      expect(prefs.getString(localLeaderboardKey), isNull);
    });
  });

  group('SessionSync', () {
    late FakeSessionsRepository repo;
    late FakeAuthRepository auth;
    late ProviderContainer container;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repo = FakeSessionsRepository();
      auth = FakeAuthRepository(FakeAuthRepository.ann);
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(auth),
          sessionsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
    });

    SessionSync sync() => container.read(sessionSyncProvider);
    SubmissionStatus? status(SessionSubmission s) =>
        container.read(submissionStatusProvider)[s.clientNonce]?.status;
    PendingSubmissionQueue queue() =>
        container.read(pendingSubmissionQueueProvider);

    test('saved: status saved, nothing queued', () async {
      await sync().submit(_s(1));
      expect(status(_s(1)), SubmissionStatus.saved);
      expect(queue().entries(), isEmpty);
    });

    test('pending while the submit is in flight', () async {
      repo.gate = Completer<void>();
      final f = sync().submit(_s(1));
      expect(status(_s(1)), SubmissionStatus.pending);
      repo.gate!.complete();
      await f;
      expect(status(_s(1)), SubmissionStatus.saved);
    });

    test('retryable: queued with the same nonce, flush attempted', () async {
      repo.script.addAll([
        const SubmitRetryable(RetryReason.network),
        const SubmitRetryable(RetryReason.network),
      ]);
      await sync().submit(_s(1));
      expect(status(_s(1)), SubmissionStatus.queued);
      expect(queue().entries().single.clientNonce, _s(1).clientNonce);
      // The immediate flush resent it with the same nonce.
      expect(repo.submitted.map((e) => e.clientNonce), [
        _s(1).clientNonce,
        _s(1).clientNonce,
      ]);
    });

    test('a thrown repository error is queued, not lost', () async {
      repo.throwWith = StateError('boom');
      await sync().submit(_s(1));
      expect(status(_s(1)), SubmissionStatus.queued);
      expect(queue().entries(), hasLength(1));
    });

    test('rejected: status carries a safe message, not queued', () async {
      repo.script.add(const SubmitRejected(SubmitRejected.routineGone));
      await sync().submit(_s(1));
      final state = container.read(
        submissionStatusProvider,
      )[_s(1).clientNonce]!;
      expect(state.status, SubmissionStatus.rejected);
      expect(state.message, SubmitRejected.routineGone);
      expect(queue().entries(), isEmpty);
      expect(repo.submitted, hasLength(1));
    });

    test('a later flush uploads queued plays and marks them saved', () async {
      await queue().enqueue(_s(1));
      await queue().enqueue(_s(2, user: 'other'));
      await sync().flush();
      expect(repo.submitted.map((e) => e.clientNonce), [_s(1).clientNonce]);
      expect(status(_s(1)), SubmissionStatus.saved);
      expect(queue().entries().single.userId, 'other');
    });

    test('flush when signed out or nothing queued does not submit', () async {
      await sync().flush();
      expect(repo.submitted, isEmpty);
      auth.emit(null);
      await queue().enqueue(_s(1));
      await sync().flush();
      expect(repo.submitted, isEmpty);
    });
  });
}
