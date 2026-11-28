-- WM-18: trainer photos.
--
-- trainers.photo_path is an object path inside the public `trainer-photos`
-- Storage bucket (null = no photo; the app shows the trainer's initial).
-- Same access model as the routine-videos bucket (WM-11): anyone can read,
-- only the service role (admins / upload scripts) can write; there are
-- deliberately no insert/update/delete policies on storage.objects for it.
-- Clients already have `select` on public.trainers (WM-08), which covers the
-- new column.

alter table public.trainers
  add column photo_path text
    check (photo_path is null or char_length(photo_path) between 1 and 200);

comment on column public.trainers.photo_path is
  'Object path in the trainer-photos bucket; the app builds the public URL.';

insert into storage.buckets (id, name, public)
values ('trainer-photos', 'trainer-photos', true)
on conflict (id) do nothing;

create policy trainer_photos_public_read
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'trainer-photos');
