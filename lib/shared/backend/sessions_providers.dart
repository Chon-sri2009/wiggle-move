import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../prefs.dart';
import 'auth_providers.dart';
import 'offline_sessions_repository.dart';
import 'pending_submission_queue.dart';
import 'sessions_repository.dart';
import 'supabase_sessions_repository.dart';

/// On-device sessions under WM_OFFLINE, the `submit_session` Edge Function
/// otherwise. Tests override this with a fake.
final sessionsRepositoryProvider = Provider<SessionsRepository>((ref) {
  if (Env.offline) {
    return OfflineSessionsRepository(
      ref.watch(sharedPrefsProvider),
      playerName: () => ref.read(authUserProvider)?.displayName,
    );
  }
  return SupabaseSessionsRepository(Supabase.instance.client.functions);
});

final pendingSubmissionQueueProvider = Provider<PendingSubmissionQueue>(
  (ref) => PendingSubmissionQueue(ref.watch(sharedPrefsProvider)),
);

enum SubmissionStatus { pending, saved, queued, rejected }

class SubmissionState {
  const SubmissionState(this.status, [this.message]);
  final SubmissionStatus status;

  /// User-safe reason for [SubmissionStatus.rejected].
  final String? message;
}

/// Upload status of the plays submitted in this app run, by client nonce.
class SubmissionStatusNotifier extends Notifier<Map<String, SubmissionState>> {
  @override
  Map<String, SubmissionState> build() => const {};

  void set(String nonce, SubmissionState value) =>
      state = {...state, nonce: value};
}

final submissionStatusProvider =
    NotifierProvider<SubmissionStatusNotifier, Map<String, SubmissionState>>(
      SubmissionStatusNotifier.new,
    );

/// Submits finished plays and drains the pending queue. Never throws.
class SessionSync {
  SessionSync(this._ref);
  final Ref _ref;

  void _set(String nonce, SubmissionState value) =>
      _ref.read(submissionStatusProvider.notifier).set(nonce, value);

  /// Sends [submission] once. Retryable failures are queued (same nonce, so
  /// a later resend is idempotent) and a flush is attempted; rejected plays
  /// are not queued. A save also flushes older queued plays.
  Future<SubmitOutcome> submit(SessionSubmission submission) async {
    final nonce = submission.clientNonce;
    _set(nonce, const SubmissionState(SubmissionStatus.pending));
    SubmitOutcome outcome;
    try {
      outcome = await _ref.read(sessionsRepositoryProvider).submit(submission);
    } catch (e) {
      outcome = classifyError(e);
    }
    switch (outcome) {
      case SubmitSaved():
        _set(nonce, const SubmissionState(SubmissionStatus.saved));
      case SubmitRetryable():
        await _ref.read(pendingSubmissionQueueProvider).enqueue(submission);
        _set(nonce, const SubmissionState(SubmissionStatus.queued));
      case SubmitRejected(:final message):
        _set(nonce, SubmissionState(SubmissionStatus.rejected, message));
    }
    if (outcome is! SubmitRejected) await flush();
    return outcome;
  }

  /// Sends the signed-in user's queued plays. Does nothing (and does not
  /// touch the repository) when signed out or nothing is queued.
  Future<void> flush() async {
    final userId = _ref.read(authUserProvider)?.id;
    if (userId == null) return;
    final queue = _ref.read(pendingSubmissionQueueProvider);
    if (!queue.hasEntriesFor(userId)) return;
    try {
      final report = await queue.flush(
        userId,
        _ref.read(sessionsRepositoryProvider),
      );
      for (final nonce in report.saved) {
        _set(nonce, const SubmissionState(SubmissionStatus.saved));
      }
      for (final nonce in report.rejected) {
        _set(
          nonce,
          const SubmissionState(
            SubmissionStatus.rejected,
            SubmitRejected.invalid,
          ),
        );
      }
    } catch (_) {
      // Best effort: entries stay queued for the next trigger.
    }
  }
}

final sessionSyncProvider = Provider<SessionSync>(SessionSync.new);
