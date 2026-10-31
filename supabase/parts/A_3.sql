-- ============================================================
-- Еженедельный итог: топ-5 фиксируется и авторам приходит уведомление
-- ============================================================
create or replace function public.close_week() returns int
language plpgsql security definer set search_path = public as $$
declare
  ws date := (now() at time zone 'Europe/Moscow')::date;
  n int;
begin
  select count(*) into n from public.weekly_finalists where week_start = ws;
  if n > 0 then return n; end if;  -- сегодня уже подведено

  with top as (
    select b.id as boat_id, b.user_id, b.created_at,
           round(avg(r.score)::numeric, 2) as avg_score,
           count(*)::int as votes
    from public.boats b
    join public.ratings r on r.boat_id = b.id
    where b.status = 'approved' and b.created_at >= now() - interval '7 days'
    group by b.id, b.user_id, b.created_at
    having count(*) >= (select s.value from public.settings s where s.key = 'min_ratings')
    order by avg_score desc, votes desc, b.created_at asc
    limit 5
  ), ranked as (
    select row_number() over (order by avg_score desc, votes desc, created_at asc)::int as rnk, *
    from top
  ), ins as (
    insert into public.weekly_finalists (week_start, rank, boat_id, avg_score, votes)
    select ws, rnk, boat_id, avg_score, votes from ranked
    returning boat_id
  )
  insert into public.notifications (user_id, kind, body, link)
  select user_id, 'finalist',
         'Твоя лодка в топ-5 недели! Мы выбираем лучшую работу. Результат появится на странице «Лучшие работы».',
         'best.html'
  from ranked;

  select count(*) into n from public.weekly_finalists where week_start = ws;
  return n;
end $$;

-- Кнопка «Подвести итоги сейчас» в админке
create or replace function public.admin_close_week_now() returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  return public.close_week();
end $$;

-- close_week напрямую через сайт вызвать нельзя, её запускает только расписание
revoke all on function public.close_week() from public, anon, authenticated;

-- ============================================================
-- Хранилище фото
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('boats', 'boats', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists boats_files_read on storage.objects;
create policy boats_files_read on storage.objects for select
  using (bucket_id = 'boats');

drop policy if exists boats_files_insert on storage.objects;
create policy boats_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'boats' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists boats_files_delete on storage.objects;
create policy boats_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'boats' and (storage.foldername(name))[1] = auth.uid()::text);
-- I-Beam: раздел Build a Boat (схемы лодок и туториалы).
-- Запусти ПОСЛЕ 1_schema.sql: SQL Editor -> New query -> вставь -> Run.
-- Читать могут все, добавлять, менять и удалять могут только админы.
-- Фото загружаются в то же хранилище, что и лодки, а видео вставляются ссылкой с YouTube.

create table if not exists public.guides (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('scheme', 'tutorial')),
  title       text not null check (char_length(title) between 2 and 80),
  description text check (char_length(description) <= 1000),
  image_path  text,
  video_id    text check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  created_by  uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  check (image_path is not null or video_id is not null)
);
create index if not exists guides_kind_created_idx on public.guides (kind, created_at desc);

alter table public.guides enable row level security;

drop policy if exists guides_read on public.guides;
create policy guides_read on public.guides for select using (true);

drop policy if exists guides_write on public.guides;
create policy guides_write on public.guides for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
