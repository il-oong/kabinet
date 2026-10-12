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

  window.epLibrary = function (items) {
    library = Array.isArray(items) ? items : [];
    const folders = [...new Set(library.map(i => i.folder || '미분류'))].sort((a, b) => a.localeCompare(b, 'ko'));
    const filter = byId('library-filter');
    const selected = filter.value;
    filter.replaceChildren(new Option('전체 폴더', ''), ...folders.map(f => new Option(f, f)));
    filter.value = folders.includes(selected) ? selected : '';
    byId('library-folders').replaceChildren(...folders.map(f => new Option(f, f)));
    renderLibrary();
    kabinet.setLibrary(library);   // 왼쪽 사이드바 "내 가구 보관함" 폴더
  };

  window.kabinetDrawing = {
    place(id) { call('ep_library_place', id, '저장한 가구를 불러오고 있습니다…'); },
    refresh() { if (window.sketchup) window.sketchup.ep_library_list(); },
    setSpaceMode(on) {
      byId('space-mode').checked = !!on;
      applySpaceMode();
    }
  };

  function renderLibrary() {
    const box = byId('library-list');
    if (!box) return;
    box.textContent = '';
    const q = byId('library-search').value.trim().toLocaleLowerCase();
    const sel = byId('library-filter').value;
    const items = library.filter(i => {
      const f = i.folder || '미분류';
      return (!sel || f === sel) && (i.name.toLocaleLowerCase().includes(q) || f.toLocaleLowerCase().includes(q));
    });
    if (!items.length) {
      const p = document.createElement('p');
      p.className = 'ep-hint';
      p.textContent = library.length ? '검색한 가구가 없습니다.' : '아직 저장한 가구가 없습니다.';
      box.appendChild(p);
    }
    items.forEach(item => {
      const row = document.createElement('div');
      row.className = 'ep-lib-row';
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'ep-lib-item';
      btn.disabled = pending;
      const t = document.createElement('strong');
      t.textContent = item.name;
      const d = document.createElement('span');
      const dims = Array.isArray(item.dimensions_mm) ? item.dimensions_mm.join(' × ') + ' mm · ' : '';
      d.textContent = (item.folder || '미분류') + ' · ' + dims + String(item.saved_at || '').slice(0, 16).replace('T', ' ');
      btn.append(t, d);
      btn.addEventListener('click', () => kabinetDrawing.place(item.id));

      const edit = document.createElement('button');
      edit.type = 'button';
      edit.className = 'btn-inline';
      edit.textContent = '이름·폴더 변경';
      edit.disabled = pending;
      const form = document.createElement('form');
      form.className = 'ep-lib-edit';
      form.hidden = true;
      const name = document.createElement('input');
      name.value = item.name; name.maxLength = 60; name.required = true;
      const folder = document.createElement('input');
      folder.value = item.folder || '미분류'; folder.maxLength = 40;
      folder.setAttribute('list', 'ep-library-folders');
      const save = document.createElement('button');
      save.type = 'submit'; save.className = 'btn-primary'; save.textContent = '변경 저장';
      const cancel = document.createElement('button');
      cancel.type = 'button'; cancel.className = 'btn-secondary'; cancel.textContent = '취소';
      cancel.addEventListener('click', () => { form.hidden = true; });
      edit.addEventListener('click', () => { form.hidden = !form.hidden; if (!form.hidden) name.focus(); });
      form.append(name, folder, save, cancel);
      form.addEventListener('submit', ev => {
        ev.preventDefault();
        if (!name.value.trim()) { window.epResult('가구 이름을 입력하세요.', true); return; }
        call('ep_library_update', JSON.stringify({ id: item.id, name: name.value.trim(), folder: folder.value.trim() }),
             '가구 이름과 폴더를 변경하고 있습니다…');
      });
      row.append(btn, edit, form);
      box.appendChild(row);
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
