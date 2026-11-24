# Wiggle Move — Project Document

## 1. Vision
Wiggle Move lets users pick a trainer, follow their dance/workout, and get real-time AI feedback on whether their movement is correct. Users compete on a leaderboard and review a per-session summary showing exactly which moves they got wrong.

Design: Figma — https://www.figma.com/design/MkWpgib6r9BDayHSRuZMaS/ToBeIT70?node-id=0-1 (source of truth for UI; confirm screens with the designer before building each feature).

## 2. Core features
| # | Feature | Summary |
|---|---------|---------|
| 1 | Trainer selection | Browse trainers, each with routines (video + reference choreography). |
| 2 | Live workout | Camera runs while the routine video plays; pose is scored continuously. |
| 3 | Move scoring | AI compares the user's pose to the trainer's reference per time window → correct / partial / wrong. |
| 4 | Leaderboard | Rank users by score, per routine and global (weekly/all-time). |
| 5 | Session summary | After each session: total score, accuracy over time, list of missed moves with the body part that was off. |
| 6 | Accounts | Sign up / login, profile, history. |

## 3. Architecture
```
Camera frames ──► ML Kit Pose (on-device) ──► 33 landmarks
                                                │
Reference choreography (per routine) ──────────►├─► Scoring (pure Dart) ──► per-move result
                                                                              │
                                              Session summary ◄───────────────┤
                                              Supabase (score, results) ◄─────┘ ──► Leaderboard
```
- **Client:** Flutter, feature-first (`lib/features/*`), Riverpod state, go_router.
- **Pose detection:** `google_mlkit_pose_detection`, on-device. Privacy: video never leaves the phone.
- **Scoring (proposed):** compute joint angles (elbows, shoulders, hips, knees) from landmarks; compare to the reference angles at the matching timestamp; tolerance band → score 0–100 per move; flag the joints whose angle deviation is largest (this drives the "what went wrong" summary). Reference poses are produced offline by running the trainer video through the same detector and stored with the routine.
- **Backend:** Supabase — Postgres + Auth + Row Level Security. Tables (initial sketch): `profiles`, `trainers`, `routines`, `sessions`, `move_results`, plus a `leaderboard` view.
- **Anti-cheat (later):** sanity-check submitted scores server-side (bounds, rate) — the client is not trusted.

## 4. Decisions
- **Flutter** — single codebase for Android/iOS, and the camera + ML Kit plugins are mature.
- **On-device ML Kit** over server inference — low latency, no video upload, no GPU cost. Trade-off: mobile only, and ML Kit accuracy is limited for fast or occluded movement.
- **Supabase** over custom backend — auth, DB and RLS out of the box for a small team. Revisit if scoring must move server-side.
- Riverpod + go_router — standard, testable, minimal boilerplate.

These are defaults picked at project start; change them via PR that updates this section.

## 5. Roadmap
1. **Foundation (done):** Flutter scaffold, deps, camera permissions, CI-ready analyze/test.
2. **Pose spike:** camera preview + skeleton overlay on a real device; measure FPS/accuracy.
3. **Scoring engine:** angle math, reference format, unit tests with recorded landmark fixtures.
4. **Trainer + routine screens** from Figma, seeded routine data.
5. **Workout flow:** video playback synced with scoring.
6. **Summary screen.**
7. **Supabase:** auth, schema, save sessions, leaderboard.
8. **Polish:** onboarding, error/permission states, performance, store release.

## 6. Setup for new teammates
1. Install Flutter 3.47+ and Android Studio (Android SDK) and/or Xcode (macOS, iOS).
2. `git clone <repo>` → `cd wiggle_move_app1` → `flutter pub get`
3. `flutter doctor` should be clean for your target platform.
4. Run on a **physical device** (`flutter run`) — emulators lack a usable camera for pose work.
5. Get the Supabase URL/anon key from the team (not in git) and pass via `--dart-define`.

## 7. Open questions
- Trainer content: who records the routines, and how are reference poses authored/validated?
- Scoring fairness across body sizes and camera distance (normalize landmarks by torso length).
- Leaderboard scope: global only, or friends/groups?
- Minimum supported devices (ML Kit performance floor).
