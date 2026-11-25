import 'package:supabase_flutter/supabase_flutter.dart';

import 'content_models.dart';
import 'content_repository.dart';
import 'profile_repository.dart';

/// Reads trainers with embedded routines and moves in one request. Children
/// are ordered client-side by `sort_order` / `idx` (see [trainersFromRows]).
class SupabaseContentRepository implements ContentRepository {
  SupabaseContentRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Trainer>> fetchTrainers() async {
    try {
      final rows = await _client
          .from('trainers')
          .select('*, routines(*, moves(*))')
          // postgrest's order() is descending unless told otherwise.
          .order('sort_order', ascending: true);
      return trainersFromRows(rows);
    } catch (e) {
      throw mapRepositoryException(e);
    }
  }
}
