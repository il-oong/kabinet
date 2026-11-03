/* =====================================================================
   도면 시트(DXF) — 페이지 구성 편집
   페이지 목록(순서·숨김·제목·SHEET NO.·SCALE) + 가구명/현장명/DATE + 내보내기 옵션.
   구성은 SketchUp 모델에 저장(kabinet:sheet_save). 계산은 Ruby(Kabinet::Output::Sheet).
   ===================================================================== */
const kabinetSheet = (() => {
  const STORE = 'kabinet.sheetConfig';   // 브라우저 단독 실행(테스트)용 보조 저장
  let cfg = null;
  let types = {};
  let furniture = {};
  let scenes = [];
  let dragId = null;
  let saveTimer = null;

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const DEFAULT_TYPES = { photos: '현장사진', view3d: '상담 3D', floor: '평면도', furniture: '가구 시트 (TOP / 정면)', side: '측면 · 단면', detail: '상세 (EP · 목찬넬)', table: '생산 확인표' };
  let seq = 0;
  const newId = () => 'p' + Date.now().toString(36) + (seq++);

  function defaultConfig() {
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const mk = (type, title) => ({ id: newId(), type, title, subject: title, sheet_no: '', scale: '', hidden: false, export: true, images: [] });
    return {
      site: '', furniture_name: '', date: d.getFullYear() + '.' + pad(d.getMonth() + 1) + '.' + pad(d.getDate()),
      bg: 'white', style_name: 'MALGUN', font_file: 'malgun.ttf',
      pages: [mk('photos', '현장사진'), mk('view3d', '상담 3D'), mk('floor', '평면도'), mk('furniture', '가구 시트'),
              mk('side', '측면 · 단면'), mk('detail', '상세'), mk('table', '생산 확인표')]
    };
  }

  function ensure() {
    if (cfg) return;
    try { cfg = JSON.parse(localStorage.getItem(STORE) || 'null'); } catch (e) { cfg = null; }
    if (!cfg || !Array.isArray(cfg.pages)) cfg = defaultConfig();
    if (!Object.keys(types).length) types = DEFAULT_TYPES;
  }

  function persist() {
    try { localStorage.setItem(STORE, JSON.stringify(cfg)); } catch (e) {}
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      if (window.sketchup && sketchup['kabinet:sheet_save']) sketchup['kabinet:sheet_save'](JSON.stringify(cfg));
    }, 300);
  }

  // Ruby 가 모델에 저장된 구성을 보내 줄 때
  function setState(payload) {
    if (payload && payload.config) cfg = payload.config;
    if (payload && payload.page_types) types = payload.page_types;
    furniture = (payload && payload.furniture) || {};
    scenes = (payload && payload.scenes) || [];
    cfg.pages.forEach(p => { if (p.export === undefined) p.export = true; });
    render();
  }

  function open() {
    ensure();
    render();
    if (window.sketchup && sketchup['kabinet:sheet_load']) sketchup['kabinet:sheet_load']('');
  }

  function typeLabel(t) { return types[t] || DEFAULT_TYPES[t] || t; }

  function render() {
    ensure();
    ['site', 'furniture_name', 'date', 'style_name'].forEach(k => { const el = $('sh-' + k); if (el && el !== document.activeElement) el.value = cfg[k] || ''; });
    const bg = $('sh-bg'); if (bg) bg.value = cfg.bg || 'white';
    const info = $('sh-furniture-info');
    if (info) info.textContent = furniture.has_furniture ? ('도면 기준 가구: ' + furniture.name + ' (' + furniture.size + ' mm)') :
      '선택한/마지막 Kabinet 가구가 없으면 샘플 가구(1,800×2,300×600)로 틀만 그립니다.';
    const list = $('sh-pages');
    if (!list) return;
    list.innerHTML = cfg.pages.map((p, i) => (
      '<div class="sh-row' + (p.hidden ? ' hidden-page' : '') + '" draggable="true" data-id="' + esc(p.id) + '">' +
      '<span class="sh-handle" title="끌어서 순서 변경">☰</span>' +
      '<span class="sh-no">' + (i + 1) + '</span>' +
      '<span class="sh-type">' + esc(typeLabel(p.type)) + '</span>' +
      '<input class="sh-title" data-k="subject" value="' + esc(p.subject) + '" placeholder="제목(SUBJECT TITLE)" title="제목">' +
      '<input class="sh-small" data-k="sheet_no" value="' + esc(p.sheet_no) + '" placeholder="SHEET NO." title="SHEET NO. (비우면 자동)">' +
      '<input class="sh-small" data-k="scale" value="' + esc(p.scale) + '" placeholder="SCALE" title="축척 분모 (예 25 → 1/25, 비우면 자동)">' +
      '<label class="sh-chk" title="체크하면 이 쪽을 숨김(내보내기 제외)"><input type="checkbox" data-k="hidden"' + (p.hidden ? ' checked' : '') + '>숨김</label>' +
      '<label class="sh-chk" title="이번 내보내기에 포함"><input type="checkbox" data-k="export"' + (p.export !== false ? ' checked' : '') + '>내보내기</label>' +
      '<button type="button" class="btn-inline" data-act="up" title="위로"' + (i === 0 ? ' disabled' : '') + '>▲</button>' +
      '<button type="button" class="btn-inline" data-act="down" title="아래로"' + (i === cfg.pages.length - 1 ? ' disabled' : '') + '>▼</button>' +
      '<button type="button" class="btn-inline" data-act="del" title="삭제">✕</button>' +
      '</div>' + (typeof renderPageExtra === 'function' ? renderPageExtra(p) : '')
    )).join('');
    const sel = $('sh-add-type');
    if (sel && !sel.options.length) {
      Object.keys(types).forEach(t => sel.add(new Option(typeLabel(t), t)));
    }
    const cnt = $('sh-export-count');
    if (cnt) cnt.textContent = cfg.pages.filter(p => !p.hidden && p.export !== false).length + '쪽 내보내기';
  }


  const IMG_TYPES = { photos: { max: 6, label: '현장사진' }, view3d: { max: 4, label: '상담 3D' } };
  const baseName = (p) => String(p || '').split(/[\\/]/).pop();
  function renderPageExtra(p) {
    const t = IMG_TYPES[p.type];
    if (!t || p.hidden) return '';
    const imgs = p.images || [];
    const perPage = t.max;
    let h = '<div class="sh-extra" data-pid="' + esc(p.id) + '">' +
      '<div><b>' + t.label + ' 이미지 ' + imgs.length + '장</b> <span class="dim-note">쪽당 최대 ' + perPage + '장(넘치면 다음 쪽으로 자동 이어짐). ' +
      (perPage === 6 ? '1·2·4·6칸 자동 격자' : '1~4장 자동 격자') + '</span></div>';
    h += imgs.map((im, i) => (
      '<div class="sh-img"><span class="sh-no">' + (i + 1) + '</span>' +
      '<span title="' + esc(im.path) + '">' + esc(baseName(im.path)) + '</span>' +
      '<input data-ik="caption" data-idx="' + i + '" value="' + esc(im.caption) + '" placeholder="캡션">' +
      '<button type="button" class="btn-inline" data-iact="iup" data-idx="' + i + '"' + (i === 0 ? ' disabled' : '') + '>▲</button>' +
      '<button type="button" class="btn-inline" data-iact="idown" data-idx="' + i + '"' + (i === imgs.length - 1 ? ' disabled' : '') + '>▼</button>' +
      '<button type="button" class="btn-inline" data-iact="idel" data-idx="' + i + '">✕</button></div>'
    )).join('');
    h += '<div class="di-actions"><button type="button" class="btn-inline" data-iact="ifile">＋ 이미지 파일…</button>' +
      '<button type="button" class="btn-inline" data-iact="ifolder">＋ 폴더의 이미지 모두…</button>';
    if (p.type === 'view3d') {
      h += '<button type="button" class="btn-inline" data-iact="icapture">현재 화면 캡처 추가</button>' +
        '<select data-iscene="1"><option value="">장면 선택…</option>' + scenes.map((n, i) => '<option value="' + i + '">' + esc(n) + '</option>').join('') + '</select>' +
        '<button type="button" class="btn-inline" data-iact="iscene">선택한 장면 캡처 추가</button>';
    }
    h += '</div></div>';
    return h;
  }

  function addImages(pageId, paths, caption) {
    ensure();
    const p = pageById(pageId); if (!p) return;
    p.images = p.images || [];
    (paths || []).forEach(path => p.images.push({ path, caption: caption || baseName(path).replace(/\.[^.]+$/, '') }));
    persist(); render();
  }
  function imgAct(pid, act, idx, sceneSel) {
    const p = pageById(pid); if (!p) return;
    const imgs = p.images = p.images || [];
    if (act === 'iup' && idx > 0) { const [x] = imgs.splice(idx, 1); imgs.splice(idx - 1, 0, x); persist(); render(); }
    else if (act === 'idown' && idx < imgs.length - 1) { const [x] = imgs.splice(idx, 1); imgs.splice(idx + 1, 0, x); persist(); render(); }
    else if (act === 'idel') { imgs.splice(idx, 1); persist(); render(); }
    else if (act === 'ifile') kabinet.callSketchup('kabinet:sheet_pick_image', JSON.stringify({ page_id: pid }));
    else if (act === 'ifolder') kabinet.callSketchup('kabinet:sheet_pick_folder', JSON.stringify({ page_id: pid }));
    else if (act === 'icapture') kabinet.callSketchup('kabinet:sheet_capture', JSON.stringify({ page_id: pid, scene: -1, width: 1600, caption: '현재 화면' }));
    else if (act === 'iscene') {
      if (sceneSel === '' || sceneSel == null) { kabinet.setStatus('캡처할 장면을 선택하세요.', 'error'); return; }
      kabinet.callSketchup('kabinet:sheet_capture', JSON.stringify({ page_id: pid, scene: parseInt(sceneSel, 10), width: 1600, caption: scenes[parseInt(sceneSel, 10)] || '' }));
    }
  }

  function pageById(id) { return cfg.pages.find(p => p.id === id); }
  function indexOf(id) { return cfg.pages.findIndex(p => p.id === id); }
  function move(id, delta) {
    const i = indexOf(id); const j = i + delta;
    if (i < 0 || j < 0 || j >= cfg.pages.length) return;
    const [p] = cfg.pages.splice(i, 1); cfg.pages.splice(j, 0, p);
    persist(); render();
  }
  function moveTo(id, targetId) {
    const i = indexOf(id); let j = indexOf(targetId);
    if (i < 0 || j < 0 || i === j) return;
    const [p] = cfg.pages.splice(i, 1); cfg.pages.splice(j, 0, p);
    persist(); render();
  }
  function remove(id) {
    const i = indexOf(id); if (i < 0) return;
    cfg.pages.splice(i, 1);
    persist(); render();
  }
  function add(type) {
    ensure();
    type = type || ($('sh-add-type') || {}).value || 'furniture';
    const title = typeLabel(type).replace(/ \(.*\)$/, '');
    cfg.pages.push({ id: newId(), type, title, subject: title, sheet_no: '', scale: '', hidden: false, export: true, images: [] });
    persist(); render();
  }
  function resetPages() {
    ensure();
    cfg.pages = defaultConfig().pages;
    persist(); render();
  }

  function onField(key, value) { ensure(); cfg[key] = value; persist(); }

  function bind() {
    const list = $('sh-pages');
    if (!list) return;
    list.addEventListener('input', (e) => {
      const row = e.target.closest('.sh-row'); if (!row) return;
      const p = pageById(row.dataset.id); const k = e.target.dataset.k; if (!p || !k) return;
      if (e.target.type === 'checkbox') return;
      p[k] = e.target.value; if (k === 'subject') p.title = e.target.value;
      persist();
    });
    list.addEventListener('change', (e) => {
      const row = e.target.closest('.sh-row'); if (!row) return;
      const p = pageById(row.dataset.id); const k = e.target.dataset.k; if (!p || !k) return;
      if (e.target.type === 'checkbox') { p[k] = e.target.checked; persist(); render(); }
    });
    list.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-act]'); if (!b) return;
      const row = b.closest('.sh-row'); const id = row && row.dataset.id; if (!id) return;
      if (b.dataset.act === 'up') move(id, -1);
      else if (b.dataset.act === 'down') move(id, 1);
      else if (b.dataset.act === 'del') remove(id);
    });
    list.addEventListener('input', (e) => {
      const ex = e.target.closest('.sh-extra');
      if (ex && e.target.dataset.ik) {
        const p = pageById(ex.dataset.pid); const im = p && p.images[parseInt(e.target.dataset.idx, 10)];
        if (im) { im.caption = e.target.value; persist(); }
      }
    });
    list.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-iact]'); if (!b) return;
      const ex = b.closest('.sh-extra'); if (!ex) return;
      const sel = ex.querySelector('select[data-iscene]');
      imgAct(ex.dataset.pid, b.dataset.iact, parseInt(b.dataset.idx, 10), sel ? sel.value : null);
    });
    list.addEventListener('dragstart', (e) => {
      const row = e.target.closest && e.target.closest('.sh-row'); if (!row) return;
      dragId = row.dataset.id; row.classList.add('dragging');
      if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; try { e.dataTransfer.setData('text/plain', dragId); } catch (x) {} }
    });
    list.addEventListener('dragover', (e) => { if (dragId) e.preventDefault(); });
    list.addEventListener('drop', (e) => {
      const row = e.target.closest && e.target.closest('.sh-row');
      if (dragId && row) { e.preventDefault(); moveTo(dragId, row.dataset.id); }
      dragId = null;
    });
    list.addEventListener('dragend', () => { dragId = null; list.querySelectorAll('.dragging').forEach(r => r.classList.remove('dragging')); });
  }

  function exportDxf() {
    ensure();
    const ids = cfg.pages.filter(p => !p.hidden && p.export !== false).map(p => p.id);
    if (!ids.length) { kabinet.setStatus('내보낼 페이지가 없습니다 (숨김/내보내기 체크 확인).', 'error'); return; }
    kabinet.setStatus('도면 시트 DXF 만드는 중…', '');
    kabinet.callSketchup('kabinet:sheet_export', JSON.stringify({ config: cfg, page_ids: ids }));
  }

  // 입력 CAD 도면(DXF) → 이 양식의 시트 DXF 재구성 (Ruby: Output::Sheet::DxfImport)
  function importCad() {
    ensure();
    kabinet.setStatus('CAD 도면 DXF 읽는 중…', '');
    kabinet.callSketchup('kabinet:sheet_import_cad', JSON.stringify({ config: cfg }));
  }

  document.addEventListener('DOMContentLoaded', bind);
  if (document.readyState !== 'loading') bind();

  return { open, setState, addImages, render, add, resetPages, move, moveTo, remove, onField, exportDxf, importCad,
           getConfig: () => { ensure(); return cfg; }, _persist: persist, _pageById: (id) => pageById(id) };
})();

window.kabinetSheet = kabinetSheet;
