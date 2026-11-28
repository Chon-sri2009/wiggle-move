import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiggle_move/features/home/home_screen.dart';
import 'package:wiggle_move/features/trainers/personalization.dart';
import 'package:wiggle_move/features/trainers/trainer_screen.dart';
import 'package:wiggle_move/shared/backend/content_models.dart';
import 'package:wiggle_move/shared/backend/profile.dart';
import 'package:wiggle_move/shared/backend/trainer_data.dart';
import 'package:wiggle_move/shared/backend/trainer_photo.dart';

final _routines = builtInTrainers.expand((t) => t.routines).toList();
Routine _r(String id) => _routines.firstWhere((r) => r.id == id);

const _beginnerCardio = Profile(
  level: 'Beginner',
  styles: ['Cardio'],
  onboarded: true,
);
const _advancedDance = Profile(
  level: 'Advanced',
  styles: ['Dance Workout'],
  onboarded: true,
);

void main() {
  group('routineFit', () {
    test('a style match with the right level is 0', () {
      expect(routineFit(_r('squat-sets'), _beginnerCardio), 0); // Easy cardio
    });

    test('the level gap adds 1 per step; a style miss adds 10', () {
      expect(routineFit(_r('cardio-circuit'), _beginnerCardio), 1); // Medium
      expect(routineFit(_r('pop-starter'), _beginnerCardio), 10); // Easy dance
      expect(routineFit(_r('disco-fever'), _beginnerCardio), 11);
    });

    test('unknown answers are neutral', () {
      expect(routineFit(_r('pop-starter'), const Profile()), 0);
      // Styles with no content ("Stretching") do not penalize anything.
      expect(
        routineFit(_r('pop-starter'), const Profile(styles: ['Stretching'])),
        0,
      );
      expect(routineFit(_r('pop-starter'), const Profile(level: 'Expert')), 0);
    });
  });

  group('ranking', () {
    test('routines: best fit first, ties keep the given order', () {
      final ids = rankRoutines(
        builtInTrainers.last.routines,
        _beginnerCardio,
      ).map((r) => r.id);
      // Easy cardio (0), Medium cardio x3 (1), keeping server order.
      expect(ids, ['squat-sets', 'cardio-burn', 'cardio-circuit']);
    });

    test('trainers: the one with the best-fitting routine first', () {
      expect(rankTrainers(builtInTrainers, _beginnerCardio).map((t) => t.id), [
        'jay',
        'mia',
      ]);
      expect(rankTrainers(builtInTrainers, _advancedDance).map((t) => t.id), [
        'mia',
        'jay',
      ]);
    });

    test('an empty profile leaves the order untouched', () {
      expect(
        rankTrainers(builtInTrainers, const Profile()).map((t) => t.id),
        builtInTrainers.map((t) => t.id),
      );
      expect(
        rankRoutines(_routines, const Profile()).map((r) => r.id),
        _routines.map((r) => r.id),
      );
    });

    test('ranking never drops or duplicates anything', () {
      final ranked = rankTrainers(builtInTrainers, _beginnerCardio);
      expect(ranked, hasLength(builtInTrainers.length));
      expect(ranked.toSet(), builtInTrainers.toSet());
    });

    test('a trainer without routines goes last', () {
      const empty = Trainer(
        id: 'x',
        name: 'X',
        style: 's',
        color: Color(0xFF000000),
        routines: [],
      );
      expect(
        rankTrainers([empty, ...builtInTrainers], _beginnerCardio).last,
        empty,
      );
    });
  });

  group('recommended', () {
    test('only with answers to match and a perfect fit', () {
      expect(isRecommended(_r('squat-sets'), _beginnerCardio), isTrue);
      expect(isRecommended(_r('cardio-circuit'), _beginnerCardio), isFalse);
      expect(isRecommended(_r('squat-sets'), const Profile()), isFalse);
      expect(trainerRecommended(builtInTrainers.last, _beginnerCardio), isTrue);
      expect(
        trainerRecommended(builtInTrainers.first, _beginnerCardio),
        isFalse,
      );
    });
  });

  group('trainer photos', () {
    test('public URL in the trainer-photos bucket', () {
      expect(
        trainerPhotoUrl('mia/head shot.jpg', base: 'https://x.supabase.co'),
        'https://x.supabase.co/storage/v1/object/public/trainer-photos/'
        'mia/head%20shot.jpg',
      );
      expect(
        trainerPhotoUrl('a.png', base: 'https://x.supabase.co/'),
        'https://x.supabase.co/storage/v1/object/public/trainer-photos/a.png',
      );
    });

    test('no photo or no backend means no URL', () {
      expect(trainerPhotoUrl(null, base: 'https://x'), isNull);
      expect(trainerPhotoUrl('', base: 'https://x'), isNull);
      expect(trainerPhotoUrl('a.png', base: ''), isNull);
    });

    test('photo_path round trips; wrong type is malformed; empty is none', () {
      final json = builtInTrainers.first.toJson();
      expect(json.containsKey('photo_path'), isFalse);
      expect(Trainer.fromJson(json).photoPath, isNull);
      expect(Trainer.fromJson({...json, 'photo_path': ''}).photoPath, isNull);
      final withPhoto = Trainer.fromJson({...json, 'photo_path': 'mia.jpg'});
      expect(withPhoto.photoPath, 'mia.jpg');
      expect(Trainer.fromJson(withPhoto.toJson()).photoPath, 'mia.jpg');
      expect(
        () => Trainer.fromJson({...json, 'photo_path': 5}),
        throwsFormatException,
      );
    });
  });

  group('screens', () {
    testWidgets('the avatar shows the initial without a photo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: TrainerAvatar(trainer: builtInTrainers.first)),
      );
      expect(find.text('M'), findsOneWidget); // Coach Mia
    });

    testWidgets('the trainer screen ranks routines and badges the fit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TrainerScreen(trainer: builtInTrainers.last),
          ),
        ),
      );
      // No profile loaded: server order, no badge.
      expect(find.textContaining('Recommended'), findsNothing);
    });
  });
}
