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

  document.addEventListener('DOMContentLoaded', bind);
  if (document.readyState !== 'loading') bind();

  return { open, setState, render, add, resetPages, move, moveTo, remove, onField, exportDxf,
           getConfig: () => { ensure(); return cfg; }, _persist: persist, _pageById: (id) => pageById(id) };
})();

window.kabinetSheet = kabinetSheet;
