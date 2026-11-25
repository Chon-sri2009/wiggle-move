import 'dart:async';

import 'package:wiggle_move/shared/backend/auth_repository.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/content_repository.dart';
import 'package:wiggle_move/shared/backend/profile.dart';
import 'package:wiggle_move/shared/backend/profile_repository.dart';
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

/// In-memory [ContentRepository]. Set [gate] to hold fetches until completed;
/// set [failWith] to make fetches throw.
class FakeContentRepository implements ContentRepository {
  FakeContentRepository([List<Trainer>? trainers])
    : trainers = trainers ?? builtInTrainers;

  List<Trainer> trainers;
  Completer<void>? gate;
  Object? failWith;
  int fetches = 0;

  @override
  Future<List<Trainer>> fetchTrainers() async {
    fetches++;
    final g = gate;
    if (g != null) await g.future;
    final f = failWith;
    if (f != null) throw f;
    return trainers;
  }
}
