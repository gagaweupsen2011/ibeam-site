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

-- ============================================================
-- Действия администратора (проверка роли внутри каждой функции)
-- ============================================================
create or replace function public.moderate_boat(p_boat uuid, p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid;
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  select b.user_id into v_user from public.boats b where b.id = p_boat;
  if v_user is null then raise exception 'Лодка не найдена'; end if;

  if p_action = 'approve' then
    update public.boats set status = 'approved', hide_reason = null where id = p_boat;
    delete from public.reports where boat_id = p_boat;
    update public.profiles set approved_count = approved_count + 1 where id = v_user;
    insert into public.notifications (user_id, kind, body, link)
      values (v_user, 'boat_approved', 'Твоя лодка одобрена и видна всем.', 'boats.html');
  elsif p_action = 'remove' then
    update public.boats set status = 'removed' where id = p_boat;
    insert into public.notifications (user_id, kind, body, link)
      values (v_user, 'boat_removed', 'Твоё фото удалено модератором. Проверь правила загрузки.', 'boats.html#rules');
  else
    raise exception 'Неизвестное действие';
  end if;
end $$;

create or replace function public.set_admin(p_user uuid, p_make boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'Только владелец может назначать админов'; end if;
  if exists (select 1 from public.profiles where id = p_user and is_owner) then
    raise exception 'Права владельца менять нельзя';
  end if;
  update public.profiles set is_admin = p_make where id = p_user;
  if p_make then
    insert into public.notifications (user_id, kind, body, link)
      values (p_user, 'admin_granted', 'Тебя назначили администратором. В меню появилась кнопка «Админ».', 'admin.html');
  end if;
end $$;

create or replace function public.ban_user(p_user uuid, p_ban boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  if exists (select 1 from public.profiles where id = p_user and (is_admin or is_owner)) then
    raise exception 'Админов блокировать нельзя';
  end if;
  update public.profiles set banned = p_ban where id = p_user;
end $$;

create or replace function public.set_setting(p_key text, p_value int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  if p_key not in ('report_threshold', 'min_ratings', 'new_user_review', 'daily_limit') then
    raise exception 'Неизвестная настройка';
  end if;
  update public.settings set value = p_value where key = p_key;
end $$;

-- Список пользователей (почты видит только владелец)
create or replace function public.admin_list_users(p_query text default '')
returns table (u_id uuid, u_nick text, u_email text, u_is_admin boolean,
               u_is_owner boolean, u_banned boolean, u_created_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare v_owner boolean := public.is_owner();
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  return query
    select p.id, p.nick,
           case when v_owner then u.email::text else null end,
           p.is_admin, p.is_owner, p.banned, p.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    where coalesce(p_query, '') = '' or p.nick ilike '%' || lower(p_query) || '%'
    order by p.created_at desc
    limit 50;
end $$;

-- Топ-5 последней недели с почтами авторов (только для админов)
create or replace function public.admin_finalists()
returns table (f_rank int, f_boat_id uuid, f_title text, f_image_path text, f_nick text,
               f_email text, f_avg numeric, f_votes int, f_status text, f_week date)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  return query
    select f.rank, f.boat_id, b.title, b.image_path, p.nick, u.email::text,
           f.avg_score, f.votes, f.contact_status, f.week_start
    from public.weekly_finalists f
    join public.boats b on b.id = f.boat_id
    join public.profiles p on p.id = b.user_id
    join auth.users u on u.id = b.user_id
    where f.week_start = (select max(w.week_start) from public.weekly_finalists w)
    order by f.rank;
end $$;

create or replace function public.admin_mark_finalist(p_boat uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare ws date;
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  if p_status not in ('waiting', 'no_reply', 'rewarded') then
    raise exception 'Неизвестный статус';
  end if;
  select max(w.week_start) into ws from public.weekly_finalists w;
  update public.weekly_finalists set contact_status = p_status
    where week_start = ws and boat_id = p_boat;
  if p_status = 'rewarded' then
    update public.featured set rewarded = true where boat_id = p_boat;
  end if;
end $$;

-- Выбор лучшей работы недели из топ-5 (повторный выбор заменяет прежний)
create or replace function public.choose_featured(p_boat uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  ws date;
  v_user uuid;
begin
  if not public.is_admin() then raise exception 'Нет доступа'; end if;
  select max(w.week_start) into ws from public.weekly_finalists w;
  if ws is null or not exists (
    select 1 from public.weekly_finalists w where w.week_start = ws and w.boat_id = p_boat
  ) then
    raise exception 'Этой лодки нет в последнем топ-5';
  end if;
  select b.user_id into v_user from public.boats b where b.id = p_boat;

  insert into public.featured (week_start, boat_id, chosen_by, chosen_at, reward_note, rewarded)
    values (ws, p_boat, auth.uid(), now(), nullif(trim(coalesce(p_note, '')), ''), false)
  on conflict (week_start) do update
    set boat_id = excluded.boat_id, chosen_by = excluded.chosen_by,
        chosen_at = now(), reward_note = excluded.reward_note, rewarded = false;

  insert into public.notifications (user_id, kind, body, link)
    values (v_user, 'featured',
            'Твоя лодка выбрана лучшей работой недели! Мы свяжемся с тобой по почте аккаунта.',
            'best.html');
end $$;

