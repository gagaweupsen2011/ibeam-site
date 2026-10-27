/* I-Beam: общий код всех страниц (шапка, вход, уведомления, помощники). */
(function () {
  'use strict';

  var cfg = window.IBEAM_CONFIG || {};
  var notSet = !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY ||
    /YOUR_/.test(String(cfg.SUPABASE_URL) + String(cfg.SUPABASE_ANON_KEY));
  var sb = (!notSet && window.supabase) ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;

  var state = { sb: sb, user: null, profile: null };

  /* Создание элементов без innerHTML: тексты пользователей не выполняются как код */
  function h(tag, props) {
    var el = document.createElement(tag);
    var p = props || {};
    Object.keys(p).forEach(function (k) {
      var v = p[k];
      if (v === null || v === undefined || v === false) return;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k === 'value') el.value = v;
      else if (k.slice(0, 2) === 'on' && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
      else el.setAttribute(k, v === true ? '' : v);
    });
    for (var i = 2; i < arguments.length; i++) appendKid(el, arguments[i]);
    return el;
  }
  function appendKid(el, kid) {
    if (kid === null || kid === undefined || kid === false) return;
    if (Array.isArray(kid)) { kid.forEach(function (x) { appendKid(el, x); }); return; }
    el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }

  var LOGO = '<svg aria-hidden="true" viewBox="0 0 100 100" width="40" height="40">' +
    '<polygon points="50,6.7 93.3,50 50,93.3 6.7,50" fill="#454249"/>' +
    '<rect x="19.4" y="19.4" width="61.2" height="61.2" fill="#5E5B68"/>' +
    '<path d="M30.3 30.7h39.4v8.9H61.2v20.7h8.5v9H30.3v-9h8.5V39.6h-8.5z" fill="#454249"/></svg>';
  var LOGO_LIGHT = LOGO.replace('fill="#5E5B68"', 'fill="#A29DB0"');

  function logo(light) {
    var s = document.createElement('span');
    s.innerHTML = light ? LOGO_LIGHT : LOGO; /* статичная разметка, пользовательских данных нет */
    return s.firstChild;
  }

  /* Всплывающие сообщения */
  var toastWrap = null;
  function toast(msg) {
    if (!toastWrap) {
      toastWrap = h('div', { class: 'toast-wrap', role: 'status', 'aria-live': 'polite' });
      document.body.append(toastWrap);
    }
    var t = h('div', { class: 'toast', text: msg });
    toastWrap.append(t);
    setTimeout(function () { t.remove(); }, 4500);
  }

  function errText(e) {
    var m = (e && e.message) || String(e || '');
    if (/row-level security|permission denied/i.test(m)) return 'Нет прав на это действие.';
    if (/duplicate key|23505/.test(m)) return 'Это уже сделано.';
    if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return 'Нет связи с сервером. Проверь интернет.';
    return m || 'Что-то пошло не так.';
  }

  function fmtDate(s) {
    try { return new Date(s).toLocaleDateString('ru-RU', { day: 'numeric', month: 'long' }); }
    catch (e) { return ''; }
  }

  function imageUrl(path) {
    if (!sb || !path) return '';
    return sb.storage.from('boats').getPublicUrl(path).data.publicUrl;
  }

  function modal(title) {
    var rest = Array.prototype.slice.call(arguments, 1);
    var dlg = h('dialog', { 'aria-labelledby': 'dlg-title' });
    dlg.append(h('div', { class: 'dlg-head' },
      h('h2', { id: 'dlg-title', text: title }),
      h('button', { class: 'btn btn-ghost btn-sm', type: 'button', text: 'Закрыть', onclick: function () { dlg.close(); } })
    ));
    rest.forEach(function (x) { appendKid(dlg, x); });
    dlg.addEventListener('close', function () { dlg.remove(); });
    document.body.append(dlg);
    dlg.showModal();
    return dlg;
  }

  var NAV = [
    ['home', 'Главная', 'index.html'],
    ['boats', 'Лодки', 'boats.html'],
    ['best', 'Лучшие работы', 'best.html'],
    ['support', 'Поддержка', '#support']
  ];

  function renderShell(active) {
    var head = document.getElementById('site-header');
    var foot = document.getElementById('site-footer');
    if (head) {
      var actions = h('div', { class: 'head-actions' });
      if (state.user) {
        var nick = state.profile ? state.profile.nick : 'профиль';
        actions.append(
          h('button', { class: 'btn btn-ghost btn-sm', type: 'button', onclick: openProfile, text: '@' + nick })
        );
        var bell = h('button', { class: 'btn btn-ghost btn-sm', type: 'button', id: 'bell', onclick: openNotifications },
          'Уведомления ', h('span', { class: 'badge', id: 'bell-count', hidden: true, text: '0' }));
        actions.append(bell);
        if (state.profile && state.profile.is_admin) {
          actions.append(h('a', { class: 'btn btn-fill btn-sm', href: 'admin.html', text: 'Админ' }));
        }
        actions.append(h('button', { class: 'btn btn-ghost btn-sm', type: 'button', text: 'Выйти', onclick: signOut }));
      } else {
        actions.append(
          h('a', { class: 'btn btn-ghost', href: 'login.html#login', text: 'Вход' }),
          h('a', { class: 'btn btn-fill', href: 'login.html#register', text: 'Регистрация' })
        );
      }
      head.className = 'site-header';
      head.replaceChildren(
        h('div', { class: 'wrap' },
          h('a', { class: 'brand', href: 'index.html', 'aria-label': 'I-Beam, на главную' },
            h('span', { class: 'brand-mark' }, logo(false)),
            h('span', { class: 'brand-name', text: 'I-Beam' })),
          actions));
      var nav = h('nav', { class: 'site-nav', 'aria-label': 'Разделы' },
        h('div', { class: 'wrap' }, NAV.map(function (n) {
          return h('a', { class: 'nav-link', href: n[2], 'aria-current': n[0] === active ? 'page' : null, text: n[1] });
        })));
      head.after(nav);
      if (!sb) {
        nav.after(h('div', { class: 'setup' }, h('div', { class: 'wrap' },
          'Сайт ещё не подключён к базе данных. Открой файл js/config.js и вставь адрес и ключ Supabase, как написано в README.')));
      }
    }
    if (foot) {
      foot.className = 'site-footer';
      foot.id = 'support';
      foot.replaceChildren(h('div', { class: 'wrap' },
        h('span', { text: '© I-Beam' }),
        h('span', { text: cfg.SUPPORT_EMAIL ? 'Поддержка: ' + cfg.SUPPORT_EMAIL : 'Поддержка: почта пока не указана' })));
    }
  }

  async function signOut() {
    await sb.auth.signOut();
    location.href = 'index.html';
  }

  async function loadBell() {
    var r = await sb.from('notifications').select('id', { count: 'exact', head: true }).eq('read', false);
    var n = r.count || 0;
    var b = document.getElementById('bell-count');
    if (b) { b.textContent = String(n); b.hidden = n === 0; }
  }

  async function openNotifications() {
    var box = h('div', { class: 'stack' }, h('p', { class: 'muted', text: 'Загрузка…' }));
    modal('Уведомления', box);
    var r = await sb.from('notifications').select('id,body,link,read,created_at').order('created_at', { ascending: false }).limit(20);
    if (r.error) { box.replaceChildren(h('p', { text: errText(r.error) })); return; }
    if (!r.data.length) { box.replaceChildren(h('p', { text: 'Пока нет уведомлений.' })); return; }
    box.replaceChildren.apply(box, r.data.map(function (n) {
      return h('div', { class: 'comment' },
        h('b', { text: fmtDate(n.created_at) + (n.read ? '' : ' · новое') }),
        h('span', { text: n.body }),
        n.link ? h('a', { class: 'linkbtn', href: n.link, text: 'Открыть' }) : null);
    }));
    await sb.from('notifications').update({ read: true }).eq('read', false);
    loadBell();
  }

  function openProfile() {
    var msg = h('p', { class: 'note', role: 'status' });
    var input = h('input', { class: 'inp', id: 'nick-edit', type: 'text', maxlength: '20', autocomplete: 'off',
      value: state.profile ? state.profile.nick : '' });
    var form = h('form', { class: 'stack' },
      h('div', { class: 'field' },
        h('label', { class: 'lbl', for: 'nick-edit', text: 'Ник (латиница, цифры, _; 3-20 символов)' }), input),
      msg,
      h('button', { class: 'btn btn-fill', type: 'submit', text: 'Сохранить ник' }));
    form.addEventListener('submit', async function (e) {
      e.preventDefault();
      var r = await sb.rpc('set_nick', { p_nick: input.value });
      if (r.error) { msg.textContent = errText(r.error); return; }
      location.reload();
    });
    modal('Профиль', form);
  }

  async function init(active) {
    if (sb) {
      var s = await sb.auth.getSession();
      var session = s && s.data ? s.data.session : null;
      state.user = session ? session.user : null;
      if (state.user) {
        var p = await sb.from('profiles').select('*').eq('id', state.user.id).maybeSingle();
        state.profile = p.data || null;
      }
    }
    renderShell(active);
    if (sb && state.user) loadBell();
    return state;
  }

  window.IB = {
    sb: sb, state: state, h: h, logo: logo, toast: toast, errText: errText,
    fmtDate: fmtDate, imageUrl: imageUrl, modal: modal, init: init
  };
})();
