import 'package:supabase_flutter/supabase_flutter.dart' show FunctionsClient;

import 'sessions_repository.dart';

/// Sends plays to the `submit_session` Edge Function (WM-10). The client's
/// FunctionsClient adds the signed-in user's token. Nothing here logs the
/// payload, response details or headers.
class SupabaseSessionsRepository implements SessionsRepository {
  SupabaseSessionsRepository(
    this._functions, {
    this.timeout = const Duration(seconds: 20),
  });

  static const functionName = 'submit_session';

  final FunctionsClient _functions;

  /// `invoke` has no timeout of its own; a hung request would stall the
  /// pending-queue flush.
  final Duration timeout;

  @override
  Future<SubmitOutcome> submit(SessionSubmission submission) async {
    try {
      final res = await _functions
          .invoke(functionName, body: submission.toPayload())
          .timeout(timeout);
      return classifyStatus(res.status, data: res.data);
    } catch (e) {
      return classifyError(e);
    }
  }
}
