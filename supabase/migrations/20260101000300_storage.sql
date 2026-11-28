-- WM-11: Storage bucket for trainer routine videos.
--
-- Public read (anyone, signed in or not, can stream a routine video);
-- writes only by the service role (admins / upload scripts), which bypasses
-- RLS. There are deliberately NO insert/update/delete policies on
-- storage.objects for this bucket, so anon/authenticated cannot upload,
-- overwrite or delete videos. routines.video_path holds the object path
-- inside this bucket.

insert into storage.buckets (id, name, public)
values ('routine-videos', 'routine-videos', true)
on conflict (id) do nothing;

-- Read access through the Storage API (download/list). Public URLs of a
-- public bucket work without a policy; this covers authenticated API reads.
create policy routine_videos_public_read
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'routine-videos');
