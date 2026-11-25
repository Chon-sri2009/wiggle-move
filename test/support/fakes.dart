import 'dart:async';

import 'package:wiggle_move/shared/backend/auth_repository.dart';

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
