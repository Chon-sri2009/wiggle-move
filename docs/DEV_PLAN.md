# Wiggle Move — Development Plan (WM-01 → WM-xx)

## Context
Wiggle Move is a Flutter app (trainer → camera workout → pose score → summary → leaderboard). Today (3 commits, `D:\Wiggle_Move_App\wiggle_move_app1`):
- Done: theme/palette, login & sign-up (UI only, name saved on device), 4-step personalization, home, trainer/routine screens, camera workout with ML Kit, pure-Dart scoring (unit-tested), summary, per-device leaderboard.
- Missing for a "complete backend + frontend": real accounts, shared database, shared leaderboard, trainer content/video, Figma-accurate screens for everything beyond auth/onboarding/home, device validation.
- Goal of this plan: finish a complete, shippable backend + frontend **without the AI detection engine**, leaving a clean seam so the trained model drops in later. Plan is written so humans and AI agents (Claude Code) can split work without colliding.

Stack (already decided in `docs/PROJECT.md`, keep): Flutter + Riverpod + go_router; Supabase (Auth, Postgres+RLS, Storage, Edge Functions). Ticket codes: `WM-01`, `WM-02`, … (zero-padded 2 digits; roll to `WM-100` when needed). Branch `feature/wm-07-supabase-auth`, commit subject `WM-07 Add Supabase auth`.

## Owner legend
- **H** = human only (needs judgment, accounts, devices, design sign-off, secrets)
- **AI** = Claude Code can do end to end; human only reviews the PR
- **H+AI** = human supplies input/decision, AI implements (or AI drafts, human verifies on device)

## Working agreement (how humans and AI share the repo)
1. One ticket = one branch = one PR into `main`; ≤ ~400 changed lines. No two open tickets touch the same files (see "Collision map").
2. Every AI ticket starts from a **ticket brief** (template below) pasted into the session. AI must not widen scope; surprises become new tickets.
3. Gate before any PR: `dart format lib test`, `flutter analyze` clean, `flutter test` green. AI runs these and pastes the result in the PR.
4. Anything involving camera, ML Kit, real backend keys, store accounts, or visual fidelity is verified by a **human on a physical phone** — AI never claims "works on device".
5. Secrets: only `--dart-define` / Supabase dashboard. Never in git. AI never asks for or prints keys.
6. Schema/RLS changes only through migration files in `supabase/migrations/` (reviewed by a human before `supabase db push`).
7. Decisions that change architecture update `docs/PROJECT.md` §4 in the same PR.

Ticket brief template: `ID · goal · files allowed to touch · acceptance criteria · how to verify · out of scope`.

## Phase 0 — Foundations (unblock everyone)
| ID | Owner | Task | Done when |
|---|---|---|---|
| WM-01 | H+AI | Plan kickoff: commit this plan as `docs/DEV_PLAN.md`, create GitHub remote + `main` protection, issue labels `H`/`AI`/`H+AI`, board columns | Repo on remote; plan visible to team |
| WM-02 | H | Install Android SDK/Xcode, run current app on a physical phone, record device models + FPS + whether landmarks detect (validates the untested `pose_service.dart` path) | Short device report in `docs/DEVICE_LOG.md`; blockers filed as tickets |
| WM-03 | H | Export Figma: full frame list, rabbit logo SVG/PNG, font files, trainer avatars, icon set. Mark which frames exist for workout / summary / leaderboard / profile (CLAUDE.md says none yet) | Assets in `assets/` request list + frame inventory table in `docs/FIGMA_MAP.md` |
| WM-04 | H | Create Supabase project (dev + prod), invite team, share URL/anon key via password manager | Keys distributed; no keys in git |
| WM-05 | AI | Rename package `wiggle_move_app1` → `wiggle_move` (pubspec, Android/iOS ids, imports), add `lib/shared/`, env config via `--dart-define` with a clear startup error if missing | Analyze/test green; app boots |
| WM-06 | AI | CI (GitHub Actions): format check, analyze, test on every PR | Required check on `main` |

