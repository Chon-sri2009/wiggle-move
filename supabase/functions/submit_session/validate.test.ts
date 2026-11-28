// WM-10: tests for the pure submit_session validation.
// Run: node --test supabase/functions/submit_session/   (Node >= 22.18 / 23.6)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  DEVIATION_MAX_ABS,
  ERR,
  isValidNonce,
  JOINT_NAMES,
  MAX_RESULTS,
  MAX_ROUTINE_ID_LENGTH,
  rateLimitDecision,
  REPS_OVERSHOOT,
  validateSubmission,
} from './validate.ts';

const ROUTINE = {
  id: 'mia-pop-starter',
  durationMs: 10000,
  moveCount: 3,
  sets: 1,
  restMs: 0,
  repTargets: [null, null, null] as (number | null)[],
};

function payload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    routine_id: 'mia-pop-starter',
    client_nonce: '3f2b8c1e-9a4d-4c7b-8e2f-1a2b3c4d5e6f',
    duration_ms: 10000,
    score: 70,
    sets: 1,
    results: [
      { move_idx: 0, score: 60, reps: 0, worst_joint: 'leftElbow', deviation: -12.5 },
      { move_idx: 1, score: 70, reps: 0, worst_joint: null, deviation: null },
      { move_idx: 2, score: 80, reps: 0, worst_joint: 'rightKnee', deviation: 20 },
    ],
    ...overrides,
  };
}

function withResult(i: number, patch: Record<string, unknown>): Record<string, unknown> {
  const p = payload();
  const results = (p.results as Record<string, unknown>[]).map((r) => ({ ...r }));
  results[i] = { ...results[i], ...patch };
  p.results = results;
  return p;
}

function expectError(p: unknown, code: string, routine = ROUTINE): void {
  const r = validateSubmission(p, routine);
  assert.equal(r.ok, false, `expected ${code}, got ok`);
  if (!r.ok) assert.equal(r.error, code);
}

function expectOk(p: unknown, routine = ROUTINE): void {
  const r = validateSubmission(p, routine);
  assert.equal(r.ok, true, r.ok ? '' : `unexpected error ${r.error}`);
}

test('valid payload is accepted and returned normalized', () => {
  const r = validateSubmission(payload(), ROUTINE);
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.deepEqual(r.value, {
      routine_id: 'mia-pop-starter',
      client_nonce: '3f2b8c1e-9a4d-4c7b-8e2f-1a2b3c4d5e6f',
      duration_ms: 10000,
      score: 70,
      sets: 1,
      played_at: null,
      results: [
        { move_idx: 0, score: 60, reps: 0, worst_joint: 'leftElbow', deviation: -12.5 },
        { move_idx: 1, score: 70, reps: 0, worst_joint: null, deviation: null },
        { move_idx: 2, score: 80, reps: 0, worst_joint: 'rightKnee', deviation: 20 },
      ],
    });
  }
});

test('results may arrive in any order; value is sorted by move_idx', () => {
  const p = payload();
  p.results = [...(p.results as unknown[])].reverse();
  const r = validateSubmission(p, ROUTINE);
  assert.equal(r.ok, true);
  if (r.ok) assert.deepEqual(r.value.results.map((x) => x.move_idx), [0, 1, 2]);
});

test('non-object payloads are rejected', () => {
  for (const p of [null, undefined, 42, 'x', true, [], [payload()]]) {
    expectError(p, ERR.invalidPayload);
  }
});

test('missing and unknown top-level keys are rejected', () => {
  const missing = payload();
  delete missing.score;
  expectError(missing, ERR.missingKey);
  expectError(payload({ user_id: 'x' }), ERR.unknownKey);
});

test('routine_id must be a non-empty capped string matching the routine', () => {
  expectError(payload({ routine_id: 5 }), ERR.invalidRoutineId);
  expectError(payload({ routine_id: '' }), ERR.invalidRoutineId);
  expectError(payload({ routine_id: 'a'.repeat(MAX_ROUTINE_ID_LENGTH + 1) }), ERR.invalidRoutineId);
  expectError(payload({ routine_id: 'other' }), ERR.routineMismatch);
});

test('client_nonce must be a UUID string', () => {
  for (const n of [null, 1, '', 'not-a-uuid', '3f2b8c1e9a4d4c7b8e2f1a2b3c4d5e6f', '3f2b8c1e-9a4d-4c7b-8e2f-1a2b3c4d5e6g']) {
    expectError(payload({ client_nonce: n }), ERR.invalidNonce);
  }
  expectOk(payload({ client_nonce: '3F2B8C1E-9A4D-4C7B-8E2F-1A2B3C4D5E6F' }));
});

