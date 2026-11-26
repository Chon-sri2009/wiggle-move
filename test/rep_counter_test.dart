import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/shared/calories.dart';
import 'package:wiggle_move/shared/pose/rep_counter.dart';

int _count(RepCounter c, List<double> angles) {
  angles.forEach(c.update);
  return c.count;
}

void main() {
  group('RepCounter', () {
    test('counts a squat: down to low, back up to high', () {
      final c = RepCounter(low: 110, high: 160);
      expect(_count(c, [170, 150, 100, 130, 165]), 1);
      expect(_count(c, [120, 90, 155, 150]), 1); // 155 < high: not yet
      c.update(161);
      expect(c.count, 2);
    });

    test('jitter around one threshold does not double count', () {
      final c = RepCounter(low: 110, high: 160);
      expect(_count(c, [112, 108, 111, 109, 112]), 0); // never came back up
      expect(_count(c, [158, 162, 159, 163, 158]), 1); // one rep, not three
    });

    test('a half rep (never reaching low) counts nothing', () {
      final c = RepCounter(low: 110, high: 160);
      expect(_count(c, [170, 130, 170, 125, 170]), 0);
    });

    test('starting already low (arms down) still counts the first cycle', () {
      final c = RepCounter(low: 50, high: 140);
      expect(_count(c, [20, 90, 160, 30, 150]), 2);
    });

    test('low must be below high', () {
      expect(() => RepCounter(low: 5, high: 5), throwsA(isA<AssertionError>()));
    });
  });

  group('estimateCalories', () {
    test('MET formula for a 70 kg body', () {
      // 8 MET * 3.5 * 70 / 200 = 9.8 kcal per minute.
      expect(estimateCalories(met: 8, durationMs: 60000), 10);
      expect(estimateCalories(met: 8, durationMs: 600000), 98);
    });

    test('nothing for no time or no intensity', () {
      expect(estimateCalories(met: 8, durationMs: 0), 0);
      expect(estimateCalories(met: 0, durationMs: 60000), 0);
    });
  });
}
