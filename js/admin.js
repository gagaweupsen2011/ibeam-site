/* Панель администратора: лучшая работа недели, модерация, пользователи и админы, настройки.
   Все данные защищены правилами базы: даже если открыть эту страницу без прав, сервер ничего не отдаст. */
(async function () {
  'use strict';
  var IB = window.IB, sb = IB.sb, h = IB.h, toast = IB.toast, errText = IB.errText;
  var st = await IB.init('admin');
  var root = document.getElementById('admin-root');
  if (!sb) { root.replaceChildren(); return; }

  if (!st.user) { location.replace('login.html?next=admin.html#login'); return; }
  if (!st.profile || !st.profile.is_admin) {
    root.replaceChildren(h('section', { class: 'card pad', style: 'max-width:560px' },
      h('h1', { class: 'card-title', style: 'font-size:28px', text: 'Нет доступа' }),
      h('p', { text: 'Эта страница только для администраторов.' }),
      h('div', { class: 'row' }, h('a', { class: 'btn btn-fill', href: 'index.html', text: 'На главную' }))));
    return;
  }
  var isOwner = !!st.profile.is_owner;

  /* ---------- Лучшая работа недели ---------- */
  var finBox = h('div', { class: 'admin-grid' });
  var finStatus = h('div', { class: 'card toggle-row', style: 'flex-direction:row' });
  var noteInput = h('input', { class: 'inp', id: 'reward-note', type: 'text', maxlength: '120', placeholder: 'Например: роль в Discord или подарок', style: 'max-width:420px' });
  var current = null;

  async function loadFinal() {
    var res = await Promise.all([
      sb.rpc('admin_finalists'),
      sb.from('featured').select('*').order('chosen_at', { ascending: false }).limit(1)
    ]);
    if (res[0].error) { finBox.replaceChildren(h('p', { class: 'note', text: errText(res[0].error) })); return; }
    current = res[1].data && res[1].data[0] ? res[1].data[0] : null;
    var list = res[0].data || [];
    var week = list.length ? list[0].f_week : null;
    var chosenNow = current && week && current.week_start === week ? current : null;

    var text = 'Топ-5 ещё не подведён. Он фиксируется в воскресенье в 06:00 по Москве.';
    if (list.length && !chosenNow) text = 'Ждём твоего выбора: выбери одну из пяти работ.';
    if (list.length && chosenNow) text = 'Выбрана лучшая работа недели' + (chosenNow.rewarded ? '. Награда выдана.' : '. Рамка уже на сайте.');
    finStatus.replaceChildren(h('span', { style: 'font-size:17px;font-weight:600', text: text }));

    if (!list.length) {
      finBox.replaceChildren(h('p', { class: 'note', style: 'grid-column:1/-1', text: 'Пока нет лодок с достаточным числом оценок за неделю.' }));
      return;
    }
    finBox.replaceChildren.apply(finBox, list.map(function (f) {
      var chosen = chosenNow && chosenNow.boat_id === f.f_boat_id;
      var pillCls = 'pill pill-line', pillTxt = 'Финалист';
      if (chosen) { pillCls = 'pill pill-light'; pillTxt = chosenNow.rewarded ? 'Награждён' : 'Лучшая работа'; }
      else if (f.f_status === 'no_reply') { pillCls = 'pill pill-strike'; pillTxt = 'Не ответил'; }
      return h('article', { class: 'card' + (chosen ? ' feat' : '') },
        h('div', { class: 'row', style: 'justify-content:space-between' },
          h('span', { class: 'rank', text: String(f.f_rank) }),
          h('span', { class: pillCls, text: pillTxt })),
        h('div', { class: 'cardimg' }, h('img', { src: IB.imageUrl(f.f_image_path), alt: 'Лодка «' + f.f_title + '»', loading: 'lazy' })),
        h('div', null,
          h('div', { class: 'card-title', text: f.f_title }),
          h('div', { class: 'muted', text: '@' + f.f_nick }),
          h('div', { class: 'muted', text: 'Оценка ' + f.f_avg + ' / 10, оценок: ' + f.f_votes })),
        h('div', { class: 'stack', style: 'gap:6px' },
          h('span', { class: 'muted', text: 'Почта для связи:' }),
          h('span', { style: 'overflow-wrap:anywhere;font-weight:600;user-select:all', text: f.f_email || '' }),
          h('button', { class: 'btn btn-ghost btn-sm', type: 'button', text: 'Скопировать', onclick: function () { copy(f.f_email); } })),
        chosen
          ? h('div', { class: 'stack', style: 'gap:8px' },
              chosenNow.rewarded ? null : h('button', { class: 'btn btn-fill', type: 'button', text: 'Награда выдана', onclick: function () { markFinalist(f.f_boat_id, 'rewarded'); } }),
              chosenNow.rewarded ? null : h('button', { class: 'btn btn-ghost', type: 'button', text: 'Не ответил, выбрать другую', onclick: function () { markFinalist(f.f_boat_id, 'no_reply'); } }))
          : h('button', { class: 'btn btn-fill', type: 'button', text: 'Выбрать лучшей', onclick: function () { choose(f.f_boat_id); } }));
    }));
  }

  function copy(text) {
    if (!text) return;
    var done = function () { toast('Почта скопирована.'); };
    var fail = function () { toast('Не удалось скопировать. Выдели почту и скопируй вручную.'); };
    try { navigator.clipboard.writeText(text).then(done, fail); } catch (e) { fail(); }
  }

  async function choose(boatId) {
    var r = await sb.rpc('choose_featured', { p_boat: boatId, p_note: noteInput.value });
    if (r.error) { toast(errText(r.error)); return; }
    toast('Лучшая работа выбрана. Автору отправлено уведомление.');
    loadFinal();
  }
  async function markFinalist(boatId, status) {
    var r = await sb.rpc('admin_mark_finalist', { p_boat: boatId, p_status: status });
    if (r.error) { toast(errText(r.error)); return; }
    toast(status === 'rewarded' ? 'Отмечено: награда выдана.' : 'Отмечено: не ответил. Выбери другую работу.');
    loadFinal();
  }
  async function closeNow() {
    var r = await sb.rpc('admin_close_week_now');
    if (r.error) { toast(errText(r.error)); return; }
    toast(r.data > 0 ? 'Итоги подведены. В топ-5: ' + r.data + '. Авторам отправлены уведомления.' : 'Пока нет лодок с достаточным числом оценок.');
    loadFinal();
  }

  /* ---------- Модерация ---------- */
  var modBox = h('div', { class: 'admin-grid' });
  var modCount = h('span', { style: 'font-weight:600' });

  async function loadMod() {
    var r = await sb.from('boats')
      .select('id,title,image_path,status,created_at,profiles(nick),reports(count)')
      .in('status', ['pending', 'hidden']).order('created_at', { ascending: true }).limit(50);
    if (r.error) { modBox.replaceChildren(h('p', { class: 'note', text: errText(r.error) })); return; }
    modCount.textContent = 'Ждут проверки: ' + r.data.length;
    if (!r.data.length) {
      modBox.replaceChildren(h('div', { class: 'card pad', style: 'grid-column:1/-1;font-size:18px', text: 'Очередь пуста: всё проверено.' }));
      return;
    }
    modBox.replaceChildren.apply(modBox, r.data.map(function (b) {
      var n = b.reports && b.reports[0] ? b.reports[0].count : 0;
      var why = b.status === 'hidden' ? 'Скрыто: жалоб ' + n : 'Новый участник, на проверке';
      var nick = b.profiles && b.profiles.nick ? b.profiles.nick : '?';
      return h('article', { class: 'card' },
        h('div', { class: 'cardimg' }, h('img', { src: IB.imageUrl(b.image_path), alt: 'Фото «' + b.title + '»', loading: 'lazy' })),
        h('div', null, h('div', { class: 'card-title', text: b.title }), h('div', { class: 'muted', text: '@' + nick })),
        h('span', { class: 'pill pill-line', style: 'align-self:flex-start', text: why }),
        h('div', { class: 'row' },
          h('button', { class: 'btn btn-fill', type: 'button', style: 'flex:1 1 110px', text: 'Одобрить', onclick: function () { moderate(b.id, 'approve'); } }),
          h('button', { class: 'btn btn-ghost', type: 'button', style: 'flex:1 1 110px', text: 'Удалить', onclick: function () { moderate(b.id, 'remove'); } })));
    }));
  }
  async function moderate(id, action) {
    var r = await sb.rpc('moderate_boat', { p_boat: id, p_action: action });
    if (r.error) { toast(errText(r.error)); return; }
    toast(action === 'approve' ? 'Одобрено.' : 'Удалено.');
    loadMod();
  }

  /* ---------- Пользователи и админы ---------- */
  var usersBox = h('div', { class: 'stack' });
  var searchInput = h('input', { class: 'inp', id: 'user-search', type: 'search', placeholder: 'Найти по нику', autocomplete: 'off', style: 'max-width:320px' });

  async function loadUsers() {
    var r = await sb.rpc('admin_list_users', { p_query: searchInput.value.trim() });
    if (r.error) { usersBox.replaceChildren(h('p', { class: 'note', text: errText(r.error) })); return; }
    if (!r.data.length) { usersBox.replaceChildren(h('p', { class: 'note', text: 'Никого не найдено.' })); return; }
    usersBox.replaceChildren.apply(usersBox, r.data.map(function (u) {
      var badges = [];
      if (u.u_is_owner) badges.push(h('span', { class: 'pill pill-light', text: 'Владелец' }));
      else if (u.u_is_admin) badges.push(h('span', { class: 'pill pill-lav', text: 'Админ' }));
      if (u.u_banned) badges.push(h('span', { class: 'pill pill-strike', text: 'Заблокирован' }));
      var actions = [];
      if (isOwner && !u.u_is_owner) {
        actions.push(h('button', { class: 'btn btn-sm ' + (u.u_is_admin ? 'btn-ghost' : 'btn-fill'), type: 'button',
          text: u.u_is_admin ? 'Снять админа' : 'Сделать админом',
          onclick: function () { setAdmin(u, !u.u_is_admin); } }));
      }
      if (!u.u_is_admin && !u.u_is_owner) {
        actions.push(h('button', { class: 'btn btn-ghost btn-sm', type: 'button',
          text: u.u_banned ? 'Разблокировать' : 'Заблокировать',
          onclick: function () { setBan(u, !u.u_banned); } }));
      }
      return h('div', { class: 'card user-row' },
        h('div', { class: 'who' },
          h('span', { style: 'font-weight:600;font-size:17px', text: '@' + u.u_nick }),
          isOwner && u.u_email ? h('span', { class: 'muted', text: u.u_email }) : null),
        h('div', { class: 'row' }, badges, actions));
    }));
  }
  async function setAdmin(u, make) {
    var r = await sb.rpc('set_admin', { p_user: u.u_id, p_make: make });
    if (r.error) { toast(errText(r.error)); return; }
    toast(make ? '@' + u.u_nick + ' теперь админ.' : 'У @' + u.u_nick + ' сняты права админа.');
    loadUsers();
  }
  async function setBan(u, ban) {
    var r = await sb.rpc('ban_user', { p_user: u.u_id, p_ban: ban });
    if (r.error) { toast(errText(r.error)); return; }
    toast(ban ? '@' + u.u_nick + ' заблокирован.' : '@' + u.u_nick + ' разблокирован.');
    loadUsers();
  }
  searchInput.addEventListener('input', function () {
    clearTimeout(searchInput._t);
    searchInput._t = setTimeout(loadUsers, 300);
  });

  /* ---------- Настройки ---------- */
  var setBox = h('div', { class: 'stack', style: 'max-width:900px' });
  var SET = [
    ['report_threshold', 'Жалоб до скрытия фото', 'Когда на фото пожалуются столько человек, оно скроется до проверки.', 2, 10, ''],
    ['min_ratings', 'Минимум оценок для топ-5', 'Лодка попадёт в топ-5 недели, только если у неё не меньше оценок.', 1, 50, ''],
    ['new_user_review', 'Сколько первых фото проверять', 'Столько первых фото нового участника ждут твоего одобрения.', 0, 10, ''],
    ['daily_limit', 'Фото в сутки от одного человека', 'Защита от спама.', 1, 20, '']
  ];
  async function loadSettings() {
    var r = await sb.from('settings').select('key,value');
    if (r.error) { setBox.replaceChildren(h('p', { class: 'note', text: errText(r.error) })); return; }
    var vals = {};
    r.data.forEach(function (x) { vals[x.key] = x.value; });
    setBox.replaceChildren.apply(setBox, SET.map(function (s) {
      var v = vals[s[0]];
      var out = h('b', { text: String(v) });
      function change(d) {
        var nv = Math.max(Math.max(1, s[3]), Math.min(s[4], v + d));
        if (nv === v) return;
        sb.rpc('set_setting', { p_key: s[0], p_value: nv }).then(function (res) {
          if (res.error) { toast(errText(res.error)); return; }
          v = nv; out.textContent = String(v);
        });
      }
      return h('div', { class: 'card toggle-row', style: 'flex-direction:row' },
        h('div', { style: 'flex:1 1 300px;min-width:0' },
          h('div', { style: 'font-weight:600;font-size:17px', text: s[1] }),
          h('div', { class: 'muted', text: s[2] })),
        h('div', { class: 'stepper' },
          h('button', { class: 'st', type: 'button', 'aria-label': 'Меньше: ' + s[1], text: '−', onclick: function () { change(-1); } }),
          out,
          h('button', { class: 'st', type: 'button', 'aria-label': 'Больше: ' + s[1], text: '+', onclick: function () { change(1); } })));
    }));
  }

  /* ---------- Сборка страницы ---------- */
  function section(id, title, lead) {
    var rest = Array.prototype.slice.call(arguments, 3);
    return h('section', { class: 'section', id: id },
      h('h2', { class: 'section-title', text: title }),
      lead ? h('p', { style: 'max-width:72ch', text: lead }) : null, rest);
  }

  root.replaceChildren(
    h('section', { class: 'stack', style: 'max-width:760px;gap:14px' },
      h('h1', { class: 'page-title', text: 'Панель администратора' }),
      h('p', { class: 'lead', text: 'Сайт сам пропускает чистые фото и скрывает спорные. Тебе остаётся выбрать лучшую работу недели и разобрать короткую очередь.' }),
      h('div', { class: 'row' }, h('span', { class: 'pill pill-demo', text: isOwner ? 'Ты владелец сайта' : 'Ты администратор' }))),

    section('choice', 'Лучшая работа недели',
      'В воскресенье в 06:00 по Москве сайт фиксирует топ-5 и отправляет авторам уведомление «Выбираем лучшую работу». Ты выбираешь одну из пяти: она получает рамку на сайте и попадает на страницу «Лучшие работы».',
      finStatus,
      h('div', { class: 'field', style: 'max-width:420px' },
        h('label', { class: 'lbl', style: 'color:var(--text)', for: 'reward-note', text: 'Награда (этот текст увидят все на странице «Лучшие работы»)' }), noteInput),
      finBox,
      h('div', { class: 'row' },
        h('button', { class: 'linkbtn', type: 'button', style: 'color:var(--ink)', text: 'Подвести итоги сейчас (проверка)', onclick: closeNow }))),

    section('mod', 'Модерация', 'Сюда попадают только спорные случаи: жалобы и первые фото новых участников.',
      h('div', null, modCount), modBox),

    section('users', 'Пользователи', isOwner
      ? 'Ты владелец: можешь назначать и снимать админов. Админ видит эту панель, но других админов назначать не может.'
      : 'Здесь можно найти пользователя и заблокировать нарушителя. Назначать админов может только владелец.',
      h('div', { class: 'field' }, h('label', { class: 'sr', for: 'user-search', text: 'Поиск по нику' }), searchInput),
      usersBox),

    section('settings', 'Автоматика', 'Чем больше настроено, тем реже нужно заходить: достаточно раза в день.', setBox)
  );

  loadFinal(); loadMod(); loadUsers(); loadSettings();
})();