test('isValidNonce (used for the pre-validation idempotency lookup) accepts only UUID strings', () => {
  assert.equal(isValidNonce('3f2b8c1e-9a4d-4c7b-8e2f-1a2b3c4d5e6f'), true);
  assert.equal(isValidNonce('3F2B8C1E-9A4D-4C7B-8E2F-1A2B3C4D5E6F'), true);
  for (const n of [undefined, null, 1, {}, '', 'not-a-uuid', '3f2b8c1e9a4d4c7b8e2f1a2b3c4d5e6f',
    ' 3f2b8c1e-9a4d-4c7b-8e2f-1a2b3c4d5e6f']) {
    assert.equal(isValidNonce(n), false, String(n));
  }
});

test('duration_ms must be an integer', () => {
  for (const d of [null, '10000', 10000.5, NaN, Infinity, -Infinity]) {
    expectError(payload({ duration_ms: d }), ERR.invalidDuration);
  }
});

test('duration_ms boundaries: exactly 0.8x and 3x ok, just outside rejected', () => {
  expectOk(payload({ duration_ms: 8000 }));
  expectOk(payload({ duration_ms: 30000 }));
  expectError(payload({ duration_ms: 7999 }), ERR.implausibleDuration);
  expectError(payload({ duration_ms: 30001 }), ERR.implausibleDuration);
  expectError(payload({ duration_ms: 0 }), ERR.implausibleDuration);
  expectError(payload({ duration_ms: -1 }), ERR.implausibleDuration);
});

test('duration 0.8x boundary is exact for durations not divisible by 5', () => {
  // 0.8 * 4003 = 3202.4 -> 3203 is the smallest plausible integer.
  const routine = { ...ROUTINE, durationMs: 4003 };
  expectOk(payload({ duration_ms: 3203 }), routine);
  expectError(payload({ duration_ms: 3202 }), ERR.implausibleDuration, routine);
});

test('top-level score must be an integer 0..100', () => {
  for (const s of [null, '70', 70.5, NaN, Infinity, -1, 101]) {
    expectError(payload({ score: s }), ERR.invalidScore);
  }
});

test('top-level score must equal round(mean) within +-1', () => {
  // mean of 60, 70, 80 = 70.
  expectOk(payload({ score: 69 }));
  expectOk(payload({ score: 71 }));
  expectError(payload({ score: 68 }), ERR.scoreMismatch);
  expectError(payload({ score: 72 }), ERR.scoreMismatch);
});

test('score mean rounds half up like Dart round()', () => {
  // (50 + 51 + 52) / 3 = 51.
  const p = payload({ score: 52 });
  p.results = [
    { move_idx: 0, score: 50, reps: 0, worst_joint: null, deviation: null },
    { move_idx: 1, score: 51, reps: 0, worst_joint: null, deviation: null },
    { move_idx: 2, score: 52, reps: 0, worst_joint: null, deviation: null },
  ];
  // mean 51 -> 52 ok (+1), 53 rejected.
  expectOk(p);
  expectError({ ...p, score: 53 }, ERR.scoreMismatch);
  // mean 50.5 (two moves 50, 51) rounds to 51 -> 52 ok, 49 rejected.
  const two = { ...ROUTINE, moveCount: 2, repTargets: [null, null] };
  const q = payload({
    score: 52,
    results: [
      { move_idx: 0, score: 50, reps: 0, worst_joint: null, deviation: null },
      { move_idx: 1, score: 51, reps: 0, worst_joint: null, deviation: null },
    ],
  });
  expectOk(q, two);
  expectError({ ...q, score: 49 }, ERR.scoreMismatch, two);
});

test('results must be an array of exactly moveCount entries', () => {
  expectError(payload({ results: null }), ERR.invalidResults);
  expectError(payload({ results: {} }), ERR.invalidResults);
  const p = payload();
  p.results = (p.results as unknown[]).slice(0, 2);
  expectError(p, ERR.moveCountMismatch);
  const q = payload();
  q.results = [...(q.results as unknown[]), { move_idx: 3, score: 70, reps: 0, worst_joint: null, deviation: null }];
  expectError(q, ERR.moveCountMismatch);
});

test('results array is capped before iterating', () => {
  const huge = Array.from({ length: MAX_RESULTS + 1 }, (_, i) => ({
    move_idx: i, score: 70, worst_joint: null, deviation: null,
  }));
  expectError(payload({ results: huge }), ERR.invalidResults, {
    ...ROUTINE,
    moveCount: MAX_RESULTS + 1,
    repTargets: new Array<number | null>(MAX_RESULTS + 1).fill(null),
  });
});

