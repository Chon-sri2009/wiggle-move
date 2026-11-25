import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiggle_move/shared/backend/pending_submission_queue.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';

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

const _retry = SubmitRetryable(RetryReason.network);
const _rejected = SubmitRejected(SubmitRejected.invalid);
const _saved = SubmitSaved();

void main() {
  late SharedPreferences prefs;
  late PendingSubmissionQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    queue = PendingSubmissionQueue(prefs);
  });

  List<String> nonces() => queue.entries().map((e) => e.clientNonce).toList();

  test('enqueue keeps order and survives a new instance', () async {
    await queue.enqueue(_s(1));
    await queue.enqueue(_s(2));
    expect(PendingSubmissionQueue(prefs).entries().map((e) => e.clientNonce), [
      _s(1).clientNonce,
      _s(2).clientNonce,
    ]);
  });

  test('enqueue with an already queued nonce does not duplicate', () async {
    await queue.enqueue(_s(1));
    await queue.enqueue(_s(1));
    expect(nonces(), [_s(1).clientNonce]);
  });

  test('flush submits in order, removes saved and duplicates', () async {
    await queue.enqueue(_s(1));
    await queue.enqueue(_s(2));
    final repo = FakeSessionsRepository()
      ..script.addAll([_saved, const SubmitSaved(duplicate: true)]);
    final report = await queue.flush('u1', repo);
    expect(repo.submitted.map((e) => e.clientNonce), [
      _s(1).clientNonce,
      _s(2).clientNonce,
    ]);
    expect(report.saved, [_s(1).clientNonce, _s(2).clientNonce]);
    expect(queue.entries(), isEmpty);
  });

  test('flush stops at the first retryable and keeps order', () async {
    for (final n in [1, 2, 3]) {
      await queue.enqueue(_s(n));
    }
    final repo = FakeSessionsRepository()..script.addAll([_saved, _retry]);
    final report = await queue.flush('u1', repo);
    expect(repo.submitted.length, 2);
    expect(report.stoppedAtRetryable, isTrue);
    expect(nonces(), [_s(2).clientNonce, _s(3).clientNonce]);
  });

  test('flush drops rejected entries and continues', () async {
    await queue.enqueue(_s(1));
    await queue.enqueue(_s(2));
    final repo = FakeSessionsRepository()..script.addAll([_rejected, _saved]);
    final report = await queue.flush('u1', repo);
    expect(report.rejected, [_s(1).clientNonce]);
    expect(report.saved, [_s(2).clientNonce]);
    expect(queue.entries(), isEmpty);
  });

  test('flush never submits or removes another user\'s entries', () async {
    await queue.enqueue(_s(1, user: 'other'));
    await queue.enqueue(_s(2));
    await queue.enqueue(_s(3, user: 'other'));
    final repo = FakeSessionsRepository();
    await queue.flush('u1', repo);
    expect(repo.submitted.map((e) => e.clientNonce), [_s(2).clientNonce]);
    expect(nonces(), [_s(1).clientNonce, _s(3).clientNonce]);
    expect(queue.hasEntriesFor('other'), isTrue);
    expect(queue.hasEntriesFor('u1'), isFalse);
  });

  test('a thrown repository error is treated as retryable', () async {
    await queue.enqueue(_s(1));
    final repo = FakeSessionsRepository()..throwWith = StateError('boom');
    final report = await queue.flush('u1', repo);
    expect(report.stoppedAtRetryable, isTrue);
    expect(nonces(), [_s(1).clientNonce]);
  });

  test('cap drops the oldest and counts drops', () async {
    for (var n = 0; n < PendingSubmissionQueue.cap + 3; n++) {
      await queue.enqueue(_s(n));
    }
    final list = nonces();
    expect(list.length, PendingSubmissionQueue.cap);
    expect(list.first, _s(3).clientNonce);
    expect(queue.droppedCount, 3);
  });

  test('corrupt storage is discarded safely', () async {
    await prefs.setString(PendingSubmissionQueue.key, '{not json');
    expect(queue.entries(), isEmpty);
    expect(prefs.getString(PendingSubmissionQueue.key), isNull);
    await queue.enqueue(_s(1));
    expect(nonces(), [_s(1).clientNonce]);
  });

  test('malformed entries are skipped, good ones kept', () async {
    await prefs.setString(
      PendingSubmissionQueue.key,
      jsonEncode([
        {'bad': true},
        _s(1).toJson(),
      ]),
    );
    expect(nonces(), [_s(1).clientNonce]);
  });

  test('enqueue during a flush is not lost', () async {
    await queue.enqueue(_s(1));
    final gate = Completer<void>();
    final repo = FakeSessionsRepository()..gate = gate;
    final flushing = queue.flush('u1', repo);
    await Future<void>.delayed(Duration.zero);
    await queue.enqueue(_s(2));
    gate.complete();
    await flushing;
    expect(nonces(), [_s(2).clientNonce]);
  });

  test('overlapping flushes are coalesced (no double submit)', () async {
    await queue.enqueue(_s(1));
    final gate = Completer<void>();
    final repo = FakeSessionsRepository()..gate = gate;
    final a = queue.flush('u1', repo);
    final b = queue.flush('u1', repo);
    gate.complete();
    await Future.wait([a, b]);
    expect(repo.submitted.length, 1);
    expect(queue.entries(), isEmpty);
  });

  test('retried entry keeps its nonce (idempotent)', () async {
    await queue.enqueue(_s(7));
    final repo = FakeSessionsRepository()..script.addAll([_retry, _saved]);
    await queue.flush('u1', repo);
    await queue.flush('u1', repo);
    expect(repo.submitted.map((e) => e.clientNonce), [
      _s(7).clientNonce,
      _s(7).clientNonce,
    ]);
    expect(queue.entries(), isEmpty);
  });
}
