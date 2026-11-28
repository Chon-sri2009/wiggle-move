import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/prefs.dart';
import '../../shared/uuid.dart';

/// A user-curated sequence of workout routines to play back-to-back.
class WorkoutPlaylist {
  const WorkoutPlaylist({
    required this.id,
    required this.name,
    required this.routineIds,
  });

  final String id;
  final String name;
  final List<String> routineIds;

  WorkoutPlaylist copyWith({String? name, List<String>? routineIds}) =>
      WorkoutPlaylist(
        id: id,
        name: name ?? this.name,
        routineIds: routineIds ?? this.routineIds,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'routineIds': routineIds,
  };

  static WorkoutPlaylist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final ids = raw['routineIds'];
    if (id is! String || name is! String || ids is! List) return null;
    return WorkoutPlaylist(
      id: id,
      name: name,
      routineIds: [
        for (final x in ids)
          if (x is String) x,
      ],
    );
  }
}

const _starterPlaylists = <WorkoutPlaylist>[
  WorkoutPlaylist(
    id: 'starter-squat-cardio',
    name: 'Squat & Cardio Mix',
    routineIds: ['video-squat-demo', 'squat-sets', 'cardio-burn'],
  ),
];

/// Persists playlists on this device via [SharedPreferences].
class PlaylistsNotifier extends Notifier<List<WorkoutPlaylist>> {
  static const key = 'playlists_v1';

  @override
  List<WorkoutPlaylist> build() {
    final raw = ref.watch(sharedPrefsProvider).getString(key);
    if (raw == null) return _starterPlaylists;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return _starterPlaylists;
      return [for (final item in list) ?WorkoutPlaylist.fromJson(item)];
    } catch (_) {
      return _starterPlaylists;
    }
  }

  Future<void> _save(List<WorkoutPlaylist> next) async {
    state = next;
    await ref
        .read(sharedPrefsProvider)
        .setString(key, jsonEncode([for (final p in next) p.toJson()]));
  }

  Future<WorkoutPlaylist> create(
    String name, {
    List<String> routineIds = const [],
  }) async {
    final trimmed = name.trim();
    final created = WorkoutPlaylist(
      id: uuidV4(),
      name: trimmed.isEmpty ? 'My Playlist' : trimmed,
      routineIds: List<String>.from(routineIds),
    );
    await _save([...state, created]);
    return created;
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _save([
      for (final p in state) p.id == id ? p.copyWith(name: trimmed) : p,
    ]);
  }

  Future<void> delete(String id) async {
    await _save([
      for (final p in state)
        if (p.id != id) p,
    ]);
  }

  Future<void> addRoutine(String playlistId, String routineId) async {
    await _save([
      for (final p in state)
        p.id == playlistId
            ? p.copyWith(routineIds: [...p.routineIds, routineId])
            : p,
    ]);
  }

  Future<void> removeRoutineAt(String playlistId, int index) async {
    await _save([
      for (final p in state)
        if (p.id == playlistId && index >= 0 && index < p.routineIds.length)
          p.copyWith(
            routineIds: [
              for (var i = 0; i < p.routineIds.length; i++)
                if (i != index) p.routineIds[i],
            ],
          )
        else
          p,
    ]);
  }

  Future<void> reorderRoutine(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await _save([
      for (final p in state)
        if (p.id == playlistId)
          () {
            final items = List<String>.from(p.routineIds);
            final moved = items.removeAt(oldIndex);
            items.insert(newIndex.clamp(0, items.length), moved);
            return p.copyWith(routineIds: items);
          }()
        else
          p,
    ]);
  }
}

final playlistsProvider =
    NotifierProvider<PlaylistsNotifier, List<WorkoutPlaylist>>(
      PlaylistsNotifier.new,
    );

/// Tracks an in-progress playlist run across consecutive workouts.
class PlaylistPlayback {
  const PlaylistPlayback({
    required this.playlistId,
    required this.playlistName,
    required this.routineIds,
    required this.index,
  });

  final String playlistId;
  final String playlistName;
  final List<String> routineIds;
  final int index;

  String get currentRoutineId => routineIds[index];
  bool get hasNext => index + 1 < routineIds.length;
  String? get nextRoutineId => hasNext ? routineIds[index + 1] : null;
  int get total => routineIds.length;

  PlaylistPlayback advance() => PlaylistPlayback(
    playlistId: playlistId,
    playlistName: playlistName,
    routineIds: routineIds,
    index: index + 1,
  );
}

class ActivePlaylistNotifier extends Notifier<PlaylistPlayback?> {
  @override
  PlaylistPlayback? build() => null;

  void start(WorkoutPlaylist playlist, {int startIndex = 0}) {
    if (playlist.routineIds.isEmpty) return;
    state = PlaylistPlayback(
      playlistId: playlist.id,
      playlistName: playlist.name,
      routineIds: List<String>.unmodifiable(playlist.routineIds),
      index: startIndex.clamp(0, playlist.routineIds.length - 1),
    );
  }

  String? advanceToNext() {
    final current = state;
    if (current == null || !current.hasNext) {
      state = null;
      return null;
    }
    final next = current.advance();
    state = next;
    return next.currentRoutineId;
  }

  void clear() => state = null;
}

final activePlaylistProvider =
    NotifierProvider<ActivePlaylistNotifier, PlaylistPlayback?>(
      ActivePlaylistNotifier.new,
    );
