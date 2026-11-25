import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'content_models.dart';

/// Last successfully fetched content, kept per install (content is public,
/// so it is not tied to the signed-in user and survives sign-out).
class ContentCache {
  ContentCache(this._prefs);

  static const key = 'content_cache_v1';

  final SharedPreferences _prefs;

  /// The cached trainers, or null when there is none or it is unreadable
  /// (a corrupt cache is discarded).
  CachedContent? read() {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return CachedContent(
        trainers: trainersFromJson(json['trainers']),
        savedAt: DateTime.parse(json['saved_at'] as String),
      );
    } catch (_) {
      unawaited(_prefs.remove(key));
      return null;
    }
  }

  Future<void> save(List<Trainer> trainers, {DateTime? now}) =>
      _prefs.setString(
        key,
        jsonEncode({
          'saved_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
          'trainers': trainersToJson(trainers),
        }),
      );
}

class CachedContent {
  const CachedContent({required this.trainers, required this.savedAt});
  final List<Trainer> trainers;
  final DateTime savedAt;
}
