/* Вход и регистрация: почта + пароль, вход через Google, сброс пароля. */
(async function () {
  'use strict';
  var IB = window.IB, sb = IB.sb, errText = IB.errText;
  var $ = function (id) { return document.getElementById(id); };

  var isRecovery = /type=recovery/.test(location.hash);
  var st = await IB.init('login');

  var params = new URLSearchParams(location.search);
  var next = params.get('next') || 'index.html';
  if (!/^[a-z0-9_-]+\.html$/i.test(next)) next = 'index.html'; /* только страницы этого сайта */

  if (!sb) { $('auth-form').hidden = true; $('alt').hidden = true; return; }
  if (st.user && !isRecovery) { location.replace(next); return; }

  var mode = location.hash === '#login' ? 'login' : 'register';

  function show(el, text, ok) {
    el.hidden = !text;
    el.textContent = text || '';
    el.className = ok ? 'err pill-lav' : 'err';
    el.style.background = ok ? 'var(--lav)' : '';
  }

  function setMode(m) {
    mode = m;
    var reg = m === 'register';
    $('tab-register').setAttribute('aria-selected', reg ? 'true' : 'false');
    $('tab-login').setAttribute('aria-selected', reg ? 'false' : 'true');
    $('auth-title').textContent = reg ? 'Создать аккаунт' : 'С возвращением';
    $('f-nick').hidden = !reg;
    $('submit').textContent = reg ? 'Зарегистрироваться' : 'Войти';
    $('pass').autocomplete = reg ? 'new-password' : 'current-password';
    $('forgot').hidden = reg;
    show($('auth-msg'), '');
  }
  setMode(mode);
  $('tab-register').addEventListener('click', function () { setMode('register'); });
  $('tab-login').addEventListener('click', function () { setMode('login'); });

  $('show-pass').addEventListener('click', function () {
    var p = $('pass');
    var visible = p.type === 'text';
    p.type = visible ? 'password' : 'text';
    this.textContent = visible ? 'Показать' : 'Скрыть';
  });

  function authError(e) {
    var m = (e && e.message) || '';
    if (/Invalid login credentials/i.test(m)) return 'Неверная почта или пароль.';
    if (/Email not confirmed/i.test(m)) return 'Почта ещё не подтверждена. Открой письмо от нас и нажми на ссылку.';
    if (/already registered|already been registered/i.test(m)) return 'Эта почта уже зарегистрирована. Попробуй войти.';
    if (/rate limit|too many/i.test(m)) return 'Слишком много попыток. Подожди пару минут.';
    if (/Password should be/i.test(m)) return 'Пароль слишком простой. Нужно минимум 8 символов.';
    return errText(e);
  }

  $('auth-form').addEventListener('submit', async function (e) {
    e.preventDefault();
    var msg = $('auth-msg');
    show(msg, '');
    var email = $('email').value.trim();
    var pass = $('pass').value;
    if (!email || !/^\S+@\S+\.\S+$/.test(email)) { show(msg, 'Введи почту, например имя@gmail.com.'); return; }
    if (pass.length < 8) { show(msg, 'Пароль: минимум 8 символов.'); return; }

    var btn = $('submit');
    btn.disabled = true;

    if (mode === 'register') {
      var nick = $('nick').value.trim().toLowerCase();
      if (!/^[a-z0-9_]{3,20}$/.test(nick)) {
        show(msg, 'Ник: от 3 до 20 символов, только латиница, цифры и _.');
        btn.disabled = false; return;
      }
      var av = await sb.rpc('nick_available', { p_nick: nick });
      if (av.data === false) { show(msg, 'Этот ник занят. Выбери другой.'); btn.disabled = false; return; }

      var r = await sb.auth.signUp({
        email: email, password: pass,
        options: { data: { nick: nick }, emailRedirectTo: new URL('index.html', location.href).href }
      });
      btn.disabled = false;
      if (r.error) { show(msg, authError(r.error)); return; }
      if (r.data.user && r.data.user.identities && r.data.user.identities.length === 0) {
        show(msg, 'Эта почта уже зарегистрирована. Попробуй войти.'); return;
      }
      if (r.data.session) { location.replace(next); return; }
      show(msg, 'Мы отправили письмо на ' + email + '. Открой его, подтверди почту и потом войди.', true);
    } else {
      var l = await sb.auth.signInWithPassword({ email: email, password: pass });
      btn.disabled = false;
      if (l.error) { show(msg, authError(l.error)); return; }
      location.replace(next);
    }
  });

  $('google').addEventListener('click', async function () {
    var r = await sb.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: new URL(next, location.href).href }
    });
    if (r.error) show($('auth-msg'), 'Вход через Google ещё не настроен: ' + authError(r.error));
  });

  $('forgot').addEventListener('click', async function () {
    var email = $('email').value.trim();
    var msg = $('auth-msg');
    if (!email) { show(msg, 'Сначала впиши свою почту выше.'); return; }
    var r = await sb.auth.resetPasswordForEmail(email, { redirectTo: new URL('login.html', location.href).href });
    if (r.error) show(msg, authError(r.error));
    else show(msg, 'Если такая почта есть у нас, мы отправили ссылку для смены пароля.', true);
  });

  /* Возврат по ссылке «сменить пароль» из письма */
  function showReset() {
    $('auth-form').hidden = true; $('alt').hidden = true; $('tabs').hidden = true;
    $('auth-title').textContent = 'Новый пароль';
    $('reset-form').hidden = false;
  }
  if (isRecovery) showReset();
  sb.auth.onAuthStateChange(function (ev) { if (ev === 'PASSWORD_RECOVERY') showReset(); });

  $('reset-form').addEventListener('submit', async function (e) {
    e.preventDefault();
    var p = $('newpass').value;
    var msg = $('reset-msg');
    if (p.length < 8) { show(msg, 'Пароль: минимум 8 символов.'); return; }
    var r = await sb.auth.updateUser({ password: p });
    if (r.error) { show(msg, authError(r.error)); return; }
    show(msg, 'Пароль изменён. Переходим на сайт…', true);
    setTimeout(function () { location.replace('index.html'); }, 1200);
  });
})();
