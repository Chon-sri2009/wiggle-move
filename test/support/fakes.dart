import 'dart:async';

import 'package:wiggle_move/shared/backend/auth_repository.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/content_repository.dart';
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
