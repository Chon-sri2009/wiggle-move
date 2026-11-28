import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/shared/env.dart';
import 'package:wiggle_move/shared/env_error_screen.dart';

void main() {
  test('hasKeys requires both values', () {
    expect(Env.hasKeys('u', 'k'), isTrue);
    expect(Env.hasKeys('', 'k'), isFalse);
    expect(Env.hasKeys('u', ''), isFalse);
  });

  test('missingFlags names the absent defines', () {
    expect(Env.missingFlags('', ''), ['SUPABASE_URL', 'SUPABASE_ANON_KEY']);
    expect(Env.missingFlags('u', ''), ['SUPABASE_ANON_KEY']);
    expect(Env.missingFlags('u', 'k'), isEmpty);
  });

  test('isConfigured reflects the supplied defines', () {
    expect(Env.isConfigured, Env.hasKeys(Env.supabaseUrl, Env.supabaseAnonKey));
  });

  test('offline mode is forbidden only in release builds', () {
    expect(Env.offlineForbidden(offline: true, release: true), isTrue);
    expect(Env.offlineForbidden(offline: true, release: false), isFalse);
    expect(Env.offlineForbidden(offline: false, release: true), isFalse);
    expect(Env.offlineForbidden(offline: false, release: false), isFalse);
  });

  testWidgets('error screen can show a custom message', (tester) async {
    await tester.pumpWidget(
      const EnvErrorScreen(
        title: 'Offline mode not allowed',
        message: 'WM_OFFLINE cannot be used in a release build.',
      ),
    );
    expect(find.text('Offline mode not allowed'), findsOneWidget);
    expect(find.textContaining('release build'), findsOneWidget);
    expect(find.textContaining('--dart-define=SUPABASE_URL'), findsNothing);
  });

  testWidgets('error screen lists missing flags', (tester) async {
    await tester.pumpWidget(
      const EnvErrorScreen(missing: ['SUPABASE_URL', 'SUPABASE_ANON_KEY']),
    );
    expect(find.text('Missing configuration'), findsOneWidget);
    expect(find.textContaining('--dart-define=SUPABASE_URL'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
