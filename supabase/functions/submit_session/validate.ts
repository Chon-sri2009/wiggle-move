// WM-10: pure validation for the submit_session Edge Function.
//
// No Deno or remote imports, so it runs under both Deno (the Edge Function)
// and Node >= 22.18 (`node --test`, type stripping). Keep to erasable
// TypeScript syntax: no enums, namespaces or parameter properties.

/** Dart `Joint.name` values from lib/features/scoring/pose_math.dart. */
export const JOINT_NAMES: readonly string[] = Object.freeze([
  'leftElbow',
  'rightElbow',
  'leftShoulder',
  'rightShoulder',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
]);

/**
 * |MoveResult.worstSignedDeviation| bound in degrees. The value is signed
 * (measured - target; joint angles are 0..180), so negatives are valid.
 */
export const DEVIATION_MAX_ABS = 360;

/** Hard cap on results.length, checked before iterating. */
export const MAX_RESULTS = 200;

export const MAX_ROUTINE_ID_LENGTH = 64;

/**
 * Reps counted for a move may exceed its target (the counter keeps counting
 * until the set's time is up), but not by more than this factor over all sets.
 * The app caps each set's reps at the same factor (`maxRepsOvershoot` in
 * lib/features/workout/workout_session.dart): keep the two equal, or an
 * honest play is rejected permanently.
 */
export const REPS_OVERSHOOT = 3;

/** Raw request body cap (bytes), enforced by index.ts before JSON.parse. */
export const MAX_BODY_BYTES = 32 * 1024;

/** A reported play time may be at most this old (the offline queue's reach). */
export const MAX_PLAY_AGE_MS = 30 * 24 * 60 * 60 * 1000;

/** Clock skew allowed for a play time slightly in the future. */
export const PLAY_TIME_SKEW_MS = 5 * 60 * 1000;

/** Sessions allowed per user per rolling hour. */
export const RATE_LIMIT_PER_HOUR = 30;

/** Stable error codes returned as `{error}` by the Edge Function. */
export const ERR = Object.freeze({
  invalidPayload: 'invalid_payload',
  missingKey: 'missing_key',
  unknownKey: 'unknown_key',
  invalidRoutine: 'invalid_routine',
  invalidRoutineId: 'invalid_routine_id',
  routineMismatch: 'routine_mismatch',
  invalidNonce: 'invalid_nonce',
  invalidDuration: 'invalid_duration',
  invalidPlayedAt: 'invalid_played_at',
  implausibleDuration: 'implausible_duration',
  invalidScore: 'invalid_score',
  invalidSets: 'invalid_sets',
  setsMismatch: 'sets_mismatch',
  invalidReps: 'invalid_reps',
  scoreMismatch: 'score_mismatch',
  invalidResults: 'invalid_results',
  moveCountMismatch: 'move_count_mismatch',
  invalidMoveResult: 'invalid_move_result',
  invalidMoveIdx: 'invalid_move_idx',
  duplicateMoveIdx: 'duplicate_move_idx',
  invalidMoveScore: 'invalid_move_score',
  invalidWorstJoint: 'invalid_worst_joint',
  invalidDeviation: 'invalid_deviation',
});

export type ErrorCode = (typeof ERR)[keyof typeof ERR];

export type MoveResultInput = {
  move_idx: number;
  score: number;
  reps: number;
  worst_joint: string | null;
  deviation: number | null;
};

export type Submission = {
  routine_id: string;
  client_nonce: string;
  duration_ms: number;
  score: number;
  sets: number;
  /** ISO time the play happened; null = the server's upload time. */
  played_at: string | null;
  results: MoveResultInput[];
};

/**
 * [durationMs] is one set (the sum of the moves); the whole play is
 * durationMs * sets + restMs * (sets - 1). [repTargets] has one entry per
 * move: its reps per set, or null for a timed pose.
 */
export type RoutineInfo = {
  id: string;
  durationMs: number;
  moveCount: number;
  sets: number;
  restMs: number;
  repTargets: (number | null)[];
};

export type ValidationResult =
  | { ok: true; value: Submission }
  | { ok: false; error: ErrorCode };

const TOP_KEYS = ['routine_id', 'client_nonce', 'duration_ms', 'score', 'sets', 'results'];
const RESULT_KEYS = ['move_idx', 'score', 'reps', 'worst_joint', 'deviation'];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** null when the keys are exactly [expected], else the error code. */
function keyError(obj: Record<string, unknown>, expected: string[]): ErrorCode | null {
  for (const k of expected) {
    if (!Object.prototype.hasOwnProperty.call(obj, k)) return ERR.missingKey;
  }
  for (const k of Object.keys(obj)) {
    if (!expected.includes(k)) return ERR.unknownKey;
  }
  return null;
}

function isScore(v: unknown): v is number {
  return Number.isInteger(v) && (v as number) >= 0 && (v as number) <= 100;
}

function fail(error: ErrorCode): ValidationResult {
  return { ok: false, error };
}

/** Cheap check index.ts runs before loading the routine. */
export function isValidRoutineId(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0 && v.length <= MAX_ROUTINE_ID_LENGTH;
}

/** UUID shape check; index.ts uses it before the idempotency lookup. */
export function isValidNonce(v: unknown): v is string {
  return typeof v === 'string' && UUID_RE.test(v);
}

