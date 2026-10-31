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

