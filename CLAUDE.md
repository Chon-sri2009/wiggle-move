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
- `lib/features/<feature>/` — one folder per feature: `home`, `trainers` (models + seed data), `scoring` (pure angle math + scorer), `workout` (session, ML Kit service, camera screen), `summary`, `leaderboard` (local store). Keep UI, providers and data code for a feature together.
- Code shared by 2+ features goes in `lib/shared/` (create when first needed).
- Tests mirror `lib/` under `test/`.

## Conventions
- Pose scoring logic is **pure Dart** (landmarks in → scores out) with no Flutter/camera imports, so it is unit-testable without a device. Test it.
- No secrets in git. Supabase URL/anon key come via `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
- Never upload camera frames. Only scores and per-move results are stored.
- Don't add a dependency without saying why in the PR.
- Follow `analysis_options.yaml` (flutter_lints). Prefer `const` widgets.
- The package is still named `wiggle_move_app1` (from `flutter create`); imports use `package:wiggle_move_app1/...`.

## Git
Branch from `main` → `feature/<short-name>` / `fix/<short-name>`; PR into `main`; one logical change per commit, imperative subject. Details in CONTRIBUTING.

## Status
First playable version, **not yet run on a device** (no Android SDK on the machine it was written on). Implemented: trainer list → routines → camera workout with ML Kit scoring → summary with per-move feedback → local leaderboard. Scoring + session logic is unit-tested; the camera/ML Kit path (`lib/features/workout/pose_service.dart`, `workout_screen.dart`) is untested until someone runs it on a phone.

Figma applied: theme/palette in `lib/app/theme.dart`, login/sign-up (`features/auth`), 4-step personalization (`features/profile`), navy-header home. Router redirects: signed out → `/login`; not onboarded → `/personalize`.

Known gaps: **login/sign-up are UI only** (they just store a display name on the device; no real accounts until Supabase is wired); leaderboard is per-device; no trainer video; target angles in `trainer_data.dart` are uncalibrated estimates; logo is a placeholder icon + text (export the rabbit asset from Figma); font not matched to Figma; Figma has no workout/summary/leaderboard frames so those use the theme only.
