/* =====================================================================
   도면 치수표 → 3D 가구
   한 줄 = 가구 하나: 프리셋(구조) + 치수·위치. 생성은 SketchUp(kabinet:drawing_import).
   ===================================================================== */
const kabinetDrawingImport = (() => {
  const STORE = 'kabinet.drawingImportRows';
  // 도면 예시 — 오톤도 30X33_2550 (폭 3400 방): 왼쪽 붙박이장 · 책상 · 상부장 3칸 · 낮은 오픈장/서랍장
  const EXAMPLE = [
    { preset: 'otondo_tall',         name: '붙박이장',     x: 0,    y: 0,   z: 0,    width: 1082, height: 2550, depth: 600 },
    { preset: 'otondo_desk',         name: '책상',         x: 1082, y: 0,   z: 0,    width: 1768, height: 720,  depth: 600 },
    { preset: 'otondo_upper_pair',   name: '상부장 양개',  x: 1082, y: 0,   z: 1579, width: 1120, height: 971,  depth: 350 },
    { preset: 'otondo_upper_single', name: '상부장 단문',  x: 2202, y: 0,   z: 1579, width: 560,  height: 971,  depth: 350 },
    { preset: 'otondo_low_open',     name: '낮은 오픈장',  x: 0,    y: 900, z: 0,    width: 1182, height: 700,  depth: 400 },
    { preset: 'otondo_low_drawer',   name: '낮은 서랍장',  x: 1300, y: 900, z: 0,    width: 750,  height: 270,  depth: 400 }
  ];
  let rows = [];

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const num = (v) => { const n = parseFloat(v); return isFinite(n) ? n : 0; };

  function save() { try { localStorage.setItem(STORE, JSON.stringify(rows)); } catch (e) {} }
  function load() {
    try { const r = JSON.parse(localStorage.getItem(STORE) || '[]'); if (Array.isArray(r)) rows = r; } catch (e) { rows = []; }
  }

  function presetOptions(cur) {
    const sel = document.getElementById('f-furniture-type');
    let html = '<option value="">가구 종류…</option>';
    if (!sel) return html;
    Array.from(sel.querySelectorAll('optgroup')).forEach(g => {
      if (g.id === 'user-preset-group') return;
      const opts = Array.from(g.querySelectorAll('option'));
      if (!opts.length) return;
      html += '<optgroup label="' + esc(g.label.replace(/^[─\s]+/, '')) + '">' +
        opts.map(o => '<option value="' + esc(o.value) + '"' + (o.value === cur ? ' selected' : '') + '>' + esc(o.textContent) + '</option>').join('') +
        '</optgroup>';
    });
    return html;
  }

  const FIELDS = [['name', '이름', 'text', 90], ['x', 'X', 'number', 62], ['y', 'Y', 'number', 56], ['z', '바닥', 'number', 56],
                  ['width', '폭', 'number', 62], ['height', '높이', 'number', 62], ['depth', '깊이', 'number', 56]];

  function render() {
    const t = $('di-table');
    if (!t) return;
    let h = '<thead><tr><th>가구 종류</th>' + FIELDS.map(f => '<th>' + f[1] + '</th>').join('') +
            '<th>방향</th><th>두께</th><th>도어</th><th>서랍</th><th></th></tr></thead><tbody>';
    rows.forEach((r, i) => {
      h += '<tr><td><select data-i="' + i + '" data-k="preset">' + presetOptions(r.preset) + '</select></td>' +
        FIELDS.map(f => '<td><input data-i="' + i + '" data-k="' + f[0] + '" type="' + f[2] + '" style="width:' + f[3] + 'px" value="' + esc(r[f[0]]) + '"></td>').join('') +
        '<td><select data-i="' + i + '" data-k="rot">' + [0, 90, 180, 270].map(d => '<option value="' + d + '"' + ((+r.rot || 0) === d ? ' selected' : '') + '>' + d + '°</option>').join('') + '</select></td>' +
        '<td><input data-i="' + i + '" data-k="thickness" type="number" style="width:46px" placeholder="18" value="' + esc(r.thickness == null ? 18 : r.thickness) + '"></td>' +
        '<td><select data-i="' + i + '" data-k="doors">' + [['', '유지'], ['none', '없음'], ['single', '단문'], ['pair', '양개']].map(([v, l]) => '<option value="' + v + '"' + ((r.doors || '') === v ? ' selected' : '') + '>' + l + '</option>').join('') + '</select></td>' +
        '<td><input data-i="' + i + '" data-k="drawers" type="number" style="width:44px" min="0" value="' + esc(r.drawers) + '"></td>' +
        '<td><button type="button" class="btn-inline" data-fill="' + i + '" title="프리셋의 폭·높이·깊이로 채우기">채움</button>' +
        '<button type="button" class="btn-inline" data-del="' + i + '" title="이 줄 삭제">✕</button></td></tr>';
    });
    t.innerHTML = h + '</tbody>';
  }

  function onChange(e) {
    const el = e.target;
    if (el.dataset.k === undefined) return;
    const r = rows[+el.dataset.i];
    if (!r) return;
    r[el.dataset.k] = el.type === 'number' ? (el.value === '' ? '' : +el.value) : el.value;
    save();
    if (el.dataset.k === 'preset' && !r.name) { r.name = ''; }
  }

  function presetTotals(key) {
    const p = (typeof FURNITURE_PRESETS !== 'undefined') ? FURNITURE_PRESETS[key] : null;
    if (!p) return null;
    // 런 모드는 모듈이 가로로 나열되므로 높이는 run_height 하나, 아니면 모듈 높이 합(세로 적층)
    const mods = p.run_mode ? (+p.run_height || 0)
      : (p.modules || []).reduce((a, m) => a + (m.kind === 'bed_gap' ? 0 : (+m.height || 0)), 0);
    const epTop = p.ep && p.ep.top ? (+p.ep.thickness || 0) : 0;
    const total = (+p.base_height || 0) + mods + (p.top_panel ? (+p.top_panel.thickness || 0) : 0) + epTop;
    return { width: p.width, height: Math.round(total), depth: p.max_depth };
  }

  function onClick(e) {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.del !== undefined) { rows.splice(+b.dataset.del, 1); save(); render(); }
    else if (b.dataset.fill !== undefined) {
      const r = rows[+b.dataset.fill]; const t = r && presetTotals(r.preset);
      if (!t) return status('먼저 가구 종류를 고르세요.', true);
      Object.assign(r, t); save(); render();
    }
  }

  function status(msg, err) {
    const el = $('di-status');
    if (el) { el.textContent = msg; el.style.color = err ? 'var(--error, #e55)' : ''; }
    if (window.kabinet) kabinet.setStatus(msg, err ? 'error' : 'ok');
  }

  function addRow(r) {
    rows.push(Object.assign({ preset: '', name: '', x: 0, y: 0, z: 0, width: '', height: '', depth: '', rot: 0, thickness: 18, doors: '', drawers: '' }, r || {}));
    save(); render();
  }
  function clearRows() { rows = []; save(); render(); }
  function loadExample() {
    rows = EXAMPLE.map(r => Object.assign({ rot: 0, thickness: 18, doors: '', drawers: '' }, r));
    save(); render();
    status('도면 예시 6줄을 불러왔습니다. 값을 고치거나 그대로 생성하세요.');
  }

  // Claude 가 도면(PDF·DWG·DXF)에서 읽어 준 JSON 표를 붙여넣어 한 번에 불러오기.
  // 형식: [{preset,name,x,y,z,width,height,depth,rot,thickness,doors,drawers}, …] 또는 {rows:[…]}
  function importJson() {
    const el = $('di-json');
    let data;
    try { data = JSON.parse((el && el.value || '').trim()); } catch (e) { return status('JSON 형식이 올바르지 않습니다: ' + e.message, true); }
    const list = Array.isArray(data) ? data : (data && Array.isArray(data.rows) ? data.rows : null);
    if (!list || !list.length) return status('가구 목록([...])이 비어 있습니다.', true);
    const presets = (typeof FURNITURE_PRESETS !== 'undefined') ? FURNITURE_PRESETS : {};
    const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
    const bad = list.findIndex(r => !r || typeof r.preset !== 'string' || !own(presets, r.preset));
    if (bad >= 0) return status((bad + 1) + '번째 줄: 알 수 없는 가구 종류(preset) "' + (list[bad] && list[bad].preset) + '"', true);
    rows = list.map(r => Object.assign({ name: '', x: 0, y: 0, z: 0, width: '', height: '', depth: '', rot: 0, thickness: 18, doors: '', drawers: '' }, r));
    save(); render();
    status('표 ' + rows.length + '줄을 불러왔습니다. 확인한 뒤 "모델에 모두 생성"을 누르세요.');
  }

  function generateAll() {
    if (!rows.length) return status('가구를 한 줄 이상 입력하세요.', true);
    const items = [];
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      const res = kabinet.buildDrawingSpec(r);
      if (res.error) return status((i + 1) + '번째 줄: ' + res.error, true);
      items.push({ spec: res.spec, x: num(r.x), y: num(r.y), z: num(r.z), rot: num(r.rot) });
    }
    status('가구 ' + items.length + '개를 만드는 중…');
    kabinet.callSketchup('kabinet:drawing_import', JSON.stringify({ items }));
  }

  function open() {
    load();
    if (!rows.length) rows = [];
    render();
  }

  document.addEventListener('DOMContentLoaded', () => {
    const t = $('di-table');
    if (t) { t.addEventListener('change', onChange); t.addEventListener('click', onClick); }
  });

  return { open, addRow, clearRows, loadExample, importJson, generateAll };
})();
