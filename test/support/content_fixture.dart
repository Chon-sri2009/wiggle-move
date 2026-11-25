// The PostgREST response for
// `trainers.select('*, routines(*, moves(*))')` against supabase/seed.sql.
// Arrays are deliberately out of order: the codec must sort them.

const _templates = <String, (String, String, Map<String, num>)>{
  '_armsUp': (
    'Arms Up',
    'Reach both arms straight up',
    {
      'leftShoulder': 165,
      'rightShoulder': 165,
      'leftElbow': 170,
      'rightElbow': 170,
    },
  ),
  '_tPose': (
    'T-Pose',
    'Arms straight out to the sides',
    {
      'leftShoulder': 90,
      'rightShoulder': 90,
      'leftElbow': 170,
      'rightElbow': 170,
    },
  ),
  '_handsOnHips': (
    'Hands on Hips',
    'Hands on your hips, elbows out',
    {
      'leftElbow': 80,
      'rightElbow': 80,
      'leftShoulder': 35,
      'rightShoulder': 35,
    },
  ),
  '_pointRight': (
    'Disco Point Right',
    'Right arm up high, left arm down',
    {
      'rightShoulder': 165,
      'rightElbow': 170,
      'leftShoulder': 15,
      'leftElbow': 170,
    },
  ),
  '_pointLeft': (
    'Disco Point Left',
    'Left arm up high, right arm down',
    {
      'leftShoulder': 165,
      'leftElbow': 170,
      'rightShoulder': 15,
      'rightElbow': 170,
    },
  ),
  '_flex': (
    'Flex',
    'Arms out, elbows bent, fists up',
    {
      'leftShoulder': 90,
      'rightShoulder': 90,
      'leftElbow': 60,
      'rightElbow': 60,
    },
  ),
  '_halfSquat': (
    'Half Squat',
    'Bend your knees, sit back',
    {'leftKnee': 125, 'rightKnee': 125},
  ),
};

Map<String, Object?> _routine(
  String id,
  String trainerId,
  String name,
  String level,
  int sortOrder,
  List<String> sequence,
) => {
  'id': id,
  'trainer_id': trainerId,
  'name': name,
  'level': level,
  'video_path': null,
  'duration_ms': sequence.length * 4000,
  'sort_order': sortOrder,
  'moves': [
    for (var i = sequence.length - 1; i >= 0; i--)
      {
        'routine_id': id,
        'idx': i,
        'name': _templates[sequence[i]]!.$1,
        'instruction': _templates[sequence[i]]!.$2,
        'duration_ms': 4000,
        'target_angles': _templates[sequence[i]]!.$3,
      },
  ],
};

/// Fresh, mutable rows (tests may corrupt them).
List<Map<String, Object?>> seedRows() => [
  {
    'id': 'jay',
    'name': 'Coach Jay',
    'style': 'Cardio burn',
    'color': 4279950273,
    'sort_order': 1,
    'routines': [
      _routine('cardio-burn', 'jay', 'Cardio Burn', 'Medium', 0, [
        '_halfSquat',
        '_armsUp',
        '_halfSquat',
        '_flex',
        '_halfSquat',
        '_tPose',
      ]),
    ],
  },
  {
    'id': 'mia',
    'name': 'Coach Mia',
    'style': 'Pop & disco',
    'color': 4294934335,
    'sort_order': 0,
    'routines': [
      _routine('disco-fever', 'mia', 'Disco Fever', 'Medium', 1, [
        '_pointRight',
        '_pointLeft',
        '_flex',
        '_tPose',
        '_pointRight',
        '_pointLeft',
        '_armsUp',
        '_handsOnHips',
      ]),
      _routine('pop-starter', 'mia', 'Pop Starter', 'Easy', 0, [
        '_armsUp',
        '_tPose',
        '_handsOnHips',
        '_pointRight',
        '_pointLeft',
        '_armsUp',
      ]),
    ],
  },
];
