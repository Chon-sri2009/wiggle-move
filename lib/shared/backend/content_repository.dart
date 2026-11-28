import 'content_models.dart';

/// Public workout content (trainers -> routines -> moves). Implementations:
/// `SupabaseContentRepository` (the content tables) and
/// `OfflineContentRepository` (WM_OFFLINE, built-in `trainer_data.dart`).
///
/// Throws `RepositoryFailure` on error, including malformed rows: partial
/// content is never returned.
abstract class ContentRepository {
  /// All trainers with their routines and moves, in display order.
  Future<List<Trainer>> fetchTrainers();
}
