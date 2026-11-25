// WM-10: tests for the pure submit_session validation.
// Run: node --test supabase/functions/submit_session/   (Node >= 22.18 / 23.6)
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  DEVIATION_MAX_ABS,
  ERR,
  JOINT_NAMES,
  MAX_RESULTS,
  MAX_ROUTINE_ID_LENGTH,
  rateLimitDecision,
  validateSubmission,
} from './validate.ts';

const ROUTINE = { id: 'mia-pop-starter', durationMs: 10000, moveCount: 3 };

function payload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    routine_id: 'mia-pop-starter',
    client_nonce: '3f2b8c1e-9a4d-4c7b-8e2f-1a2b3c4d5e6f',
    duration_ms: 10000,
    score: 70,
    results: [
      { move_idx: 0, score: 60, worst_joint: 'leftElbow', deviation: -12.5 },
      { move_idx: 1, score: 70, worst_joint: null, deviation: null },
      { move_idx: 2, score: 80, worst_joint: 'rightKnee', deviation: 20 },
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
      results: [
        { move_idx: 0, score: 60, worst_joint: 'leftElbow', deviation: -12.5 },
        { move_idx: 1, score: 70, worst_joint: null, deviation: null },
        { move_idx: 2, score: 80, worst_joint: 'rightKnee', deviation: 20 },
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
    { move_idx: 0, score: 50, worst_joint: null, deviation: null },
    { move_idx: 1, score: 51, worst_joint: null, deviation: null },
    { move_idx: 2, score: 52, worst_joint: null, deviation: null },
  ];
  // mean 51 -> 52 ok (+1), 53 rejected.
  expectOk(p);
  expectError({ ...p, score: 53 }, ERR.scoreMismatch);
  // mean 50.5 (two moves 50, 51) rounds to 51 -> 52 ok, 49 rejected.
  const two = { ...ROUTINE, moveCount: 2 };
  const q = payload({
    score: 52,
    results: [
      { move_idx: 0, score: 50, worst_joint: null, deviation: null },
      { move_idx: 1, score: 51, worst_joint: null, deviation: null },
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
  q.results = [...(q.results as unknown[]), { move_idx: 3, score: 70, worst_joint: null, deviation: null }];
  expectError(q, ERR.moveCountMismatch);
});

test('results array is capped before iterating', () => {
  const huge = Array.from({ length: MAX_RESULTS + 1 }, (_, i) => ({
    move_idx: i, score: 70, worst_joint: null, deviation: null,
  }));
  expectError(payload({ results: huge }), ERR.invalidResults, { ...ROUTINE, moveCount: MAX_RESULTS + 1 });
});

test('each result must be an object with exactly the four keys', () => {
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
      { move_idx: 0, score: 0, worst_joint: null, deviation: null },
      { move_idx: 1, score: 100, worst_joint: null, deviation: null },
      { move_idx: 2, score: 0, worst_joint: null, deviation: null },
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
  expectError(payload({ score: 0, results: [] }), ERR.invalidRoutine, { ...ROUTINE, moveCount: 0 });
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
});

test('rateLimitDecision allows below max and rejects at or above it', () => {
  assert.deepEqual(rateLimitDecision(0, 30), { allowed: true });
  assert.deepEqual(rateLimitDecision(29, 30), { allowed: true });
  assert.deepEqual(rateLimitDecision(30, 30), { allowed: false });
  assert.deepEqual(rateLimitDecision(31, 30), { allowed: false });
});
