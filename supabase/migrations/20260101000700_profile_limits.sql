-- Audit fix: bound the free-text profile columns.
--
-- Clients may update their own profile row (WM-08), and the leaderboard
-- returns `avatar` to every viewer. Without a limit one account could store a
-- multi-megabyte avatar and slow every leaderboard screen. The app only offers
-- short emoji avatars and a handful of goals/styles.
--
-- `not valid` is not used: existing rows are expected to satisfy the limits,
-- and the migration should fail loudly if they do not.

alter table public.profiles
  add constraint profiles_avatar_len
    check (avatar is null or char_length(avatar) <= 16),
  add constraint profiles_goals_len
    check (cardinality(goals) <= 10),
  add constraint profiles_styles_len
    check (cardinality(styles) <= 10);
