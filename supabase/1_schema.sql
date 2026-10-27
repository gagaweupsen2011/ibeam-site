-- I-Beam: схема базы данных для Supabase.
-- Запусти целиком один раз: Supabase -> SQL Editor -> New query -> вставь -> Run.

-- ============================================================
-- Профили
-- ============================================================
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  nick           text not null unique
                 check (nick ~ '^[a-z0-9_]{3,20}$'),
  is_admin       boolean not null default false,
  is_owner       boolean not null default false,
  banned         boolean not null default false,
  approved_count int not null default 0,
  created_at     timestamptz not null default now()
);

-- Настройки, которые админ меняет в панели
create table if not exists public.settings (
  key   text primary key,
  value int not null check (value between 1 and 100)
);
insert into public.settings (key, value) values
  ('report_threshold', 3),   -- жалоб до скрытия фото
  ('min_ratings',      3),   -- минимум оценок, чтобы попасть в топ-5
  ('new_user_review',  3),   -- сколько первых фото нового участника проверяет админ
  ('daily_limit',      5)    -- максимум фото от одного человека в сутки
on conflict (key) do nothing;

-- ============================================================
-- Вспомогательные функции для прав
-- ============================================================
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false)
$$;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.is_owner from public.profiles p where p.id = auth.uid()), false)
$$;

create or replace function public.is_banned() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.banned from public.profiles p where p.id = auth.uid()), false)
$$;

-- ============================================================
-- Профиль создаётся автоматически при регистрации
-- ============================================================
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base text;
  cand text;
  tries int := 0;
begin
  base := regexp_replace(lower(coalesce(new.raw_user_meta_data->>'nick', '')), '[^a-z0-9_]', '', 'g');
  base := left(base, 20);
  if length(base) < 3 then
    -- например вход через Google: ник нейтральный, чтобы не раскрывать почту
    base := 'user' || floor(random() * 900000 + 100000)::int::text;
  end if;
  cand := base;
  while exists (select 1 from public.profiles where nick = cand) and tries < 30 loop
    tries := tries + 1;
    cand := left(base, 14) || floor(random() * 9000 + 1000)::int::text;
  end loop;
  insert into public.profiles (id, nick) values (new.id, cand);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.nick_available(p_nick text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where nick = lower(trim(p_nick)))
$$;

create or replace function public.set_nick(p_nick text) returns void
language plpgsql security definer set search_path = public as $$
declare v text := lower(trim(p_nick));
begin
  if auth.uid() is null then raise exception 'Нужно войти в аккаунт'; end if;
  if v !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'Ник: от 3 до 20 символов, латиница, цифры и _';
  end if;
  if exists (select 1 from public.profiles where nick = v and id <> auth.uid()) then
    raise exception 'Этот ник занят';
  end if;
  update public.profiles set nick = v where id = auth.uid();
end $$;

-- ============================================================
-- Лодки, оценки, комментарии, жалобы
-- ============================================================
create table if not exists public.boats (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  title       text not null check (char_length(title) between 2 and 60),
  image_path  text not null,
  status      text not null default 'pending'
              check (status in ('pending', 'approved', 'hidden', 'removed')),
  hide_reason text,
  created_at  timestamptz not null default now()
);
create index if not exists boats_status_created_idx on public.boats (status, created_at desc);

create table if not exists public.ratings (
  boat_id    uuid not null references public.boats(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  score      int  not null check (score between 1 and 10),
  created_at timestamptz not null default now(),
  primary key (boat_id, user_id)
);

create table if not exists public.comments (
  id         uuid primary key default gen_random_uuid(),
  boat_id    uuid not null references public.boats(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists comments_boat_idx on public.comments (boat_id, created_at);

create table if not exists public.reports (
  boat_id    uuid not null references public.boats(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (boat_id, user_id)
);

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,
  body       text not null,
  link       text,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

-- Топ-5, зафиксированный в воскресенье в 06:00 МСК
create table if not exists public.weekly_finalists (
  week_start     date not null,
  rank           int  not null,
  boat_id        uuid not null references public.boats(id) on delete cascade,
  avg_score      numeric(4,2) not null,
  votes          int not null,
  contact_status text not null default 'waiting'
                 check (contact_status in ('waiting', 'no_reply', 'rewarded')),
  primary key (week_start, rank),
  unique (week_start, boat_id)
);

-- Лучшая работа недели, выбранная админом
create table if not exists public.featured (
  id          uuid primary key default gen_random_uuid(),
  week_start  date not null unique,
  boat_id     uuid not null references public.boats(id) on delete cascade,
  chosen_by   uuid references public.profiles(id) on delete set null,
  chosen_at   timestamptz not null default now(),
  reward_note text,
  rewarded    boolean not null default false
);

-- Лодки со средней оценкой (учитывает права того, кто читает)
create or replace view public.boat_stats with (security_invoker = true) as
select b.id, b.user_id, b.title, b.image_path, b.status, b.created_at,
       p.nick,
       coalesce(round(avg(r.score)::numeric, 1), 0) as avg_score,
       count(r.score)::int as votes
from public.boats b
join public.profiles p on p.id = b.user_id
left join public.ratings r on r.boat_id = b.id
group by b.id, p.nick;

grant select on public.boat_stats to anon, authenticated;

-- ============================================================
-- Триггеры
-- ============================================================
-- Новое фото: статус зависит от доверия к автору, плюс лимит в сутки
create or replace function public.boats_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  lim int;
  need int;
  cnt int;
begin
  select * into p from public.profiles where id = new.user_id;
  if p.banned then raise exception 'Аккаунт заблокирован'; end if;
  select s.value into lim from public.settings s where s.key = 'daily_limit';
  select count(*) into cnt from public.boats b
    where b.user_id = new.user_id and b.created_at > now() - interval '24 hours';
  if cnt >= lim then
    raise exception 'Лимит: не больше % фото в сутки', lim;
  end if;
  select s.value into need from public.settings s where s.key = 'new_user_review';
  if p.is_admin or p.approved_count >= need then
    new.status := 'approved';
  else
    new.status := 'pending';
  end if;
  new.hide_reason := null;
  return new;
end $$;

drop trigger if exists boats_before_insert on public.boats;
create trigger boats_before_insert
  before insert on public.boats
  for each row execute function public.boats_before_insert();

-- Достаточно жалоб: фото скрывается до проверки
create or replace function public.reports_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  thr int;
  cnt int;
begin
  select s.value into thr from public.settings s where s.key = 'report_threshold';
  select count(*) into cnt from public.reports r where r.boat_id = new.boat_id;
  if cnt >= thr then
    update public.boats set status = 'hidden', hide_reason = 'Жалобы'
      where id = new.boat_id and status = 'approved';
  end if;
  return new;
end $$;

drop trigger if exists reports_after_insert on public.reports;
create trigger reports_after_insert
  after insert on public.reports
  for each row execute function public.reports_after_insert();

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
