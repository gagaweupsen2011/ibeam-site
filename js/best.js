/* Страница «Лучшие работы»: работа недели в рамке и архив победителей. */
(async function () {
  'use strict';
  var IB = window.IB, sb = IB.sb, h = IB.h, errText = IB.errText;
  await IB.init('best');

  var spot = document.getElementById('spot');
  var archive = document.getElementById('archive');
  if (!sb) { spot.replaceChildren(); return; }

  var f = await sb.from('featured').select('*').order('chosen_at', { ascending: false }).limit(25);
  if (f.error) { spot.replaceChildren(h('p', { class: 'note', text: 'Не удалось загрузить: ' + errText(f.error) })); return; }
  if (!f.data.length) {
    spot.replaceChildren(h('div', { class: 'card pad' },
      h('p', { text: 'Первая лучшая работа появится после первого недельного итога. Выкладывай лодки и ставь оценки.' }),
      h('div', { class: 'row' }, h('a', { class: 'btn btn-fill', href: 'boats.html', text: 'Перейти к лодкам' }))));
    return;
  }

  var ids = f.data.map(function (x) { return x.boat_id; });
  var s = await sb.from('boat_stats').select('*').in('id', ids);
  var byId = {};
  (s.data || []).forEach(function (b) { byId[b.id] = b; });

  function pic(b) {
    return h('div', { class: 'cardimg' }, h('img', { src: IB.imageUrl(b.image_path), alt: 'Лодка «' + b.title + '»', loading: 'lazy' }));
  }

  var first = f.data[0];
  var b0 = byId[first.boat_id];
  if (b0) {
    spot.replaceChildren(h('article', { class: 'card feat spot' },
      pic(b0),
      h('div', { class: 'spot-info' },
        h('span', { class: 'pill pill-light', text: 'Работа недели' }),
        h('h2', { text: b0.title }),
        h('span', { style: 'font-size:17px;color:var(--soft)', text: 'Автор: @' + b0.nick + ' · оценка ' + b0.avg_score + ' / 10' }),
        h('p', { style: 'color:var(--soft)', text: first.reward_note ? 'Награда: ' + first.reward_note : 'Награда будет объявлена автору.' }),
        first.rewarded ? h('span', { class: 'pill pill-lav', text: 'Награда выдана' }) : null,
        h('div', { class: 'row' }, h('a', { class: 'btn btn-fill', href: 'boats.html', text: 'Смотреть и оценить' })))));
  } else {
    spot.replaceChildren(h('p', { class: 'note', text: 'Лодка недели недоступна: возможно, её удалили.' }));
  }

  var rest = f.data.slice(1).filter(function (x) { return byId[x.boat_id]; });
  archive.replaceChildren.apply(archive, rest.length ? rest.map(function (x) {
    var b = byId[x.boat_id];
    return h('article', { class: 'card' },
      pic(b),
      h('span', { class: 'muted', style: 'font-weight:600;letter-spacing:.08em;text-transform:uppercase', text: IB.fmtDate(x.chosen_at) }),
      h('div', null,
        h('h3', { class: 'card-title', text: b.title }),
        h('div', { class: 'muted', text: '@' + b.nick })));
  }) : [h('p', { class: 'note', text: 'Архив пока пуст.' })]);
})();