## Phase 1 — Backend (Supabase) — can run parallel to Phase 2
| ID | Owner | Task | Done when |
|---|---|---|---|
| WM-07 | H+AI | Schema migration: `profiles`(id→auth.users, display_name, avatar, goals[], styles[], level, onboarded), `trainers`, `routines`(trainer_id, level, video_path, duration_ms), `moves`(routine_id, idx, name, instruction, duration_ms, target_angles jsonb), `sessions`(user_id, routine_id, score, played_at), `move_results`(session_id, move_idx, score, worst_joint, deviation). AI writes SQL; human reviews | Migration applies cleanly to dev |
| WM-08 | H+AI | RLS policies: users read/write only their own profile/sessions/move_results; trainers/routines/moves public read; no client write to content tables. AI adds SQL tests (pgTAP or scripted checks) | Cross-user read/write attempts fail in tests |
| WM-09 | AI | Leaderboard: SQL view/materialized view (best score per user per routine; global + weekly); index on (routine_id, score desc) | Query returns correct ranking on seed data |
| WM-10 | AI | Edge Function `submit_session`: validates payload (score 0–100, move count matches routine, plausible duration/rate-limit), inserts session + results transactionally. Client never inserts into `sessions` directly | Bad payloads rejected; valid stored |
| WM-11 | H+AI | Seed data: move today's hardcoded trainers/routines (`trainer_data.dart`) into `supabase/seed.sql`; Storage bucket `routine-videos` (public read, admin write) | Fresh DB has same content as the app today |
| WM-12 | H | Backup/prod promotion checklist, auth email templates, redirect URLs, Terms/Privacy links | Prod project ready |

## Phase 2 — Frontend (Figma fidelity + real data)
Existing screens are re-checked against Figma by a human; AI fixes diffs.
| ID | Owner | Task | Done when |
|---|---|---|---|
| WM-13 | AI | Design tokens audit vs Figma (colors, type scale, spacing, radii) + load Figma font + real logo asset; replace placeholder `wiggle_logo.dart` | Side-by-side screenshot matches (human signs off) |
| WM-14 | AI | Shared widgets in `lib/shared/` (buttons, inputs, cards, loading/empty/error states, snackbars) extracted from existing screens | No duplicated styling across features |
| WM-15 | H+AI | Missing Figma screens: human designs/approves workout HUD, summary, leaderboard, profile, history, settings in Figma first; AI then implements each as its own ticket (WM-15a…) | Each screen has a Figma frame link before coding |
| WM-16 | AI | Profile screen: edit name/avatar/goals/styles/level, sign out, delete account (calls backend) | Round-trips to `profiles` |
| WM-17 | AI | History screen: past sessions list → tap opens that session's summary (reuses `SummaryScreen` with stored `move_results`) | Works offline-empty and with data |
| WM-18 | AI | Home personalization: sort/filter trainers & routines by profile level/styles; trainer photos from Storage | Matches Figma home |
| WM-19 | AI | Accessibility + permission states: camera denied/permanently denied flow, unsupported-platform message, text scaling, semantics, haptics/sound hooks | Manual checklist passes |

## Phase 3 — Wire frontend to backend (needs WM-04, 07, 08, 10, 11)
| ID | Owner | Task | Done when |
|---|---|---|---|
| WM-20 | AI | Supabase init + Auth: email sign-up/login/logout, session restore, router redirect driven by auth session (replaces `playerNameProvider` as the "signed in" source); password reset | Real accounts; old local-name path removed |
| WM-21 | AI | Profile repository: onboarding answers saved to `profiles`; `onboarded` read from server | New device login skips onboarding |
| WM-22 | AI | Content repository: trainers/routines/moves fetched from Supabase with local cache + loading/error UI (replace `trainer_data.dart` as source; keep file as test fixture) | App works from DB data; offline shows cached |
| WM-23 | AI | Sessions repository: on workout end call `submit_session`; retry queue if offline | Session visible in History + leaderboard |
| WM-24 | AI | Leaderboard screen on server data: routine/global tabs, weekly/all-time, "you" row highlighted, pull-to-refresh; remove `leaderboard_store.dart` entries logic (keep `rankEntries` only if still tested) | Two accounts see each other |
| WM-25 | AI | Migrate/clear old local leaderboard data on first launch after upgrade | No crash on old prefs |
| WM-26 | H | Social login (Apple required if shipping iOS with other social logins; Google) — accounts, OAuth config | Providers enabled (AI implements client in WM-26b) |

