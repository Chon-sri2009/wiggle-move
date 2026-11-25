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

/** Raw request body cap (bytes), enforced by index.ts before JSON.parse. */
export const MAX_BODY_BYTES = 32 * 1024;

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
  implausibleDuration: 'implausible_duration',
  invalidScore: 'invalid_score',
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
  worst_joint: string | null;
  deviation: number | null;
};

export type Submission = {
  routine_id: string;
  client_nonce: string;
  duration_ms: number;
  score: number;
  results: MoveResultInput[];
};

export type RoutineInfo = { id: string; durationMs: number; moveCount: number };

export type ValidationResult =
  | { ok: true; value: Submission }
  | { ok: false; error: ErrorCode };

const TOP_KEYS = ['routine_id', 'client_nonce', 'duration_ms', 'score', 'results'];
const RESULT_KEYS = ['move_idx', 'score', 'worst_joint', 'deviation'];
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

export function validateSubmission(payload: unknown, routine: RoutineInfo): ValidationResult {
  if (
    !Number.isInteger(routine.moveCount) || routine.moveCount < 1 ||
    !Number.isInteger(routine.durationMs) || routine.durationMs < 1
  ) {
    return fail(ERR.invalidRoutine);
  }
  if (!isPlainObject(payload)) return fail(ERR.invalidPayload);
  const keys = keyError(payload, TOP_KEYS);
  if (keys) return fail(keys);

  const { routine_id, client_nonce, duration_ms, score, results } = payload;

  if (!isValidRoutineId(routine_id)) return fail(ERR.invalidRoutineId);
  if (routine_id !== routine.id) return fail(ERR.routineMismatch);

  if (typeof client_nonce !== 'string' || !UUID_RE.test(client_nonce)) {
    return fail(ERR.invalidNonce);
  }

  if (!Number.isInteger(duration_ms)) return fail(ERR.invalidDuration);
  const d = duration_ms as number;
  // Plausible: 0.8x..3x the routine length. Integer math (5d >= 4D) keeps
  // the 0.8x boundary exact.
  if (d * 5 < routine.durationMs * 4 || d > routine.durationMs * 3) {
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
      results: out,
    },
  };
}

/** Allowed while the user has fewer than [max] sessions in the window. */
export function rateLimitDecision(recentCount: number, max: number): { allowed: boolean } {
  return { allowed: recentCount < max };
}
