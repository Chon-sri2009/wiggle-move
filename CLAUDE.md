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
- `lib/features/<feature>/` — one folder per feature: `home`, `trainers` (trainer screen + `trainersProvider`), `scoring` (scorer), `workout` (session, ML Kit service, camera screen), `summary`, `leaderboard` (local store). Keep UI, providers and data code for a feature together.
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
- Content (WM-22): `contentRepositoryProvider` (`ContentRepository.fetchTrainers`; models + JSON codec in `shared/backend/content_models.dart`). Supabase reads `trainers` with embedded `routines(*, moves(*))` in one request and sorts by `sort_order`/`idx` client-side; any malformed row fails the whole fetch (no partial content). `shared/backend/trainer_data.dart` is the built-in content: served only by `OfflineContentRepository` (WM_OFFLINE) and used as a test fixture; app code must not import it. `ContentCache` keeps the last good fetch in SharedPreferences per install (public content, survives sign-out; a corrupt cache is discarded). `trainersProvider` (features/trainers) is stale-while-revalidate: cached content at once, then the fetch replaces it; a failed fetch keeps the cache and sets `isStale` (Home shows an offline note, pull to refresh); no cache + failure is an error with Retry. Routes look up content through `trainerProvider(id)`/`routineProvider(id)` inside `ContentGate` (loading / error+Retry / not found).

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

Known gaps: password-reset deep link (opening the app from the email to set a new password) is not handled — needs platform redirect URL config; Google sign-in is a placeholder (WM-26); under `WM_OFFLINE` the profile is per-device (not per offline account) and survives sign-out; leaderboard is per-device and keyed by display name (WM-24); no trainer video; target angles in `trainer_data.dart` / `seed.sql` are uncalibrated estimates; logo is a placeholder icon + text (export the rabbit asset from Figma); font not matched to Figma; Figma has no workout/summary/leaderboard frames so those use the theme only.
