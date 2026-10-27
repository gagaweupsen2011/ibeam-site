-- I-Beam: выдать себе права владельца.
-- 1) Сначала зарегистрируйся на сайте (эту же почту впиши ниже).
-- 2) Замени ТВОЯ_ПОЧТА@gmail.com на свою почту.
-- 3) Запусти в SQL Editor. Делается один раз.
--
-- Владелец видит панель «Админ» и может назначать других админов.
-- Назначить владельца только отсюда: с сайта этого сделать нельзя, и это защита от взлома.

update public.profiles
set is_owner = true, is_admin = true
where id = (select id from auth.users where email = 'ТВОЯ_ПОЧТА@gmail.com');

-- Проверка: должна вернуться одна строка с is_owner = true
select nick, is_owner, is_admin from public.profiles where is_owner;
