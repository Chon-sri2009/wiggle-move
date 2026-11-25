# Contributing

## Branching
- `main` is always buildable; no direct pushes once a remote exists.
- Branch names: `feature/<name>`, `fix/<name>`, `docs/<name>`.
- Open a PR into `main`; at least one teammate reviews.

## Commits
- Imperative, concise subject (`Add trainer list screen`), body explains why when not obvious.
- One logical change per commit. Don't commit secrets, build output, or `local.properties`.

## Before opening a PR
```powershell
dart format lib test
flutter analyze
flutter test
```
All three must be clean. Add/adjust tests for logic changes (scoring especially). CI (`.github/workflows/ci.yml`) runs the same checks on every PR and push to `main`.

## PR description
What changed, why, how you tested (device model if camera/pose related), screenshots for UI.

## Secrets
Never commit Supabase keys. Use `--dart-define` locally; share keys via the team's password manager.
