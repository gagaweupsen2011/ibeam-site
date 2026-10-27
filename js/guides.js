/* Страница «Build a Boat»: схемы лодок и туториалы (фото и ролики YouTube). */
(async function () {
  'use strict';
  var IB = window.IB, sb = IB.sb, h = IB.h, errText = IB.errText;
  var st = await IB.init('guides');

  var grid = document.getElementById('guides-grid');
  var lead = document.getElementById('guides-lead');
  var tabS = document.getElementById('tab-schemes');
  var tabT = document.getElementById('tab-tutorials');
  if (!sb) { grid.replaceChildren(); return; }

  var isAdmin = !!(st.profile && st.profile.is_admin);
  var kind = location.hash === '#tutorials' ? 'tutorial' : 'scheme';
  var items = [];

  function setKind(k) {
    kind = k;
    var s = k === 'scheme';
    tabS.setAttribute('aria-selected', s ? 'true' : 'false');
    tabT.setAttribute('aria-selected', s ? 'false' : 'true');
    lead.textContent = s ? 'Схемы лодок: смотри, из чего собрана лодка, и повторяй у себя.'
                         : 'Туториалы: как построить корабль шаг за шагом.';
    try { history.replaceState(null, '', s ? '#schemes' : '#tutorials'); } catch (e) { /* не страшно */ }
    render();
  }
  tabS.addEventListener('click', function () { setKind('scheme'); });
  tabT.addEventListener('click', function () { setKind('tutorial'); });

  function openImage(g) {
    IB.modal(g.title, h('img', { src: IB.imageUrl(g.image_path), alt: g.title, style: 'width:100%;border-radius:6px' }));
  }

  /* Ролик запускается по клику: так страница грузится быстро, а YouTube не отслеживает тех, кто просто листает */
  function video(g) {
    var wrap = h('div', { class: 'media' });
    wrap.append(h('button', {
      class: 'video-thumb', type: 'button', 'aria-label': 'Смотреть видео: ' + g.title,
      onclick: function () {
        wrap.replaceChildren(h('iframe', {
          class: 'video-frame', title: g.title,
          src: 'https://www.youtube-nocookie.com/embed/' + g.video_id + '?autoplay=1&rel=0',
          allow: 'autoplay; encrypted-media; picture-in-picture; fullscreen',
          allowfullscreen: true, referrerpolicy: 'strict-origin-when-cross-origin'
        }));
      }
    },
      h('img', { src: 'https://i.ytimg.com/vi/' + g.video_id + '/hqdefault.jpg', alt: '', loading: 'lazy' }),
      h('span', { class: 'play', 'aria-hidden': 'true' })));
    return wrap;
  }

  function picture(g) {
    return h('button', { class: 'cardimg contain img-btn', type: 'button', 'aria-label': 'Открыть крупно: ' + g.title,
      onclick: function () { openImage(g); } },
      h('img', { src: IB.imageUrl(g.image_path), alt: g.title, loading: 'lazy' }));
  }

  function card(g) {
    return h('article', { class: 'card' },
      g.video_id ? video(g) : picture(g),
      h('h3', { class: 'card-title', style: 'font-size:22px', text: g.title }),
      g.description ? h('p', { class: 'desc', text: g.description }) : null,
      (g.video_id && g.image_path)
        ? h('button', { class: 'btn btn-ghost btn-sm', type: 'button', style: 'align-self:flex-start', text: 'Открыть схему', onclick: function () { openImage(g); } })
        : null,
      h('span', { class: 'muted', text: IB.fmtDate(g.created_at) }));
  }

  function render() {
    var list = items.filter(function (g) { return g.kind === kind; });
    if (!list.length) {
      grid.replaceChildren(h('div', { class: 'card pad', style: 'grid-column:1/-1' },
        h('p', { text: kind === 'scheme' ? 'Схемы лодок скоро появятся.' : 'Туториалы скоро появятся.' }),
        isAdmin ? h('div', { class: 'row' }, h('a', { class: 'btn btn-fill', href: 'admin.html#guides', text: 'Добавить в админке' })) : null));
      return;
    }
    grid.replaceChildren.apply(grid, list.map(card));
  }

  var r = await sb.from('guides').select('*').order('created_at', { ascending: false }).limit(100);
  if (r.error) {
    grid.replaceChildren(h('p', { class: 'note', text: 'Не удалось загрузить: ' + errText(r.error) }));
    return;
  }
  items = r.data || [];
  setKind(kind);
})();
