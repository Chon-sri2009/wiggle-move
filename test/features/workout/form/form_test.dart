import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/workout/form/form_coach.dart';
import 'package:wiggle_move/features/workout/form/form_feedback.dart';
import 'package:wiggle_move/features/workout/form/form_smoother.dart';
import 'package:wiggle_move/features/workout/form/frame_preprocess.dart';

int _px(int x, int y, int c) =>
    (x * 7 + y * 13 + c * 50 + ((x * y) % 31)) % 256;

int _rgb(int x, int y) =>
    (_px(x, y, 0) << 16) | (_px(x, y, 1) << 8) | _px(x, y, 2);

void main() {
  group('preprocessFrame matches TensorFlow.js pad + resizeBilinear', () {
    // Expected values were produced by tfjs 1.7.4 (the library the model was
    // exported for): every 16th pixel of the 257x257 result.
    final cases = jsonDecode(
      File('test/features/workout/form/preprocess_fixture.json')
          .readAsStringSync(),
    ) as List<dynamic>;
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final w = c['w'] as int, h = c['h'] as int;
      test('${w}x$h', () {
        final out = preprocessFrame(width: w, height: h, pixelAt: _rgb);
        final expected = (c['vals'] as List<dynamic>).cast<num>();
        var i = 0;
        for (var y = 0; y < modelInputSize; y += 16) {
          for (var x = 0; x < modelInputSize; x += 16) {
            for (var ch = 0; ch < 3; ch++) {
              final at = (y * modelInputSize + x) * 3 + ch;
              expect(
                out[at],
                closeTo(expected[i++].toDouble(), 1e-3),
                reason: 'pixel ($x,$y) channel $ch',
              );
            }
          }
        }
      });
    }
  });

  group('orientation', () {
    // 2x1 frame: left pixel red, right pixel blue (bilinear resizing blends
    // them, so compare which channel dominates instead of exact values).
    int rb(int x, int y) => x == 0 ? 0xff0000 : 0x0000ff;
    Float32List run({int rotation = 0, bool mirror = false}) => preprocessFrame(
      width: 2,
      height: 1,
      pixelAt: rb,
      rotationDegrees: rotation,
      mirror: mirror,
    );
    String colour(Float32List f, int x, int y) {
      final i = (y * modelInputSize + x) * 3;
      return f[i] > f[i + 2] ? 'red' : 'blue';
    }

    final mid = modelInputSize ~/ 2;
    const lo = 20, hi = modelInputSize - 20;

    test('unrotated: red left, blue right, black padding above', () {
      final f = run();
      expect(colour(f, lo, mid), 'red');
      expect(colour(f, hi, mid), 'blue');
      expect(f[(5 * modelInputSize + lo) * 3], lessThan(40));
    });

    test('mirror swaps left and right', () {
      final f = run(mirror: true);
      expect(colour(f, lo, mid), 'blue');
      expect(colour(f, hi, mid), 'red');
    });

    test('90 degrees clockwise puts the left pixel on top', () {
      final f = run(rotation: 90);
      expect(colour(f, mid, lo), 'red');
      expect(colour(f, mid, hi), 'blue');
    });

    test('270 degrees clockwise puts the left pixel at the bottom', () {
      final f = run(rotation: 270);
      expect(colour(f, mid, lo), 'blue');
      expect(colour(f, mid, hi), 'red');
    });

    test('180 degrees swaps sides', () {
      final f = run(rotation: 180);
      expect(colour(f, lo, mid), 'blue');
      expect(colour(f, hi, mid), 'red');
    });
  });

  group('pixel readers', () {
    test('NV21 grey with neutral chroma is grey', () {
      // 2x2 frame: 4 luma bytes then one V,U pair.
      final bytes = Uint8List.fromList([100, 100, 100, 100, 128, 128]);
      expect(nv21Pixels(bytes, 2, 2, 2)(1, 1), 0x646464);
    });

    test('NV21 strong V gives red', () {
      final bytes = Uint8List.fromList([128, 128, 128, 128, 255, 128]);
      final rgb = nv21Pixels(bytes, 2, 2, 2)(0, 0);
      expect(rgb >> 16, 255);
      expect(rgb & 0xff, lessThan(140));
    });

    test('BGRA reads blue/green/red order', () {
      final bytes = Uint8List.fromList([10, 20, 30, 255]);
      expect(bgraPixels(bytes, 4)(0, 0), (30 << 16) | (20 << 8) | 10);
    });
  });

  group('FormSmoother', () {
    test('needs consecutive confident frames to switch', () {
      final s = FormSmoother(framesToSwitch: 3);
      expect(s.add('A', 0.9), isNull);
      expect(s.add('A', 0.9), isNull);
      expect(s.add('A', 0.9), 'A');
    });

    test(
      'a noisy frame resets the pending switch but not the stable label',
      () {
        final s = FormSmoother(framesToSwitch: 3);
        for (var i = 0; i < 3; i++) {
          s.add('A', 0.9);
        }
        s.add('B', 0.9);
        s.add('B', 0.9);
        s.add('A', 0.9); // back to stable: pending B is dropped
        s.add('B', 0.9);
        expect(s.add('B', 0.9), 'A');
        expect(s.add('B', 0.9), 'B');
      },
    );

    test('low confidence frames are ignored and clear pending candidates', () {
      final s = FormSmoother(framesToSwitch: 2, minConfidence: 0.7);
      s.add('A', 0.9);
      expect(s.add('A', 0.9), 'A');

      // One noisy 'B', then an unsure frame resets the pending switch.
      expect(s.add('B', 0.9), 'A');
      expect(s.add('B', 0.4), 'A');
      expect(s.add('B', 0.9), 'A');
      expect(s.add('B', 0.9), 'B');
    });
  });

  group('feedback', () {
    test('wrong squat gets a cue for squat moves only', () {
      final f = feedbackForLabel('Squat_Wrong_Back')!;
      expect(f.verdict, FormVerdict.fix);
      expect(feedbackAppliesToMove(f, 'Squats'), isTrue);
      expect(feedbackAppliesToMove(f, 'Half Squat'), isTrue);
      expect(feedbackAppliesToMove(f, 'Jumping Jacks'), isFalse);
      expect(feedbackAppliesToMove(f, 'T-pose'), isFalse);
    });

    test('correct form is praised', () {
      final f = feedbackForLabel('Lunge_Correct')!;
      expect(f.verdict, FormVerdict.good);
    });

    test('idle and the arms-down jack need no message', () {
      expect(feedbackForLabel('Idle'), isNull);
      expect(feedbackForLabel('Jack_Down'), isNull);
    });

    test('no person shows on any move', () {
      final f = feedbackForLabel('No_Person')!;
      expect(feedbackAppliesToMove(f, 'T-pose'), isTrue);
    });

    test('every model label is handled without throwing', () {
      final labels = (jsonDecode(
        File('assets/models/pose_labels.json').readAsStringSync(),
      ) as List<dynamic>).cast<String>();
      expect(labels, hasLength(12));
      for (final l in labels) {
        feedbackForLabel(l);
      }
    });
  });

  group('FormCoach', () {
    test('turns smoothed argmax into feedback', () {
      final coach = FormCoach(const [
        'Idle',
        'No_Person',
        'Squat_Correct',
        'Squat_Wrong_Back',
      ], smoother: FormSmoother(framesToSwitch: 2));
      const probs = [0.0, 0.0, 0.05, 0.95];
      expect(coach.update(probs), isNull);
      expect(coach.update(probs)?.label, 'Squat_Wrong_Back');
      expect(coach.current?.message, 'Keep your back straight');
    });
  });
}
