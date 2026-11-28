import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/app/app.dart';
import 'package:wiggle_move/shared/backend/profile.dart';

void main() {
  const done = AsyncData(Profile(onboarded: true));
  const fresh = AsyncData(Profile());
  const loading = AsyncLoading<Profile>();
  final failed = AsyncError<Profile>(Exception('x'), StackTrace.empty);

  String? go(String loc, AsyncValue<Profile> p, {bool signedIn = true}) =>
      appRedirect(signedIn: signedIn, profile: p, location: loc);

  test('opening a reset link keeps the user on /reset-password', () {
    String? recover(String loc) => appRedirect(
      signedIn: true,
      profile: done,
      location: loc,
      recovering: true,
    );
    expect(recover('/'), '/reset-password');
    expect(recover('/login'), '/reset-password');
    expect(recover('/reset-password'), isNull);
    // Without a reset in progress the screen is not reachable.
    expect(go('/reset-password', done), '/');
    expect(go('/reset-password', done, signedIn: false), '/login');
  });

  test('signed out goes to login, auth pages stay', () {
    expect(go('/', done, signedIn: false), '/login');
    expect(go('/loading', loading, signedIn: false), '/login');
    expect(go('/signup', fresh, signedIn: false), isNull);
  });

  test('loading or failed profile waits on /loading, never /personalize', () {
    expect(go('/', loading), '/loading');
    expect(go('/login', loading), '/loading');
    expect(go('/personalize', loading), '/loading');
    expect(go('/loading', loading), isNull);
    expect(go('/', failed), '/loading');
    expect(go('/loading', failed), isNull);
  });

  test('loaded profile leaves /loading and auth pages', () {
    expect(go('/loading', done), '/');
    expect(go('/login', done), '/');
    expect(go('/loading', fresh), '/personalize');
    expect(go('/login', fresh), '/personalize');
  });

  test('not onboarded is kept on /personalize', () {
    expect(go('/', fresh), '/personalize');
    expect(go('/leaderboard', fresh), '/personalize');
    expect(go('/personalize', fresh), isNull);
    expect(go('/leaderboard', done), isNull);
  });
}