## Phase 4 — Workout experience (non-AI parts)
| ID | Owner | Task | Done when |
|---|---|---|---|
| WM-27 | H | Record/obtain trainer routine videos; decide per-move timestamps | Videos in Storage, timeline sheet per routine |
| WM-28 | AI | Video playback in workout (`video_player`, justify dependency in PR), sync move timeline to video clock, pause/resume/quit, lifecycle handling | Timeline driven by video position |
| WM-29 | AI | Skeleton overlay + live meter polish per Figma; countdown, haptics | Matches Figma on device (human verifies) |
| WM-30 | H+AI | Calibration tooling: debug screen logging measured angles per pose; human performs poses, AI updates targets in seed + tests | Targets stored in `moves.target_angles` |

## Phase 5 — Quality & release
| ID | Owner | Task | Done when |
|---|---|---|---|
| WM-31 | AI | Tests: repository fakes, widget tests for auth/onboarding/home/leaderboard, router redirect tests, integration test of full flow with fake backend | Coverage on all providers/repositories |
| WM-32 | H | Device matrix test (low/mid/high Android, iPhone), battery/thermal, bad lighting | Report + issues |
| WM-33 | H+AI | Error monitoring + analytics (privacy-reviewed; no frames ever uploaded) | Crash reports visible |
| WM-34 | H | App icons, splash, store listings, privacy policy (camera usage, on-device processing), signing keys, TestFlight/Play internal track | Internal beta live |
| WM-35 | H | Security review of RLS + edge function; pen-test auth flows | Findings closed |

## Phase 6 — AI detection engine (deferred, planned seam only)
Seam already exists and must stay stable so the trained model plugs in without UI/backend changes:
- Input: camera frames → `PoseService.detect()` returns `Map<Joint,double>?` (`lib/features/workout/pose_service.dart`).
- Scoring: `MoveScorer` / `WorkoutSession` consume angles and emit `MoveResult` (pure Dart, tested).
- Output contract to backend: `{routine_id, move_idx, score 0–100, worst_joint, deviation}` — already what `submit_session` (WM-10) accepts.
| ID | Owner | Task |
|---|---|---|
| WM-36 | H | Deliver trained model + eval report (accuracy, latency on target devices, model format: TFLite/Core ML/ML Kit custom) |
| WM-37 | AI | Define `PoseEstimator` / `MoveJudge` interfaces **only when a second implementation exists**; load model, run behind a feature flag next to ML Kit; A/B on recorded sessions |
| WM-38 | H+AI | Replace angle-tolerance scoring or add model-based judge; recalibrate; update server sanity bounds (WM-10) |
Until WM-36 lands: do not add abstractions "for the model" — the current functions are the seam.

## Collision map (who may touch what in parallel)
- Backend track: `supabase/**` only (WM-07–12) — safe in parallel with frontend.
- Frontend shared: `lib/shared/**`, `lib/app/theme.dart` (WM-13/14) — land first, then screens.
- Per-feature tickets stay inside `lib/features/<feature>/**`; `lib/app/app.dart` (router) edits are serialized — one ticket at a time, announce in channel.
- Data wiring (Phase 3) must wait for its backend ticket; use fake repositories so UI tickets don't block.

## Suggested sequencing / team split
1. Week 1: WM-01..06 (H does 02/03/04 while AI does 05/06).
2. Weeks 1–3: Backend track (WM-07..11) ∥ Frontend track (WM-13,14, then 15-screens after Figma sign-off, 16–19).
3. Weeks 3–4: Phase 3 wiring (20–25), then Phase 4 (27 content in parallel from week 1).
4. Week 5+: Phase 5, internal beta. Phase 6 starts when model is delivered.
Critical path: WM-04 → 07/08/10/11 → 20..24; WM-03 → 13/15; WM-02 → 30.

## Verification (end-to-end acceptance for "complete backend + frontend, no AI engine")
- Fresh install on a phone: sign up → onboarding → home shows server trainers → play routine (video + camera, existing ML Kit scoring) → summary → session appears in History → second account sees you on the leaderboard.
- RLS: user B cannot read/write user A's sessions (automated test).
- `submit_session` rejects out-of-range/duplicate/flooded submissions.
- CI green: format, analyze, test. Human checklist signed in `docs/DEVICE_LOG.md`.

## Open questions for the team
1. Figma has frames only for auth/onboarding/home — who designs workout/summary/leaderboard/profile (blocks WM-15)?
2. Email-only auth for v1, or social login too (WM-26)?
3. Leaderboard scope: global only, or friends/groups later?
4. Who records trainer videos and defines timestamps (WM-27)?
5. Confirm "WM-01 as start code" means ticket numbering as used here.
