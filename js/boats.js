/* Страница «Лодки»: список, оценки 1-10, комментарии, жалобы, загрузка фото. */
(async function () {
  'use strict';
  var IB = window.IB, sb = IB.sb, h = IB.h, toast = IB.toast, errText = IB.errText;
  await IB.init('boats');

  var uploadBtn = document.getElementById('upload-btn');
  var gridEl = document.getElementById('boats-grid');
  var topEl = document.getElementById('top5');
  if (!sb) { gridEl.replaceChildren(); topEl.replaceChildren(); uploadBtn.disabled = true; return; }

  var me = IB.state.user ? IB.state.user.id : null;
  var isAdmin = !!(IB.state.profile && IB.state.profile.is_admin);
  var boats = [], top5 = [], mine = {}, feat = null;

  function needLogin(text) {
    toast(text || 'Войди в аккаунт, чтобы это сделать.');
    setTimeout(function () { location.href = 'login.html?next=boats.html#login'; }, 1200);
  }

  async function load() {
    var since = new Date(Date.now() - 7 * 864e5).toISOString();
    var res = await Promise.all([
      sb.from('boat_stats').select('*').in('status', ['approved', 'pending']).order('created_at', { ascending: false }).limit(60),
      sb.from('boat_stats').select('*').eq('status', 'approved').gte('created_at', since).gt('votes', 0)
        .order('avg_score', { ascending: false }).order('votes', { ascending: false }).limit(5),
      sb.from('featured').select('boat_id,chosen_at').order('chosen_at', { ascending: false }).limit(1)
    ]);
    if (res[0].error) {
      gridEl.replaceChildren(h('p', { class: 'note', text: 'Не удалось загрузить лодки: ' + errText(res[0].error) }));
      topEl.replaceChildren();
      return;
    }
    boats = res[0].data.filter(function (b) { return b.status === 'approved' || b.user_id === me; });
    top5 = res[1].data || [];
    feat = res[2].data && res[2].data[0] ? res[2].data[0] : null;
    mine = {};
    if (me && boats.length) {
      var r = await sb.from('ratings').select('boat_id,score').eq('user_id', me)
        .in('boat_id', boats.map(function (b) { return b.id; }));
      (r.data || []).forEach(function (x) { mine[x.boat_id] = x.score; });
    }
    render();
  }

  function isFeat(b) {
    return feat && feat.boat_id === b.id && (Date.now() - new Date(feat.chosen_at).getTime()) < 7 * 864e5;
  }

  function pic(b) {
    return h('div', { class: 'cardimg' }, h('img', { src: IB.imageUrl(b.image_path), alt: 'Лодка «' + b.title + '»', loading: 'lazy' }));
  }

  function render() {
    topEl.replaceChildren.apply(topEl, top5.length ? top5.map(function (b, i) {
      return h('article', { class: 'card' },
        h('div', { class: 'row', style: 'justify-content:space-between' },
          h('span', { class: 'rank', text: String(i + 1) }),
          h('span', { class: 'pill pill-lav', text: b.avg_score + ' / 10' })),
        pic(b),
        h('div', null,
          h('div', { class: 'card-title', text: b.title }),
          h('div', { class: 'muted', text: '@' + b.nick })));
    }) : [h('p', { class: 'note', text: 'Пока нет лодок с оценками за эту неделю.' })]);

    gridEl.replaceChildren.apply(gridEl, boats.length ? boats.map(card) :
      [h('p', { class: 'note', text: 'Пока нет ни одной лодки. Будь первым: нажми «Добавить фото лодки».' })]);
  }

  function card(b) {
    var own = b.user_id === me;
    var pending = b.status === 'pending';
    var scores = h('div', { class: 'scores', role: 'group', 'aria-label': 'Оценка от 1 до 10' });
    for (var v = 1; v <= 10; v++) {
      (function (v) {
        scores.append(h('button', {
          class: 'sc', type: 'button', text: String(v),
          'aria-pressed': mine[b.id] === v ? 'true' : 'false',
          'aria-label': 'Оценка ' + v,
          disabled: own || pending,
          onclick: function () { rate(b, v); }
        }));
      })(v);
    }
    var status = own ? (pending ? 'Фото на проверке, оценки пока недоступны.' : 'Это твоя лодка.') :
      (mine[b.id] ? 'Твоя оценка: ' + mine[b.id] : 'Поставь оценку от 1 до 10');

    return h('article', { class: 'card' + (isFeat(b) ? ' feat' : '') },
      isFeat(b) ? h('span', { class: 'pill pill-light', style: 'align-self:flex-start', text: 'Работа недели' }) : null,
      pending ? h('span', { class: 'pill pill-line', style: 'align-self:flex-start', text: 'На проверке' }) : null,
      pic(b),
      h('div', { class: 'row', style: 'justify-content:space-between;align-items:baseline;flex-wrap:nowrap' },
        h('div', { style: 'min-width:0' },
          h('h3', { class: 'card-title', text: b.title }),
          h('div', { class: 'muted', text: '@' + b.nick })),
        h('span', { class: 'avg', text: b.votes ? String(b.avg_score) : '–' })),
      h('div', { class: 'muted', text: b.votes + ' ' + plural(b.votes, 'оценка', 'оценки', 'оценок') }),
      h('div', { class: 'stack', style: 'gap:8px' }, h('span', { class: 'muted', style: 'font-weight:500', text: status }), scores),
      h('div', { class: 'row', style: 'justify-content:space-between' },
        h('button', { class: 'btn btn-ghost btn-sm', type: 'button', text: 'Комментарии', onclick: function () { openComments(b); } }),
        (!own && !pending) ? h('button', { class: 'linkbtn', type: 'button', text: 'Пожаловаться', onclick: function (e) { report(b, e.currentTarget); } }) : null,
        (own || isAdmin) ? h('button', { class: 'linkbtn', type: 'button', text: 'Удалить', onclick: function () { removeBoat(b); } }) : null));
  }

  function plural(n, a, b, c) {
    var m = Math.abs(n) % 100, d = m % 10;
    if (m > 10 && m < 20) return c;
    if (d > 1 && d < 5) return b;
    if (d === 1) return a;
    return c;
  }

  async function rate(b, v) {
    if (!me) { needLogin('Войди, чтобы оценивать лодки.'); return; }
    var r = await sb.from('ratings').upsert({ boat_id: b.id, user_id: me, score: v }, { onConflict: 'boat_id,user_id' });
    if (r.error) { toast(errText(r.error)); return; }
    mine[b.id] = v;
    var s = await sb.from('boat_stats').select('*').eq('id', b.id).single();
    if (s.data) Object.assign(b, s.data);
    render();
    toast('Оценка ' + v + ' сохранена.');
  }

  async function report(b, btn) {
    if (!me) { needLogin('Войди, чтобы пожаловаться.'); return; }
    var r = await sb.from('reports').insert({ boat_id: b.id, user_id: me });
    if (r.error) {
      toast(r.error.code === '23505' ? 'Ты уже отправлял жалобу на это фото.' : errText(r.error));
      return;
    }
    btn.textContent = 'Жалоба отправлена';
    btn.disabled = true;
    toast('Спасибо, жалоба отправлена.');
  }

  async function removeBoat(b) {
    var ok = await IB.confirm('Удалить лодку «' + b.title + '»?', 'Да, удалить');
    if (!ok) return;
    var r = await sb.from('boats').delete().eq('id', b.id);
    if (r.error) { toast(errText(r.error)); return; }
    toast('Лодка удалена.');
    load();
  }

  async function openComments(b) {
    var list = h('div', { class: 'stack' }, h('p', { class: 'muted', text: 'Загрузка…' }));
    var input = h('input', { class: 'inp', id: 'c-input', type: 'text', maxlength: '500', placeholder: 'Напиши комментарий', autocomplete: 'off' });
    var form = h('form', { class: 'row', style: 'margin-top:16px;flex-wrap:nowrap' },
      h('label', { class: 'sr', for: 'c-input', text: 'Комментарий' }), input,
      h('button', { class: 'btn btn-fill', type: 'submit', text: 'Отправить' }));
    var canPost = me && !pending(b);
    function pending(x) { return x.status !== 'approved'; }

    async function refresh() {
      var r = await sb.from('comments').select('id,body,created_at,user_id,profiles(nick)')
        .eq('boat_id', b.id).order('created_at', { ascending: true }).limit(200);
      if (r.error) { list.replaceChildren(h('p', { text: errText(r.error) })); return; }
      if (!r.data.length) { list.replaceChildren(h('p', { text: 'Комментариев пока нет.' })); return; }
      list.replaceChildren.apply(list, r.data.map(function (c) {
        var nick = c.profiles && c.profiles.nick ? c.profiles.nick : '?';
        return h('div', { class: 'comment' },
          h('b', { text: '@' + nick }),
          h('span', { text: c.body }),
          (c.user_id === me || isAdmin) ? h('button', { class: 'linkbtn', type: 'button', style: 'align-self:flex-start', text: 'Удалить',
            onclick: async function () {
              var d = await sb.from('comments').delete().eq('id', c.id);
              if (d.error) toast(errText(d.error)); else refresh();
            } }) : null);
      }));
    }

    form.addEventListener('submit', async function (e) {
      e.preventDefault();
      var text = input.value.trim();
      if (!text) return;
      var r = await sb.from('comments').insert({ boat_id: b.id, user_id: me, body: text });
      if (r.error) { toast(errText(r.error)); return; }
      input.value = '';
      refresh();
    });

    IB.modal('Комментарии: ' + b.title, list,
      canPost ? form : h('p', { class: 'note', style: 'margin-top:16px' },
        me ? 'Комментарии откроются после проверки фото.' : h('span', null, 'Чтобы комментировать, ', h('a', { class: 'linkbtn', href: 'login.html?next=boats.html#login', text: 'войди в аккаунт' }), '.')));
    refresh();
  }

  var prepare = IB.prepareImage;

  function openUpload() {
    if (!me) { needLogin('Войди, чтобы добавить фото.'); return; }
    var msg = h('p', { class: 'note', role: 'status' });
    var title = h('input', { class: 'inp', id: 'u-title', type: 'text', maxlength: '60', placeholder: 'Например: Быстрый катамаран', required: true });
    var file = h('input', { class: 'inp', id: 'u-file', type: 'file', accept: 'image/jpeg,image/png,image/webp', required: true, style: 'height:auto;padding:12px 14px' });
    var send = h('button', { class: 'btn btn-fill', type: 'submit', text: 'Опубликовать' });
    var form = h('form', { class: 'stack' },
      h('div', { class: 'field' }, h('label', { class: 'lbl', for: 'u-title', text: 'Название лодки' }), title),
      h('div', { class: 'field' }, h('label', { class: 'lbl', for: 'u-file', text: 'Фото (JPG, PNG, WebP)' }), file),
      h('p', { class: 'note', style: 'color:var(--soft)', text: 'Только лодки из Build a Boat. Правила внизу страницы.' }),
      msg, send);
    var dlg = IB.modal('Добавить фото лодки', form);

    form.addEventListener('submit', async function (e) {
      e.preventDefault();
      msg.textContent = '';
      var f = file.files[0];
      var t = title.value.trim();
      if (!f || t.length < 2) { msg.textContent = 'Укажи название (от 2 символов) и выбери фото.'; return; }
      send.disabled = true; send.textContent = 'Загрузка…';
      var path = null;
      try {
        var blob = await prepare(f);
        var id = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2);
        path = me + '/' + id + '.jpg';
        var up = await sb.storage.from('boats').upload(path, blob, { contentType: 'image/jpeg', upsert: false });
        if (up.error) throw up.error;
        var ins = await sb.from('boats').insert({ user_id: me, title: t, image_path: path }).select('status').single();
        if (ins.error) { await sb.storage.from('boats').remove([path]); throw ins.error; }
        dlg.close();
        toast(ins.data && ins.data.status === 'approved' ? 'Лодка опубликована.' : 'Фото отправлено на проверку. Оно появится после одобрения.');
        load();
      } catch (err) {
        msg.textContent = errText(err);
        send.disabled = false; send.textContent = 'Опубликовать';
      }
    });
  }

  uploadBtn.addEventListener('click', openUpload);
  await load();
  if (location.hash === '#upload') openUpload();
})();