test('each result must be an object with exactly the five keys', () => {
  for (const bad of [null, 7, 'x', [0, 60]]) {
    const p = payload();
    (p.results as unknown[])[0] = bad;
    expectError(p, ERR.invalidMoveResult);
  }
  const missing = payload();
  const r0 = { ...(missing.results as Record<string, unknown>[])[0] };
  delete r0.deviation;
  (missing.results as unknown[])[0] = r0;
  expectError(missing, ERR.missingKey);
  expectError(withResult(0, { frames: 10 }), ERR.unknownKey);
});

test('move_idx must be integers 0..moveCount-1, each exactly once', () => {
  expectError(withResult(0, { move_idx: '0' }), ERR.invalidMoveIdx);
  expectError(withResult(0, { move_idx: 0.5 }), ERR.invalidMoveIdx);
  expectError(withResult(0, { move_idx: -1 }), ERR.invalidMoveIdx);
  expectError(withResult(0, { move_idx: 3 }), ERR.invalidMoveIdx);
  expectError(withResult(0, { move_idx: 1 }), ERR.duplicateMoveIdx);
});

test('move score must be an integer 0..100', () => {
  expectOk(payload({
    score: 33,
    results: [
      { move_idx: 0, score: 0, reps: 0, worst_joint: null, deviation: null },
      { move_idx: 1, score: 100, reps: 0, worst_joint: null, deviation: null },
      { move_idx: 2, score: 0, reps: 0, worst_joint: null, deviation: null },
    ],
  }));
  for (const s of [null, '60', 60.5, NaN, Infinity, -1, 101]) {
    expectError(withResult(0, { score: s }), ERR.invalidMoveScore);
  }
});

test('worst_joint must be null or a Joint enum name', () => {
  assert.deepEqual([...JOINT_NAMES], [
    'leftElbow', 'rightElbow', 'leftShoulder', 'rightShoulder',
    'leftHip', 'rightHip', 'leftKnee', 'rightKnee',
  ]);
  for (const j of JOINT_NAMES) expectOk(withResult(0, { worst_joint: j }));
  for (const j of ['left elbow', 'LeftElbow', '', 3, 'toString', '__proto__']) {
    expectError(withResult(0, { worst_joint: j }), ERR.invalidWorstJoint);
  }
});

test('deviation must be null or a finite signed number within +-360', () => {
  assert.equal(DEVIATION_MAX_ABS, 360);
  for (const d of [0, -12.5, 360, -360, 179.9]) expectOk(withResult(0, { deviation: d }));
  for (const d of [NaN, Infinity, -Infinity, 360.0001, -360.0001, '12']) {
    expectError(withResult(0, { deviation: d }), ERR.invalidDeviation);
  }
});

test('a routine with no moves cannot be submitted', () => {
  expectError(payload({ score: 0, results: [] }), ERR.invalidRoutine, { ...ROUTINE, moveCount: 0, repTargets: [] });
});

test('error codes are stable strings', () => {
  assert.deepEqual(ERR, {
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
});

test('rateLimitDecision allows below max and rejects at or above it', () => {
  assert.deepEqual(rateLimitDecision(0, 30), { allowed: true });
  assert.deepEqual(rateLimitDecision(29, 30), { allowed: true });
  assert.deepEqual(rateLimitDecision(30, 30), { allowed: false });
  assert.deepEqual(rateLimitDecision(31, 30), { allowed: false });
});

// --- Sets and reps (cardio) -------------------------------------------------

// Two moves: a counted one (12 reps per set) and a timed pose; 3 sets of
// 4000 + 6000 ms with 5000 ms rests: 3 * 10000 + 2 * 5000 = 40000 ms.
const CARDIO = {
  id: 'mia-pop-starter',
  durationMs: 10000,
  moveCount: 2,
  sets: 3,
  restMs: 5000,
  repTargets: [12, null] as (number | null)[],
};

function cardioPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return payload({
    duration_ms: 40000,
    sets: 3,
    score: 65,
    results: [
      { move_idx: 0, score: 60, reps: 30, worst_joint: null, deviation: null },
      { move_idx: 1, score: 70, reps: 0, worst_joint: null, deviation: null },
    ],
    ...overrides,
  });
}

test('a valid cardio play is accepted and keeps sets and reps', () => {
  const r = validateSubmission(cardioPayload(), CARDIO);
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.value.sets, 3);
    assert.deepEqual(r.value.results.map((x) => x.reps), [30, 0]);
  }
});

