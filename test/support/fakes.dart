import 'dart:async';

import 'package:wiggle_move/shared/backend/auth_repository.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/content_repository.dart';
import 'package:wiggle_move/shared/backend/history_repository.dart';
import 'package:wiggle_move/shared/backend/leaderboard_repository.dart';
import 'package:wiggle_move/shared/backend/profile.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
import 'package:wiggle_move/shared/backend/sessions_repository.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';

/// In-memory [AuthRepository] for tests. Set [failWith] to make the next
/// calls throw; inspect [resetRequests] for password-reset calls.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository([this._user]);

  static const ann = AppUser(id: 'u1', email: 'ann@x.com', displayName: 'Ann');

  AppUser? _user;
  AuthFailure? failWith;
  final resetRequests = <String>[];
  final nameUpdates = <String>[];
  int deletes = 0;
  final _changes = StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get authChanges => _changes.stream;

  /// Simulates a session change from outside the app (e.g. token expiry).
  void emit(AppUser? user) {
    _user = user;
    _changes.add(user);
  }

  void _check() {
    final f = failWith;
    if (f != null) throw f;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _check();
    emit(AppUser(id: 'new', email: email, displayName: displayName));
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _check();
    emit(AppUser(id: 'u1', email: email, displayName: email.split('@').first));
  }

  @override
  Future<void> signOut() async {
    _check();
    emit(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _check();
    resetRequests.add(email);
  }

  @override
  Future<void> updateDisplayName(String name) async {
    _check();
    nameUpdates.add(name);
    final u = _user!;
    emit(AppUser(id: u.id, email: u.email, displayName: name));
  }

  @override
  Future<void> deleteAccount() async {
    _check();
    deletes++;
    emit(null);
  }
}

/// In-memory [ProfileRepository] keyed by the signed-in user of [auth], like
/// the server's own-row RLS. Set [loadGate] to hold loads until completed;
/// set [failLoad] / [failSave] to make calls throw.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(this.auth, [Map<String, Profile>? profiles])
    : profiles = profiles ?? {};

  static const onboarded = Profile(
    goals: ['Burn Calories'],
    styles: ['Cardio'],
    level: 'Beginner',
    onboarded: true,
  );

  final AuthRepository auth;
  final Map<String, Profile> profiles;
  Completer<void>? loadGate;
  RepositoryFailure? failLoad;
  RepositoryFailure? failSave;
  RepositoryFailure? failName;
  final names = <String>[];
  int loads = 0;

  String get _uid => auth.currentUser!.id;

  @override
  Future<Profile> load() async {
    loads++;
    final uid = _uid;
    final gate = loadGate;
    if (gate != null) await gate.future;
    final f = failLoad;
    if (f != null) throw f;
    return profiles[uid] ?? const Profile();
  }

  @override
  Future<void> save(Profile profile) async {
    final f = failSave;
    if (f != null) throw f;
    profiles[_uid] = profile;
  }

  @override
  Future<void> saveDisplayName(String name) async {
    final f = failName;
    if (f != null) throw f;
    names.add(name);
  }
}

/// Scripted [SessionsRepository]: each submit takes the next outcome from
/// [script] (saved when empty). Set [gate] to hold submits until completed;
/// set [throwWith] to make submits throw. Submissions are recorded.
class FakeSessionsRepository implements SessionsRepository {
  final script = <SubmitOutcome>[];
  final submitted = <SessionSubmission>[];
  Completer<void>? gate;
  Object? throwWith;

  @override
  Future<SubmitOutcome> submit(SessionSubmission submission) async {
    submitted.add(submission);
    final g = gate;
    if (g != null) await g.future;
    final t = throwWith;
    if (t != null) throw t;
    return script.isEmpty ? const SubmitSaved() : script.removeAt(0);
  }
}

/// In-memory [ContentRepository]. Set [gate] to hold fetches until completed;
/// set [failWith] to make fetches throw; set [onFetch] to script each call.
class FakeContentRepository implements ContentRepository {
  FakeContentRepository([List<Trainer>? trainers])
    : trainers = trainers ?? builtInTrainers;

  List<Trainer> trainers;
  Completer<void>? gate;
  Object? failWith;
  int fetches = 0;

  /// When set, answers each fetch instead of [trainers]/[gate]/[failWith].
  Future<List<Trainer>> Function()? onFetch;

  @override
  Future<List<Trainer>> fetchTrainers() async {
    fetches++;
    final handler = onFetch;
    if (handler != null) return handler();
    final g = gate;
    if (g != null) await g.future;
    final f = failWith;
    if (f != null) throw f;
    return trainers;
  }
}

/// [LeaderboardRepository] returning [rows] (or the per-query [byQuery]
/// rows). Records every [calls] query; set [failWith] to make fetches throw,
/// or [gate] to hold them until completed.
class FakeLeaderboardRepository implements LeaderboardRepository {
  FakeLeaderboardRepository([this.rows = const []]);

  List<LeaderboardRow> rows;
  final calls = <({String? routineId, LeaderboardPeriod period})>[];

  /// The category asked for in each call (parallel to [calls]).
  final categories = <String?>[];
  RepositoryFailure? failWith;
  Completer<void>? gate;
  Map<({String? routineId, LeaderboardPeriod period}), List<LeaderboardRow>>
  byQuery = {};

  @override
  Future<List<LeaderboardRow>> fetch({
    String? routineId,
    required LeaderboardPeriod period,
    int limit = 50,
    String? category,
  }) async {
    final q = (routineId: routineId, period: period);
    calls.add(q);
    categories.add(category);
    await gate?.future;
    final f = failWith;
    if (f != null) throw f;
    return byQuery[q] ?? rows;
  }
}

/// [HistoryRepository] returning [entries]; counts [fetches]. Set
/// [failWith] to make fetches throw.
class FakeHistoryRepository implements HistoryRepository {
  FakeHistoryRepository([this.entries = const []]);

  List<HistoryEntry> entries;
  RepositoryFailure? failWith;
  int fetches = 0;

  @override
  Future<List<HistoryEntry>> fetch({int limit = 50}) async {
    fetches++;
    final f = failWith;
    if (f != null) throw f;
    return entries;
  }
}
