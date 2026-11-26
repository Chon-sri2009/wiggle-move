import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        FunctionsFetchException,
        FunctionsHttpException,
        FunctionsRelayException;
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/uuid.dart';

SessionSubmission _submission({
  String nonce = '11111111-1111-4111-8111-111111111111',
}) => SessionSubmission(
  routineId: 'mia-pop',
  clientNonce: nonce,
  durationMs: 24100,
  score: 70,
  playedAt: DateTime.utc(2026, 11, 25, 10),
  userId: 'u1',
  results: const [
    MoveSubmission(
      moveIdx: 0,
      score: 90,
      worstJoint: 'leftElbow',
      deviation: -12.5,
    ),
    MoveSubmission(moveIdx: 1, score: 50),
  ],
);

void main() {
  group('classifyStatus', () {
    test('2xx is saved, reading the duplicate flag defensively', () {
      expect(classifyStatus(200), isA<SubmitSaved>());
      expect((classifyStatus(200) as SubmitSaved).duplicate, isFalse);
      expect(
        (classifyStatus(
          200,
          data: {'duplicate': true},
        ) as SubmitSaved).duplicate,
        isTrue,
      );
      expect(
        (classifyStatus(201, data: 'not json') as SubmitSaved).duplicate,
        isFalse,
      );
    });

    test('network, timeout, 401, 408, 429 and 5xx are retryable', () {
      expect(
        (classifyStatus(0) as SubmitRetryable).reason,
        RetryReason.network,
      );
      expect(
        (classifyStatus(401) as SubmitRetryable).reason,
        RetryReason.sessionExpired,
      );
      expect(
        (classifyStatus(408) as SubmitRetryable).reason,
        RetryReason.network,
      );
      expect(
        (classifyStatus(429) as SubmitRetryable).reason,
        RetryReason.rateLimited,
      );
      for (final s in [500, 502, 503, 504]) {
        expect(
          (classifyStatus(s) as SubmitRetryable).reason,
          RetryReason.server,
        );
      }
    });

    test('400, 404, 413 and other 4xx are rejected (permanent)', () {
      for (final s in [400, 403, 404, 405, 413, 422]) {
        expect(classifyStatus(s), isA<SubmitRejected>(), reason: '$s');
      }
      expect(
        (classifyStatus(404) as SubmitRejected).message,
        SubmitRejected.routineGone,
      );
      expect(
        (classifyStatus(400) as SubmitRejected).message,
        SubmitRejected.invalid,
      );
    });
  });

  group('classifyError', () {
    test('function exceptions map by status; relay errors retry', () {
      expect(
        classifyError(const FunctionsHttpException(status: 400, details: 'x')),
        isA<SubmitRejected>(),
      );
      expect(
        classifyError(const FunctionsHttpException(status: 503)),
        isA<SubmitRetryable>(),
      );
      expect(
        classifyError(const FunctionsFetchException(details: 'offline')),
        isA<SubmitRetryable>(),
      );
      expect(
        classifyError(const FunctionsRelayException(status: 404)),
        isA<SubmitRetryable>(),
      );
    });

    test('anything else (socket, timeout, bad body) is retryable', () {
      expect(
        classifyError(const SocketException('raw')),
        isA<SubmitRetryable>(),
      );
      expect(classifyError(TimeoutException('t')), isA<SubmitRetryable>());
      expect(
        classifyError(const FormatException('bad')),
        isA<SubmitRetryable>(),
      );
    });

    test('rejected messages never contain server details', () {
      final out = classifyError(
        const FunctionsHttpException(
          status: 400,
          details: {'error': 'score_mismatch'},
        ),
      ) as SubmitRejected;
      expect(out.message, isNot(contains('score_mismatch')));
    });
  });

  group('SessionSubmission', () {
    test('payload has exactly the submit_session keys (no user_id)', () {
      final p = _submission().toPayload();
      expect(p.keys.toSet(), {
        'routine_id',
        'client_nonce',
        'duration_ms',
        'score',
        'sets',
        'results',
      });
      expect(p['routine_id'], 'mia-pop');
      expect(p['client_nonce'], '11111111-1111-4111-8111-111111111111');
      expect(p['duration_ms'], 24100);
      expect(p['score'], 70);
      final results = p['results']! as List;
      for (final r in results) {
        expect((r as Map).keys.toSet(), {
          'move_idx',
          'score',
          'reps',
          'worst_joint',
          'deviation',
        });
      }
      expect(results.first, {
        'move_idx': 0,
        'score': 90,
        'reps': 0,
        'worst_joint': 'leftElbow',
        'deviation': -12.5,
      });
      // Null fields are sent explicitly: the server requires every key.
      final second = results.last as Map;
      expect(second.containsKey('worst_joint'), isTrue);
      expect(second['worst_joint'], isNull);
      expect(second.containsKey('deviation'), isTrue);
      expect(second['deviation'], isNull);
    });

    test('storage JSON round-trips including userId and playedAt', () {
      final s = _submission();
      final back = SessionSubmission.tryFromJson(s.toJson())!;
      expect(back.toJson(), s.toJson());
      expect(back.userId, 'u1');
      expect(back.playedAt, s.playedAt);
    });

    test('malformed storage JSON is null', () {
      expect(SessionSubmission.tryFromJson('x'), isNull);
      expect(SessionSubmission.tryFromJson({'user_id': 'u1'}), isNull);
      final bad = _submission().toJson()
        ..['results'] = [
          {'move_idx': 'a'},
        ];
      expect(SessionSubmission.tryFromJson(bad), isNull);
    });
  });

  group('uuidV4', () {
    final re = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('has the v4 format', () {
      for (var i = 0; i < 200; i++) {
        expect(uuidV4(), matches(re));
      }
    });

    test('is random per call; seeded random is deterministic', () {
      expect(uuidV4(), isNot(uuidV4()));
      expect(uuidV4(Random(1)), uuidV4(Random(1)));
      expect(uuidV4(Random(1)), matches(re));
    });
  });
}
