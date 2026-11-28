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
  '_squats': (
    'Squats',
    'Sit back until your knees bend, then stand tall',
    {'leftKnee': 95, 'rightKnee': 95},
  ),
  '_jumpingJacks': (
    'Jumping Jacks',
    'Jump feet apart with arms overhead, then back',
    {
      'leftShoulder': 160,
      'rightShoulder': 160,
      'leftElbow': 170,
      'rightElbow': 170,
    },
  ),
  '_highKnees': (
    'High Knees',
    'Run in place, lifting your left knee to hip height',
    {'leftHip': 90},
  ),
};

// Counted (cardio) moves: duration per set and the rep columns.
const _counted = <String, (int, Map<String, Object?>)>{
  '_squats': (
    30000,
    {'reps': 12, 'rep_joint': 'leftKnee', 'rep_low': 110, 'rep_high': 160},
  ),
  '_jumpingJacks': (
    20000,
    {'reps': 20, 'rep_joint': 'leftShoulder', 'rep_low': 50, 'rep_high': 140},
  ),
  '_highKnees': (
    20000,
    {'reps': 16, 'rep_joint': 'leftHip', 'rep_low': 110, 'rep_high': 160},
  ),
};

int _ms(String key) => _counted[key]?.$1 ?? 4000;

Map<String, Object?> _routine(
  String id,
  String trainerId,
  String name,
  String level,
  int sortOrder,
  List<String> sequence, {
  String category = 'dance',
  int sets = 1,
  int restMs = 0,
  num met = 3.5,
}) => {
  'id': id,
  'trainer_id': trainerId,
  'name': name,
  'level': level,
  'category': category,
  'sets': sets,
  'rest_ms': restMs,
  'met': met,
  'video_path': null,
  'duration_ms': sequence.fold<int>(0, (sum, k) => sum + _ms(k)),
  'sort_order': sortOrder,
  'moves': [
    for (var i = sequence.length - 1; i >= 0; i--)
      {
        'routine_id': id,
        'idx': i,
        'name': _templates[sequence[i]]!.$1,
        'instruction': _templates[sequence[i]]!.$2,
        'duration_ms': _ms(sequence[i]),
        'target_angles': _templates[sequence[i]]!.$3,
        'reps': null,
        'rep_joint': null,
        'rep_low': null,
        'rep_high': null,
        ...?_counted[sequence[i]]?.$2,
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
    'photo_path': null,
    'sort_order': 1,
    'routines': [
      _routine(
        'cardio-burn',
        'jay',
        'Cardio Burn',
        'Medium',
        0,
        [
          '_halfSquat',
          '_armsUp',
          '_halfSquat',
          '_flex',
          '_halfSquat',
          '_tPose',
        ],
        category: 'cardio',
        met: 6,
      ),
      _routine(
        'squat-sets',
        'jay',
        'Squat Sets',
        'Easy',
        1,
        ['_squats'],
        category: 'cardio',
        sets: 3,
        restMs: 20000,
        met: 5,
      ),
      _routine(
        'cardio-circuit',
        'jay',
        'Cardio Circuit',
        'Medium',
        2,
        ['_jumpingJacks', '_squats', '_highKnees'],
        category: 'cardio',
        sets: 3,
        restMs: 30000,
        met: 8,
      ),
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
