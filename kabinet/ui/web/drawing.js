'use strict';
// LayOut 도면 · 내 가구 보관함 · EP 판재 화면 (Kabinet 2.0 ep.js를 Kabinet 창에 통합).
// 요소 ID는 'ep-' 접두사, 상태 메시지는 하단 상태줄(kabinet.setStatus)에 표시.
(function () {
  const byId = id => document.getElementById('ep-' + id);
  const root = () => document.querySelectorAll('.ep-view');
  let library = [];
  let pending = false;

  function setButtons(disabled) {
    root().forEach(v => v.querySelectorAll('button').forEach(b => { b.disabled = disabled; }));
  }
  function call(name, arg, message) {
    pending = true;
    setButtons(true);
    kabinet.setStatus(message, '');
    try {
      window.sketchup[name](arg);
    } catch (e) {
      window.epResult('SketchUp의 Kabinet 창에서 실행하세요.', true);
    }
  }

  window.epResult = function (message, error) {
    pending = false;
    setButtons(false);
    kabinet.setStatus(message, error ? 'error' : 'ok');
    renderLibrary();
  };

  const selected = new Set();

  window.epLibrary = function (items) {
    library = Array.isArray(items) ? items : [];
    const ids = new Set(library.map(i => i.id));
    [...selected].forEach(id => { if (!ids.has(id)) selected.delete(id); });
    const folders = _folders();
    const filter = byId('library-filter');
    const cur = filter.value;
    filter.replaceChildren(new Option('전체 폴더', ''), ...folders.map(f => new Option(f, f)));
    filter.value = folders.includes(cur) ? cur : '';
    byId('library-folders').replaceChildren(...folders.map(f => new Option(f, f)));
    renderLibrary();
    kabinet.setLibrary(library);   // 왼쪽 사이드바 "내 가구 보관함" 폴더
  };

  function _folders() {
    return [...new Set(library.map(i => i.folder || '미분류'))].sort((a, b) => a.localeCompare(b, 'ko'));
  }

  window.kabinetDrawing = {
    place(id) { call('ep_library_place', id, '저장한 가구를 불러오고 있습니다…'); },
    refresh() { if (window.sketchup) window.sketchup.ep_library_list(); },
    setSpaceMode(on) {
      byId('space-mode').checked = !!on;
      applySpaceMode();
    }
  };

  const esc = t => String(t).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  function renderTabs() {
    const tabs = byId('lib-tabs');
    if (!tabs) return;
    const sel = byId('library-filter').value;
    const counts = {};
    library.forEach(i => { const f = i.folder || '미분류'; counts[f] = (counts[f] || 0) + 1; });
    const tab = (value, label, n) =>
      `<button type="button" class="lib-tab${sel === value ? ' active' : ''}" data-tab="${esc(value)}">${esc(label)} <span>${n}</span></button>`;
    tabs.innerHTML = tab('', '전체', library.length) + _folders().map(f => tab(f, f, counts[f])).join('');
    tabs.querySelectorAll('[data-tab]').forEach(b => b.addEventListener('click', () => {
      byId('library-filter').value = b.dataset.tab;
      renderLibrary();
    }));
  }

  function renderBulk() {
    const bar = byId('lib-bulk');
    bar.hidden = selected.size === 0;
    byId('lib-count').textContent = selected.size + '개 선택';
  }

  function renderLibrary() {
    const box = byId('library-list');
    if (!box) return;
    renderTabs();
    renderBulk();
    const q = byId('library-search').value.trim().toLocaleLowerCase();
    const selF = byId('library-filter').value;
    const items = library.filter(i => {
      const f = i.folder || '미분류';
      return (!selF || f === selF) && (i.name.toLocaleLowerCase().includes(q) || f.toLocaleLowerCase().includes(q));
    });
    if (!items.length) {
      box.innerHTML = `<p class="ep-hint">${library.length ? '조건에 맞는 가구가 없습니다.' : '아직 저장한 가구가 없습니다. 위에서 선택한 가구를 넣어 보세요.'}</p>`;
      return;
    }
    const folders = _folders();
    box.innerHTML = items.map(it => {
      const dims = Array.isArray(it.dimensions_mm) ? it.dimensions_mm.map(v => Math.round(v)).join('×') + 'mm' : '';
      const date = String(it.saved_at || '').slice(0, 10);
      const f = it.folder || '미분류';
      return `<div class="lib-card${selected.has(it.id) ? ' sel' : ''}" data-id="${esc(it.id)}">
        <label class="lib-check" title="여러 개 선택"><input type="checkbox" data-check${selected.has(it.id) ? ' checked' : ''}></label>
        <button type="button" class="lib-thumb" data-place title="누르고 모델에서 놓을 곳 클릭">
          ${it.thumb ? `<img src="${it.thumb}" alt="">` : '<span>미리보기 없음</span>'}</button>
        <input class="lib-name" data-name value="${esc(it.name)}" maxlength="60" title="이름 — 고치고 Enter">
        <div class="lib-meta">${esc(dims)} · ${esc(date)}</div>
        <div class="lib-actions">
          <select data-folder title="폴더 이동">${folders.map(x => `<option${x === f ? ' selected' : ''}>${esc(x)}</option>`).join('')}</select>
          <button type="button" class="btn-inline" data-place>배치</button>
          <button type="button" class="btn-inline del-btn" data-del title="삭제">✕</button>
        </div></div>`;
    }).join('');
    box.querySelectorAll('.lib-card').forEach(card => {
      const id = card.dataset.id;
      const item = library.find(i => i.id === id);
      card.querySelectorAll('[data-place]').forEach(b => b.addEventListener('click', () => kabinetDrawing.place(id)));
      card.querySelector('[data-check]').addEventListener('change', e => {
        if (e.target.checked) selected.add(id); else selected.delete(id);
        card.classList.toggle('sel', e.target.checked);
        renderBulk();
      });
      const name = card.querySelector('[data-name]');
      const saveName = () => {
        const v = name.value.trim();
        if (!v) { name.value = item.name; return; }
        if (v !== item.name) call('ep_library_update', JSON.stringify({ id, name: v, folder: item.folder || '미분류' }), '이름을 바꾸는 중…');
      };
      name.addEventListener('keydown', e => { if (e.key === 'Enter') name.blur(); });
      name.addEventListener('change', saveName);
      card.querySelector('[data-folder]').addEventListener('change', e =>
        call('ep_library_move', JSON.stringify({ ids: [id], folder: e.target.value }), '폴더를 옮기는 중…'));
      card.querySelector('[data-del]').addEventListener('click', () => {
        if (confirm(`‘${item.name}’을(를) 보관함에서 삭제할까요? (보관함 .trash 폴더로 옮겨집니다)`))
          call('ep_library_delete', JSON.stringify([id]), '삭제하는 중…');
      });
    });
  }

  function applySpaceMode() {
    const on = byId('space-mode').checked;
    byId('space-options').hidden = !on;
    byId('furniture-options').hidden = on;
    document.querySelectorAll('#view-drawing [data-furniture-only]').forEach(el => { el.hidden = on; });
    byId('export').textContent = on ? '공간 도면 출력 · LayOut + PDF' : '가구 도면 출력 · LayOut + PDF';
    byId('drawing-heading').textContent = on ? '공간 도면 — LayOut + PDF (A3 가로)' : '가구 도면 — LayOut + PDF (A3 가로)';
  }

  document.addEventListener('DOMContentLoaded', () => {
    const today = new Date();
    const ymd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    byId('drawing-date').value = ymd;
    byId('survey-date').value = ymd;

    byId('board-form').addEventListener('submit', ev => {
      ev.preventDefault();
      call('ep_create', JSON.stringify({ width: byId('width').value, thickness: byId('thickness').value, height: byId('height').value }),
           'EP 판재를 준비하고 있습니다…');
    });
    byId('library-form').addEventListener('submit', ev => {
      ev.preventDefault();
      const name = byId('library-name').value.trim();
      if (!name) { window.epResult('저장할 가구 이름을 입력하세요.', true); return; }
      call('ep_library_save', JSON.stringify({ name, folder: byId('library-folder').value.trim() }),
           '선택한 가구를 보관함에 저장하고 있습니다…');
    });
    byId('library-search').addEventListener('input', renderLibrary);
    byId('lib-thumbs').addEventListener('click', () => call('ep_library_thumbs', '', '미리보기 이미지를 만드는 중… (가구 수에 따라 잠시 걸립니다)'));
    byId('lib-move').addEventListener('click', () => {
      const f = byId('lib-move-folder').value.trim();
      if (!f) { window.epResult('옮길 폴더 이름을 입력하세요.', true); return; }
      call('ep_library_move', JSON.stringify({ ids: [...selected], folder: f }), '폴더를 옮기는 중…');
      selected.clear();
    });
    byId('lib-delete').addEventListener('click', () => {
      if (!selected.size || !confirm(`선택한 ${selected.size}개를 삭제할까요? (보관함 .trash 폴더로 옮겨집니다)`)) return;
      call('ep_library_delete', JSON.stringify([...selected]), '삭제하는 중…');
      selected.clear();
    });
    byId('lib-clear').addEventListener('click', () => { selected.clear(); renderLibrary(); });
    byId('library-filter').addEventListener('change', renderLibrary);
    byId('space-mode').addEventListener('change', applySpaceMode);

    byId('export').addEventListener('click', () => {
      const space = byId('space-mode').checked;
      call('ep_export', JSON.stringify({
        title: byId('title').value.trim() || '가구 도면', internal: byId('internal').checked,
        iso_direction: byId('iso-direction').value, furniture_name: byId('furniture-name').value.trim(),
        site: byId('site').value.trim(), drawing_date: byId('drawing-date').value, author: byId('author').value.trim(),
        memo: byId('memo').value.trim(), surface_left: byId('surface-left').value,
        surface_right: byId('surface-right').value, surface_back: byId('surface-back').value,
        space_mode: space, space_name: byId('space-name').value.trim(), ceiling_height: byId('ceiling-height').value,
        survey_date: byId('survey-date').value, wall_views: byId('wall-views').checked
      }), space ? '공간 도면을 작성하고 있습니다. 잠시 기다려 주세요…' : '선택 가구의 도면을 작성하고 있습니다. 잠시 기다려 주세요…');
    });
    document.querySelectorAll('#view-drawing [data-role]').forEach(b => b.addEventListener('click', () =>
      call('ep_role', b.dataset.role, '선택 부품을 구분하고 있습니다…')));
    document.querySelectorAll('#view-drawing [data-front]').forEach(b => b.addEventListener('click', () =>
      call('ep_front', b.dataset.front, '가구의 정면 방향을 확인하고 있습니다…')));
    document.querySelectorAll('#view-drawing [data-space-role]').forEach(b => b.addEventListener('click', () =>
      call('ep_space_role', b.dataset.spaceRole, '공간 부품을 지정하고 있습니다…')));

    applySpaceMode();
    if (window.sketchup) {
      try { window.sketchup.ep_library_list(); } catch (e) { window.epLibrary([]); }
    } else {
      window.epLibrary([]);
    }
  });
})();
