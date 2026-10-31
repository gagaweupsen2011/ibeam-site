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

