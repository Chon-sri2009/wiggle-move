# CLAUDE.md — Wiggle Move

Guidance for Claude Code and humans working in this repo. Product/architecture detail lives in [docs/PROJECT.md](docs/PROJECT.md); git rules in [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## What this is
Flutter mobile app. User picks a trainer, dances/works out along with a video, the phone camera + on-device pose detection scores each move, a leaderboard ranks users, and an end-of-session summary shows which moves went wrong.

## Stack
- Flutter 3.47 / Dart 3.13 (Android + iOS are the real targets; web/desktop folders exist but pose detection does not run there)
- State: `flutter_riverpod` · Routing: `go_router`
- Camera: `camera` · Pose AI: `google_mlkit_pose_detection` (on-device, no video leaves the phone)
- Backend: Supabase (`supabase_flutter`) — auth, trainers/routines, sessions, leaderboard

## Commands (run from this folder)
```powershell
flutter pub get
flutter run                 # needs a physical Android/iOS device for camera + pose
flutter analyze             # must be clean before commit
flutter test                # must pass before commit
dart format lib test
```

## Layout
Feature-first under `lib/`:
- `lib/main.dart` — entry, wraps app in `ProviderScope`
- `lib/app/` — `MaterialApp.router`, theme, routes
- `lib/features/<feature>/` — one folder per feature: `home`, `trainers` (trainer screen + `trainersProvider`), `scoring` (scorer), `workout` (session, ML Kit service, camera screen), `summary`, `leaderboard` (screen + `leaderboardProvider`). Keep UI, providers and data code for a feature together.
- Code shared by 2+ features goes in `lib/shared/` (`pose/pose_math.dart` holds the pure-Dart `Joint`/`Lm`/`MoveTarget` types and angle math, moved out of `features/scoring` in WM-22 so content models in `shared/backend` can use them; `env.dart` holds dart-define config; `env_error_screen.dart` is the startup error; `prefs.dart` holds `sharedPrefsProvider`). `lib/shared` must not import `lib/features`.
- Backend access goes through repositories in `lib/shared/backend/` (see below).
- Tests mirror `lib/` under `test/`.

## Backend repositories
- Each backend area is an `abstract class XRepository` in `lib/shared/backend/` with two implementations: `SupabaseXRepository` (real backend) and an offline/in-memory one (used under `WM_OFFLINE`).
- A Riverpod provider picks the implementation from `Env`: `Env.offline` → offline, otherwise Supabase. `main()` only calls `Supabase.initialize` when not offline, so in tests the provider **must** be overridden (fakes live in `test/support/fakes.dart`).
- Repositories throw typed, user-safe failures (e.g. `AuthFailure`); raw server messages are never shown. Map errors in a pure function and unit-test it.
- Failures: `AuthFailure` for auth, `RepositoryFailure` (`profile_repository.dart`, mapped by `mapRepositoryException`) for data.
- Auth (WM-20): `authRepositoryProvider` + `authUserProvider` (the signed-in `AppUser`, seeded from the restored session) drive the router redirect. Sign-up sends `display_name` as user metadata; the `handle_new_user` DB trigger copies it to `profiles`.
- Profile (WM-21): `profileRepositoryProvider` (`ProfileRepository.load/save`, model in `shared/backend/profile.dart`). `profileProvider` (features/profile) is an `AsyncNotifier` that reloads when the auth user id changes. The router redirect (`appRedirect` in `app/app.dart`, pure and unit-tested) parks a signed-in user on `/loading` while the profile loads or failed (Retry), so onboarding comes from the server, not a default.
- Content (WM-22): `contentRepositoryProvider` (`ContentRepository.fetchTrainers`; models + JSON codec in `shared/backend/content_models.dart`). Supabase reads `trainers` with embedded `routines(*, moves(*))` in one request and sorts by `sort_order`/`idx` client-side; any malformed row (incl. a routine with no moves or a blank trainer name) fails the whole fetch (no partial content). `shared/backend/trainer_data.dart` is the built-in content: served only by `OfflineContentRepository` (WM_OFFLINE) and used as a test fixture; app code must not import it. `ContentCache` keeps the last good fetch in SharedPreferences per install (public content, survives sign-out; a corrupt cache is discarded). `trainersProvider` (features/trainers) is stale-while-revalidate: cached content at once, then the fetch replaces it; a failed fetch keeps the cache and sets `isStale` (Home shows a "showing saved content" note, pull to refresh); only the latest of overlapping fetches may write state or the cache; no cache + failure is an error with Retry. Routes look up content through `trainerProvider(id)`/`routineProvider(id)` inside `ContentGate` (loading / error+Retry / not found).
- Sessions (WM-23): `sessionsRepositoryProvider` (`SessionsRepository.submit` returns a `SubmitOutcome` and never throws: `SubmitSaved(duplicate)`, `SubmitRetryable(reason)` or `SubmitRejected(message)`; models + `classifyStatus`/`classifyError` in `shared/backend/sessions_repository.dart`). Supabase calls the `submit_session` Edge Function (`toPayload()` is exactly its key set; no user id). Retryable = no response/timeout, relay error, 401, 408, 429, 5xx; every other 4xx is rejected (permanent), because the queue stops at the first retryable entry. `OfflineSessionsRepository` (WM_OFFLINE) appends to the local leaderboard key and always saves. `PendingSubmissionQueue` (SharedPreferences, cap 50, oldest dropped and counted) holds retryable plays with their owner; `SessionSync.flush()` sends only the signed-in user's entries, oldest first, stopping at the first retryable one; overlapping flushes are shared. Flush triggers: after a workout submit (saved or queued), app start, sign-in, app resume (`WiggleMoveApp` lifecycle observer). The workout generates the client nonce once per play (`uuidV4()` in `shared/uuid.dart`), submits without blocking navigation, and the summary shows the status from `submissionStatusProvider` (by nonce).

- Leaderboard (WM-24): `leaderboardRepositoryProvider` (`LeaderboardRepository.fetch(routineId, period, limit)` -> `LeaderboardRow`s with server-given ranks; Supabase calls the `leaderboard` rpc and any malformed row fails the whole fetch). `OfflineLeaderboardRepository` (WM_OFFLINE) ranks the plays `OfflineSessionsRepository` stored under `localLeaderboardKey` with the same rules (best per routine, global = sum, ties share rank, week = since Monday 00:00 UTC). `leaderboardProvider` (features/leaderboard) is a `FutureProvider.autoDispose.family` keyed by (routineId, period, category), so late responses for an old selection cannot overwrite the current one; it refetches when the auth user changes or one of this run's plays reaches `saved`.

- Profile screen (WM-16): `/profile` (features/profile/profile_screen.dart) edits avatar (preset emoji in `profiles.avatar`), display name, goals, styles and level. Answers save through `profileProvider.save`; a rename calls `ProfileRepository.saveDisplayName` (the leaderboard name, `profiles.display_name`) and then `AuthRepository.updateDisplayName` (auth metadata, the name shown in the app). `AuthRepository.deleteAccount` calls the `delete_account` Edge Function (service role deletes the auth user; profile/sessions/results cascade) then drops the local session. Preset lists live in `profile_options.dart`.
- History (WM-17): `historyRepositoryProvider` (`HistoryRepository.fetch(limit)` -> `HistoryEntry`s newest first, each with its stored per-move results). Supabase reads the user's own `sessions` with embedded `move_results` (RLS-scoped); any malformed row fails the whole fetch. `OfflineHistoryRepository` (WM_OFFLINE) lists the signed-in player's local plays, which carry totals only. `/history` (features/history) opens a play in `SummaryScreen(fromHistory: true)` via `summaryFromHistory`, which needs the routine to still exist with the same number of moves; otherwise (and offline) it explains instead of opening. `frames` is not stored, so a move with score 0 and no worst joint shows as "not visible".

- Sets, reps and cardio (WM-39): a `Routine` has `category` (`dance`|`cardio`), `sets`, `restMs` and `met`; a `Move` may carry a `RepSpec` (reps per set + the joint and low/high angles the camera counts with, `shared/pose/rep_counter.dart`). `WorkoutSession` plays the moves `sets` times with rests between (time-based `advance`, frames ignored during rests); a counted move's set score is form score x min(1, reps/target), and each move is aggregated over its sets (mean score, summed reps), so `move_results` stays one row per move (history has no per-set breakdown). `routines.duration_ms` stays ONE set; the whole play is `durationMs*sets + restMs*(sets-1)` (`Routine.totalDurationMs`, also what `submit_session` checks). The payload gained top-level `sets` and per-result `reps` (old queued plays default to 1 set / 0 reps). Calories are never stored: `estimateCalories(met, durationMs)` assumes 70 kg and the UI says "estimate". The leaderboard takes an optional `category` (rpc `p_category`; offline resolves it through the content repository).

## Conventions
- Pose scoring logic is **pure Dart** (landmarks in → scores out) with no Flutter/camera imports, so it is unit-testable without a device. Test it.
- No secrets in git. Supabase URL/anon key come via `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
- Without those flags the app shows a startup error; pass `--dart-define=WM_OFFLINE=true` to run the local-only app (dev/test).
- Never upload camera frames. Only scores and per-move results are stored.
- Don't add a dependency without saying why in the PR.
- Follow `analysis_options.yaml` (flutter_lints). Prefer `const` widgets.
- The package is named `wiggle_move` (the folder is still `wiggle_move_app1`); imports use `package:wiggle_move/...`.

## Git
Branch from `main` → `feature/<short-name>` / `fix/<short-name>`; PR into `main`; one logical change per commit, imperative subject. Details in CONTRIBUTING.

## Status
First playable version, **not yet run on a device** (no Android SDK on the machine it was written on). Implemented: trainer list → routines → camera workout with ML Kit scoring → summary with per-move feedback → local leaderboard. Scoring + session logic is unit-tested; the camera/ML Kit path (`lib/features/workout/pose_service.dart`, `workout_screen.dart`) is untested until someone runs it on a phone.

Figma applied: theme/palette in `lib/app/theme.dart`, login/sign-up (`features/auth`), 4-step personalization (`features/profile`), navy-header home. Router redirects: signed out → `/login`; profile loading/failed → `/loading`; not onboarded → `/personalize`.

Auth (WM-20): email sign-up/login/logout/password-reset email via Supabase Auth behind `AuthRepository`; session restore is automatic. Under `WM_OFFLINE` an offline repository keeps a local name (any email/password works). **Not yet exercised against a real Supabase project.**

Profile (WM-21): onboarding answers are saved to the user's `profiles` row (only the UPDATE-granted columns), and `onboarded` is read from the server, so logging in on a new device skips onboarding. A release build refuses `WM_OFFLINE` (startup error). **Not yet run against a real Supabase project.**

Content (WM-22): trainers/routines/moves come from Supabase with an on-device cache for offline use. **Not yet run against a real Supabase project** (query shape and RLS read access untested live).

Sessions (WM-23): a finished workout is sent to the `submit_session` Edge Function; offline or server errors queue it on the device and it is resent (same nonce, so stored once) on app start, sign-in, resume or the next workout. **Not yet run against a real Supabase project / the deployed Edge Function.** `duration_ms` is the measured play time; the server's plausibility check uses `routines.duration_ms`, which must equal the sum of the moves' durations (seed self-check enforces it).

Leaderboard (WM-24): the screen shows server data (Weekly/All-time, Global or per routine, your row highlighted, pull to refresh). **Not yet run against a real Supabase project.**

Legacy data (WM-25): `migrateLegacyData` (`shared/legacy_data_migration.dart`, run in `main()`) removes the old device-only keys (local name/email/profile answers/leaderboard plays) once when running online and records `migrations_v`; under WM_OFFLINE those keys are live data, so nothing is touched.

Profile screen (WM-16): edit/sign out/delete account. **The `delete_account` Edge Function and the real Supabase profile/name updates have not been run.** `/loading` now has a Sign out button; the reset-password dialog shows errors inline.

History (WM-17): past plays list with per-move summaries. **Not run against a real Supabase project** (embedded `move_results` select and RLS untested live).

Sets/reps/cardio (WM-39): cardio routines with set counting, rep counting, rest periods, calorie estimate, and a category filter on the leaderboard. **Rep counting is untested on a device** (ML Kit frames are dropped while a detection is running, so fast moves such as jumping jacks may undercount on slow phones; rep thresholds in `trainer_data.dart`/`seed.sql` are uncalibrated). **The `20260101000500_cardio.sql` migration, the changed Edge Function and the pgTAP edits have never been run** (only `node --test` on `validate.ts`).

Known gaps: a play whose measured time exceeds 3x the routine (e.g. the app was backgrounded for a long time mid-workout) is rejected by the server and not stored; the queue's dropped-entry counter (`pending_submissions_dropped`) is stored but not reported anywhere yet; password-reset deep link (opening the app from the email to set a new password) is not handled — needs platform redirect URL config; Google sign-in is a placeholder (WM-26); under `WM_OFFLINE` the profile is per-device (not per offline account) and survives sign-out; the WM_OFFLINE leaderboard is per-device and keyed by display name; avatars show the initial only (the `avatar` value is not rendered yet); no trainer video; target angles in `trainer_data.dart` / `seed.sql` are uncalibrated estimates; logo is a placeholder icon + text (export the rabbit asset from Figma); font not matched to Figma; Figma has no workout/summary/leaderboard frames so those use the theme only.
