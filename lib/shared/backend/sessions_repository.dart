import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionsRelayException;

/// One move's result as sent to `submit_session`.
class MoveSubmission {
  const MoveSubmission({
    required this.moveIdx,
    required this.score,
    this.reps = 0,
    this.worstJoint,
    this.deviation,
  });

  /// Position of the move in its routine (0-based).
  final int moveIdx;

  /// 0–100.
  final int score;

  /// Reps counted over all sets; always 0 for a timed pose.
  final int reps;

  /// `Joint.name` of the joint furthest from target, or null.
  final String? worstJoint;

  /// Signed deviation in degrees (measured − target), or null.
  final double? deviation;

  /// Wire shape: every key is always present (the server requires them).
  Map<String, Object?> toPayload() => {
    'move_idx': moveIdx,
    'score': score,
    'reps': reps,
    'worst_joint': worstJoint,
    'deviation': deviation,
  };

  static MoveSubmission? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final idx = json['move_idx'], score = json['score'];
    final joint = json['worst_joint'], dev = json['deviation'];
    // Plays queued before reps existed have no key: they counted none.
    final reps = json['reps'] ?? 0;
    if (idx is! int || score is! int || reps is! int) return null;
    if (joint != null && joint is! String) return null;
    if (dev != null && dev is! num) return null;
    return MoveSubmission(
      moveIdx: idx,
      score: score,
      reps: reps,
      worstJoint: joint as String?,
      deviation: (dev as num?)?.toDouble(),
    );
  }
}

/// A finished play. [clientNonce] is generated once per play so retries are
/// idempotent on the server.
class SessionSubmission {
  const SessionSubmission({
    required this.routineId,
    required this.clientNonce,
    required this.durationMs,
    required this.score,
    required this.results,
    required this.playedAt,
    required this.userId,
    this.sets = 1,
  });

  final String routineId;
  final String clientNonce;
  final int durationMs;
  final int score;

  /// Sets played; the server expects the routine's own number of sets.
  final int sets;
  final List<MoveSubmission> results;
  final DateTime playedAt;

  /// Owner of the play; only used locally (queue ownership). The server
  /// takes the user from the auth token and rejects unknown keys.
  final String userId;

  /// Body for the `submit_session` Edge Function (exact key set).
  Map<String, Object?> toPayload() => {
    'routine_id': routineId,
    'client_nonce': clientNonce,
    'duration_ms': durationMs,
    'score': score,
    'sets': sets,
    // When the play happened: a play uploaded later (offline queue) keeps its
    // own time on the server.
    'played_at': playedAt.toUtc().toIso8601String(),
    'results': [for (final r in results) r.toPayload()],
  };

  /// Local storage shape (pending queue): the payload plus owner and time.
  Map<String, Object?> toJson() => {...toPayload(), 'user_id': userId};

  static SessionSubmission? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final routine = json['routine_id'], nonce = json['client_nonce'];
    final duration = json['duration_ms'], score = json['score'];
    final user = json['user_id'], at = json['played_at'];
    final raw = json['results'];
    final sets = json['sets'] ?? 1; // queued before sets existed: one set
    if (sets is! int ||
        routine is! String ||
        nonce is! String ||
        duration is! int ||
        score is! int ||
        user is! String ||
        at is! String ||
        raw is! List) {
      return null;
    }
    final playedAt = DateTime.tryParse(at);
    if (playedAt == null) return null;
    final results = <MoveSubmission>[];
    for (final r in raw) {
      final m = MoveSubmission.tryFromJson(r);
      if (m == null) return null;
      results.add(m);
    }
    return SessionSubmission(
      routineId: routine,
      clientNonce: nonce,
      durationMs: duration,
      score: score,
      sets: sets,
      results: results,
      playedAt: playedAt,
      userId: user,
    );
  }
}

/// Result of a submit. Repositories return it; they never throw.
sealed class SubmitOutcome {
  const SubmitOutcome();
}

/// Stored on the server (or locally under WM_OFFLINE). [duplicate] means the
/// server already had this nonce.
class SubmitSaved extends SubmitOutcome {
  const SubmitSaved({this.duplicate = false});
  final bool duplicate;
}

enum RetryReason { network, rateLimited, server, sessionExpired }

/// Temporary failure: keep the play and send it again later.
class SubmitRetryable extends SubmitOutcome {
  const SubmitRetryable(this.reason);
  final RetryReason reason;
}

/// Permanent failure: the server will never accept this play. [message] is
/// safe to show; raw server text is never used.
class SubmitRejected extends SubmitOutcome {
  const SubmitRejected(this.message);
  final String message;

  static const invalid = "This session couldn't be saved.";
  static const routineGone =
      "This routine is no longer available, so the score wasn't saved.";
}

/// Maps an HTTP status from `submit_session` to an outcome.
///
/// Anything that might succeed later is retryable (0 = no response, 401
/// expired session, 408, 429 rate limit, 5xx). Every other 4xx (400 invalid,
/// 404 routine gone, 413 too large, ...) is permanent: the pending queue
/// stops at the first retryable entry, so a permanent error classed as
/// retryable would block the queue forever.
SubmitOutcome classifyStatus(int status, {Object? data}) {
  if (status >= 200 && status < 300) {
    final duplicate = data is Map && data['duplicate'] == true;
    return SubmitSaved(duplicate: duplicate);
  }
  if (status == 0 || status == 408) {
    return const SubmitRetryable(RetryReason.network);
  }
  if (status == 401) return const SubmitRetryable(RetryReason.sessionExpired);
  if (status == 429) return const SubmitRetryable(RetryReason.rateLimited);
  if (status >= 500) return const SubmitRetryable(RetryReason.server);
  if (status == 404) return const SubmitRejected(SubmitRejected.routineGone);
  return const SubmitRejected(SubmitRejected.invalid);
}

/// Maps an error thrown while invoking `submit_session` to an outcome. Relay
/// errors (the function was not reached) and any non-HTTP error (socket,
/// timeout, unreadable body) are retryable: resending is safe because the
/// server is idempotent by nonce.
SubmitOutcome classifyError(Object error) {
  if (error is FunctionsRelayException) {
    return const SubmitRetryable(RetryReason.server);
  }
  if (error is FunctionException) return classifyStatus(error.status);
  return const SubmitRetryable(RetryReason.network);
}

/// Sends finished plays. Implementations: `SupabaseSessionsRepository` (the
/// `submit_session` Edge Function) and `OfflineSessionsRepository`
/// (WM_OFFLINE, on-device). [submit] never throws.
abstract class SessionsRepository {
  Future<SubmitOutcome> submit(SessionSubmission submission);
}
