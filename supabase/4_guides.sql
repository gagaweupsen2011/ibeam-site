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
