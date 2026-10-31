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
