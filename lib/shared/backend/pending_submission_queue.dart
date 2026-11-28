import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sessions_repository.dart';

/// What one [PendingSubmissionQueue.flush] did (nonces, in order).
class FlushReport {
  const FlushReport({
    this.saved = const [],
    this.rejected = const [],
    this.stoppedAtRetryable = false,
  });

  final List<String> saved;
  final List<String> rejected;
  final bool stoppedAtRetryable;
}

/// Plays that could not be sent yet, oldest first, in SharedPreferences.
/// Entries carry their owner; a flush only sends the current user's.
class PendingSubmissionQueue {
  PendingSubmissionQueue(this._prefs);

  static const key = 'pending_submissions_v1';

  /// Total entries ever dropped by the [cap] (kept so it can be reported).
  static const droppedKey = 'pending_submissions_dropped';
  static const cap = 50;

  final SharedPreferences _prefs;
  Future<FlushReport>? _flushing;

  /// Stored entries, oldest first. Corrupt storage is discarded; malformed
  /// entries are skipped.
  List<SessionSubmission> entries() {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) throw const FormatException('not a list');
      return list
          .map(SessionSubmission.tryFromJson)
          .whereType<SessionSubmission>()
          .toList();
    } on FormatException {
      unawaited(_prefs.remove(key));
      return [];
    }
  }

  bool hasEntriesFor(String userId) => entries().any((e) => e.userId == userId);

  int get droppedCount => _prefs.getInt(droppedKey) ?? 0;

  Future<void> _write(List<SessionSubmission> list) =>
      _prefs.setString(key, jsonEncode([for (final e in list) e.toJson()]));

  /// Adds [submission] unless its nonce is already queued. Past [cap] the
  /// oldest entries are dropped and counted in [droppedCount].
  Future<void> enqueue(SessionSubmission submission) async {
    final list = entries();
    if (list.any((e) => e.clientNonce == submission.clientNonce)) return;
    list.add(submission);
    final over = list.length - cap;
    if (over > 0) {
      list.removeRange(0, over);
      await _prefs.setInt(droppedKey, droppedCount + over);
    }
    await _write(list);
  }

  Future<void> _remove(String nonce) async {
    // Re-read so entries enqueued during a flush are kept.
    final list = entries()..removeWhere((e) => e.clientNonce == nonce);
    await _write(list);
  }

  /// Sends [userId]'s entries oldest first through [repo]: saved (incl.
  /// duplicate) and rejected entries are removed; the first retryable one
  /// stops the flush and stays queued with everything after it. Other users'
  /// entries are never sent or touched. Overlapping calls share one flush.
  Future<FlushReport> flush(String userId, SessionsRepository repo) {
    final running = _flushing;
    if (running != null) return running;
    final f = _flush(userId, repo).whenComplete(() => _flushing = null);
    _flushing = f;
    return f;
  }

  Future<FlushReport> _flush(String userId, SessionsRepository repo) async {
    final saved = <String>[], rejected = <String>[];
    final mine = entries().where((e) => e.userId == userId).toList();
    for (final entry in mine) {
      SubmitOutcome outcome;
      try {
        outcome = await repo.submit(entry);
      } catch (e) {
        outcome = classifyError(e);
      }
      switch (outcome) {
        case SubmitSaved():
          saved.add(entry.clientNonce);
          await _remove(entry.clientNonce);
        case SubmitRejected():
          rejected.add(entry.clientNonce);
          await _remove(entry.clientNonce);
        case SubmitRetryable():
          return FlushReport(
            saved: saved,
            rejected: rejected,
            stoppedAtRetryable: true,
          );
      }
    }
    return FlushReport(saved: saved, rejected: rejected);
  }
}
