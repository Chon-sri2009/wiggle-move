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

  test('unconfigured by default in tests', () {
    expect(Env.isConfigured, isFalse);
    expect(Env.offline, isFalse);
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
