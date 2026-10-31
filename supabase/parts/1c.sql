-- ============================================================
-- Права доступа (RLS)
-- ============================================================
alter table public.profiles         enable row level security;
alter table public.settings         enable row level security;
alter table public.boats            enable row level security;
alter table public.ratings          enable row level security;
alter table public.comments         enable row level security;
alter table public.reports          enable row level security;
alter table public.notifications    enable row level security;
alter table public.weekly_finalists enable row level security;
alter table public.featured         enable row level security;

-- profiles: читать могут все, менять напрямую никто (только через функции)
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using (true);

drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings for select using (true);

-- boats
drop policy if exists boats_read on public.boats;
create policy boats_read on public.boats for select
  using (status = 'approved' or user_id = auth.uid() or public.is_admin());

drop policy if exists boats_insert on public.boats;
create policy boats_insert on public.boats for insert to authenticated
  with check (user_id = auth.uid() and not public.is_banned());

drop policy if exists boats_delete on public.boats;
create policy boats_delete on public.boats for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ratings: нельзя оценивать свою лодку, только одобренные, только не заблокированным
drop policy if exists ratings_read on public.ratings;
create policy ratings_read on public.ratings for select using (true);

drop policy if exists ratings_insert on public.ratings;
create policy ratings_insert on public.ratings for insert to authenticated
  with check (
    user_id = auth.uid() and not public.is_banned()
    and exists (select 1 from public.boats b
                where b.id = boat_id and b.status = 'approved' and b.user_id <> auth.uid())
  );

drop policy if exists ratings_update on public.ratings;
create policy ratings_update on public.ratings for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid() and not public.is_banned()
    and exists (select 1 from public.boats b
                where b.id = boat_id and b.status = 'approved' and b.user_id <> auth.uid())
  );

-- comments
drop policy if exists comments_read on public.comments;
create policy comments_read on public.comments for select
  using (exists (select 1 from public.boats b where b.id = boat_id));

drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments for insert to authenticated
  with check (
    user_id = auth.uid() and not public.is_banned()
    and exists (select 1 from public.boats b where b.id = boat_id and b.status = 'approved')
  );

drop policy if exists comments_delete on public.comments;
create policy comments_delete on public.comments for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- reports: пожаловаться можно один раз и не на свою лодку; читают только админы
drop policy if exists reports_read on public.reports;
create policy reports_read on public.reports for select to authenticated
  using (public.is_admin());

drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports for insert to authenticated
  with check (
    user_id = auth.uid() and not public.is_banned()
    and exists (select 1 from public.boats b
                where b.id = boat_id and b.status = 'approved' and b.user_id <> auth.uid())
  );

-- notifications: каждый видит и отмечает прочитанными только свои
drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications for select to authenticated
  using (user_id = auth.uid());

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- weekly_finalists: только админы (почты победителей читаются отдельной функцией)
drop policy if exists finalists_read on public.weekly_finalists;
create policy finalists_read on public.weekly_finalists for select to authenticated
  using (public.is_admin());

-- featured: читают все (страница «Лучшие работы»)
drop policy if exists featured_read on public.featured;
create policy featured_read on public.featured for select using (true);