test('sets must be an integer equal to the routine sets', () => {
  for (const s of [null, '3', 3.5, NaN]) {
    expectError(cardioPayload({ sets: s }), ERR.invalidSets, CARDIO);
  }
  expectError(cardioPayload({ sets: 2 }), ERR.setsMismatch, CARDIO);
  expectError(cardioPayload({ sets: 4 }), ERR.setsMismatch, CARDIO);
  expectError(payload({ sets: 2 }), ERR.setsMismatch); // single-set routine
  const missing = cardioPayload();
  delete missing.sets;
  expectError(missing, ERR.missingKey, CARDIO);
});

test('duration is judged against every set plus the rests between', () => {
  const total = 3 * 10000 + 2 * 5000; // 40000
  expectOk(cardioPayload({ duration_ms: total }), CARDIO);
  expectOk(cardioPayload({ duration_ms: total * 0.8 }), CARDIO);
  expectOk(cardioPayload({ duration_ms: total * 3 }), CARDIO);
  expectError(cardioPayload({ duration_ms: total * 0.8 - 1 }), ERR.implausibleDuration, CARDIO);
  expectError(cardioPayload({ duration_ms: total * 3 + 1 }), ERR.implausibleDuration, CARDIO);
  // One set's worth of time is no longer enough for a 3-set routine.
  expectError(cardioPayload({ duration_ms: 10000 }), ERR.implausibleDuration, CARDIO);
});

test('reps: integer >= 0, zero for timed poses, bounded by the target', () => {
  const max = 12 * 3 * REPS_OVERSHOOT; // 108
  const res = (reps: unknown, timedReps: unknown = 0) => [
    { move_idx: 0, score: 60, reps, worst_joint: null, deviation: null },
    { move_idx: 1, score: 70, reps: timedReps, worst_joint: null, deviation: null },
  ];
  expectOk(cardioPayload({ results: res(0) }), CARDIO);
  expectOk(cardioPayload({ results: res(max) }), CARDIO);
  for (const bad of [max + 1, -1, 1.5, '5', null, NaN]) {
    expectError(cardioPayload({ results: res(bad) }), ERR.invalidReps, CARDIO);
  }
  // A timed pose cannot report reps.
  expectError(cardioPayload({ results: res(12, 1) }), ERR.invalidReps, CARDIO);
});

test('repTargets must match the move count and be positive integers or null', () => {
  expectError(cardioPayload(), ERR.invalidRoutine, { ...CARDIO, repTargets: [12] });
  expectError(cardioPayload(), ERR.invalidRoutine, { ...CARDIO, repTargets: [0, null] });
  expectError(cardioPayload(), ERR.invalidRoutine, { ...CARDIO, sets: 0 });
  expectError(cardioPayload(), ERR.invalidRoutine, { ...CARDIO, restMs: -1 });
});

test('played_at is optional; absent means null (server time)', () => {
  const r = validateSubmission(payload(), ROUTINE);
  assert.equal(r.ok, true);
  if (r.ok) assert.equal(r.value.played_at, null);
});

test('played_at: a recent past time is kept, far past and future are rejected', () => {
  const now = Date.parse('2026-01-10T12:00:00Z');
  const ok = validateSubmission(payload({ played_at: '2026-01-09T23:50:00Z' }), ROUTINE, now);
  assert.equal(ok.ok, true);
  if (ok.ok) assert.equal(ok.value.played_at, '2026-01-09T23:50:00.000Z');

  for (const bad of ['2025-11-01T00:00:00Z', '2026-01-11T00:00:00Z', 'yesterday', 5, null]) {
    const r = validateSubmission(payload({ played_at: bad }), ROUTINE, now);
    assert.equal(r.ok, false, String(bad));
    if (!r.ok) assert.equal(r.error, ERR.invalidPlayedAt);
  }
});

test('played_at slightly ahead of the server clock is clamped to now', () => {
  const now = Date.parse('2026-01-10T12:00:00Z');
  const r = validateSubmission(payload({ played_at: '2026-01-10T12:03:00Z' }), ROUTINE, now);
  assert.equal(r.ok, true);
  if (r.ok) assert.equal(r.value.played_at, '2026-01-10T12:00:00.000Z');
});

// index.ts needs Deno to run, so its check order is guarded by reading the
// source: a retry of a stored play must be answered (idempotency lookup)
// before the rate limit can turn it into a 429, or the offline queue stalls.
test('index.ts checks idempotency before validation and the rate limit', () => {
  const src = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
  const at = (needle: string): number => {
    const i = src.indexOf(needle);
    assert.ok(i >= 0, `index.ts no longer contains: ${needle}`);
    return i;
  };
  const idempotency = at("eq('client_nonce', nonce)");
  const validate = at('validateSubmission(');
  const rate = at("error(429, 'rate_limited')");
  const store = at("admin.rpc('submit_session_tx'");
  assert.ok(idempotency < validate && validate < rate && rate < store);
});
