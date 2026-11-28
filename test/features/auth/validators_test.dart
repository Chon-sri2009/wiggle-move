import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/auth/auth_screens.dart';

void main() {
  test('validateEmail', () {
    expect(validateEmail('ann@x.com'), isNull);
    expect(validateEmail(' ann@x.com '), isNull);
    for (final bad in [
      null,
      '',
      'ann',
      'ann@',
      'ann@x',
      '@x.com',
      'a b@x.com',
    ]) {
      expect(validateEmail(bad), isNotNull, reason: '$bad');
    }
  });

  test('validatePassword needs 8+ characters', () {
    expect(validatePassword('1234567'), isNotNull);
    expect(validatePassword('12345678'), isNull);
    expect(validatePassword(null), isNotNull);
  });

  test('validateName', () {
    expect(validateName('Ann'), isNull);
    expect(validateName('  '), isNotNull);
    expect(validateName('x' * 41), isNotNull);
  });
}
