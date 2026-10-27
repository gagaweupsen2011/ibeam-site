-- I-Beam: расписание итогов недели.
-- Запускай ПОСЛЕ 1_schema.sql.
-- Каждое воскресенье в 03:00 UTC = 06:00 по Москве сайт фиксирует топ-5
-- и отправляет авторам уведомление «Выбираем лучшую работу».
--
-- Если будет ошибка про pg_cron: Supabase -> Database -> Extensions -> включи pg_cron
-- и запусти этот файл ещё раз.

create extension if not exists pg_cron;

select cron.schedule(
  'ibeam-close-week',
  '0 3 * * 0',
  $$select public.close_week();$$
);