export function validateSubmission(
  payload: unknown,
  routine: RoutineInfo,
  now: number = Date.now(),
): ValidationResult {
  if (
    !Number.isInteger(routine.moveCount) || routine.moveCount < 1 ||
    !Number.isInteger(routine.durationMs) || routine.durationMs < 1 ||
    !Number.isInteger(routine.sets) || routine.sets < 1 ||
    !Number.isInteger(routine.restMs) || routine.restMs < 0 ||
    !Array.isArray(routine.repTargets) || routine.repTargets.length !== routine.moveCount ||
    routine.repTargets.some((t) => t !== null && (!Number.isInteger(t) || t < 1))
  ) {
    return fail(ERR.invalidRoutine);
  }
  if (!isPlainObject(payload)) return fail(ERR.invalidPayload);
  // played_at is optional so an older app (which never sends it) still works.
  const keys = keyError(
    payload,
    'played_at' in payload ? [...TOP_KEYS, 'played_at'] : TOP_KEYS,
  );
  if (keys) return fail(keys);

  const { routine_id, client_nonce, duration_ms, score, sets, results } = payload;

  if (!isValidRoutineId(routine_id)) return fail(ERR.invalidRoutineId);
  if (routine_id !== routine.id) return fail(ERR.routineMismatch);

  if (!isValidNonce(client_nonce)) return fail(ERR.invalidNonce);

  let playedAt: string | null = null;
  if ('played_at' in payload) {
    const raw = payload.played_at;
    const t = typeof raw === 'string' ? Date.parse(raw) : NaN;
    if (
      !Number.isFinite(t) ||
      t > now + PLAY_TIME_SKEW_MS ||
      t < now - MAX_PLAY_AGE_MS
    ) {
      return fail(ERR.invalidPlayedAt);
    }
    // Never later than the server's own clock.
    playedAt = new Date(Math.min(t, now)).toISOString();
  }

  if (!Number.isInteger(duration_ms)) return fail(ERR.invalidDuration);
  const d = duration_ms as number;
  // The client plays the routine's own number of sets, no more, no fewer.
  if (!Number.isInteger(sets)) return fail(ERR.invalidSets);
  if (sets !== routine.sets) return fail(ERR.setsMismatch);
  // Plausible: 0.8x..3x the whole play (every set plus the rests). Integer
  // math (5d >= 4D) keeps the 0.8x boundary exact.
  const total = routine.durationMs * routine.sets + routine.restMs * (routine.sets - 1);
  if (d * 5 < total * 4 || d > total * 3) {
    return fail(ERR.implausibleDuration);
  }

  if (!isScore(score)) return fail(ERR.invalidScore);

  if (!Array.isArray(results) || results.length > MAX_RESULTS) {
    return fail(ERR.invalidResults);
  }
  if (results.length !== routine.moveCount) return fail(ERR.moveCountMismatch);

  const seen = new Set<number>();
  const out: MoveResultInput[] = [];
  let sum = 0;
  for (const r of results) {
    if (!isPlainObject(r)) return fail(ERR.invalidMoveResult);
    const rk = keyError(r, RESULT_KEYS);
    if (rk) return fail(rk);

    const idx = r.move_idx;
    if (!Number.isInteger(idx) || (idx as number) < 0 || (idx as number) >= routine.moveCount) {
      return fail(ERR.invalidMoveIdx);
    }
    if (seen.has(idx as number)) return fail(ERR.duplicateMoveIdx);
    seen.add(idx as number);

    if (!isScore(r.score)) return fail(ERR.invalidMoveScore);

    // Reps are summed over sets. A timed pose counts none; a counted move
    // cannot plausibly exceed its target by more than REPS_OVERSHOOT.
    const reps = r.reps;
    const target = routine.repTargets[idx as number];
    const maxReps = target === null ? 0 : target * routine.sets * REPS_OVERSHOOT;
    if (!Number.isInteger(reps) || (reps as number) < 0 || (reps as number) > maxReps) {
      return fail(ERR.invalidReps);
    }

    const joint = r.worst_joint;
    if (joint !== null && (typeof joint !== 'string' || !JOINT_NAMES.includes(joint))) {
      return fail(ERR.invalidWorstJoint);
    }

    const dev = r.deviation;
    if (
      dev !== null &&
      (typeof dev !== 'number' || !Number.isFinite(dev) || Math.abs(dev) > DEVIATION_MAX_ABS)
    ) {
      return fail(ERR.invalidDeviation);
    }

    sum += r.score;
    out.push({
      move_idx: idx as number,
      score: r.score,
      reps: reps as number,
      worst_joint: joint as string | null,
      deviation: dev as number | null,
    });
  }

  // Client total is SessionSummary.totalScore = round(mean of move scores);
  // allow +-1 for rounding differences. Scores are >= 0, so Math.round
  // matches Dart's round() (half away from zero).
  if (Math.abs((score as number) - Math.round(sum / results.length)) > 1) {
    return fail(ERR.scoreMismatch);
  }

  out.sort((a, b) => a.move_idx - b.move_idx);
  return {
    ok: true,
    value: {
      routine_id,
      client_nonce,
      duration_ms: d,
      score: score as number,
      sets: sets as number,
      played_at: playedAt,
      results: out,
    },
  };
}

/** Allowed while the user has fewer than [max] sessions in the window. */
export function rateLimitDecision(recentCount: number, max: number): { allowed: boolean } {
  return { allowed: recentCount < max };
}
