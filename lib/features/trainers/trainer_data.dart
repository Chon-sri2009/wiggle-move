import '../../app/theme.dart';
import '../scoring/move_scorer.dart';
import '../scoring/pose_math.dart';
import 'trainer.dart';

// Target angles are first-pass estimates for a user standing front-on to the
// camera. Tune them on a real device (see docs/PROJECT.md, "Calibration").
// Joint angles: shoulder = elbow–shoulder–hip, hip = shoulder–hip–knee.

Move _move(
  String name,
  String instruction,
  Map<Joint, double> angles, [
  int ms = 4000,
]) => Move(
  name: name,
  instruction: instruction,
  target: MoveTarget(angles),
  durationMs: ms,
);

final _armsUp = _move('Arms Up', 'Reach both arms straight up', {
  Joint.leftShoulder: 165,
  Joint.rightShoulder: 165,
  Joint.leftElbow: 170,
  Joint.rightElbow: 170,
});

final _tPose = _move('T-Pose', 'Arms straight out to the sides', {
  Joint.leftShoulder: 90,
  Joint.rightShoulder: 90,
  Joint.leftElbow: 170,
  Joint.rightElbow: 170,
});

final _handsOnHips = _move('Hands on Hips', 'Hands on your hips, elbows out', {
  Joint.leftElbow: 80,
  Joint.rightElbow: 80,
  Joint.leftShoulder: 35,
  Joint.rightShoulder: 35,
});

final _pointRight = _move(
  'Disco Point Right',
  'Right arm up high, left arm down',
  {
    Joint.rightShoulder: 165,
    Joint.rightElbow: 170,
    Joint.leftShoulder: 15,
    Joint.leftElbow: 170,
  },
);

final _pointLeft = _move(
  'Disco Point Left',
  'Left arm up high, right arm down',
  {
    Joint.leftShoulder: 165,
    Joint.leftElbow: 170,
    Joint.rightShoulder: 15,
    Joint.rightElbow: 170,
  },
);

final _flex = _move('Flex', 'Arms out, elbows bent, fists up', {
  Joint.leftShoulder: 90,
  Joint.rightShoulder: 90,
  Joint.leftElbow: 60,
  Joint.rightElbow: 60,
});

final _halfSquat = _move('Half Squat', 'Bend your knees, sit back', {
  Joint.leftKnee: 125,
  Joint.rightKnee: 125,
});

final trainers = <Trainer>[
  Trainer(
    id: 'mia',
    name: 'Coach Mia',
    style: 'Pop & disco',
    color: AppColors.accent,
    routines: [
      Routine(
        id: 'pop-starter',
        name: 'Pop Starter',
        level: 'Easy',
        moves: [
          _armsUp,
          _tPose,
          _handsOnHips,
          _pointRight,
          _pointLeft,
          _armsUp,
        ],
      ),
      Routine(
        id: 'disco-fever',
        name: 'Disco Fever',
        level: 'Medium',
        moves: [
          _pointRight,
          _pointLeft,
          _flex,
          _tPose,
          _pointRight,
          _pointLeft,
          _armsUp,
          _handsOnHips,
        ],
      ),
    ],
  ),
  Trainer(
    id: 'jay',
    name: 'Coach Jay',
    style: 'Cardio burn',
    color: AppColors.secondary,
    routines: [
      Routine(
        id: 'cardio-burn',
        name: 'Cardio Burn',
        level: 'Medium',
        moves: [_halfSquat, _armsUp, _halfSquat, _flex, _halfSquat, _tPose],
      ),
    ],
  ),
];

Trainer? trainerById(String id) =>
    trainers.where((t) => t.id == id).firstOrNull;

Routine? routineById(String id) =>
    trainers.expand((t) => t.routines).where((r) => r.id == id).firstOrNull;
