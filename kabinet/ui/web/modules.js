/* =====================================================================
   Kabinet — Module list renderer (modules.js)
   Renders the module card list inside #module-list.
   Depends on app.js (kabinet.getState / kabinet.removeModule / kabinet.moveModule).
   ===================================================================== */

function renderModuleList() {
  const state = kabinet.getState();
  const el = document.getElementById('module-list');
  if (!el) return;

  if (state.modules.length === 0) {
    el.innerHTML = '<p style="color:var(--text-dim);font-size:12px;padding:12px 0">' +
                   '아래 버튼으로 모듈을 추가하세요.</p>';
    return;
  }

  el.innerHTML = state.modules.map((m, i) => moduleCardHtml(m, i, state.modules.length)).join('');

  // Wire up collapse toggles
  el.querySelectorAll('.module-card-header').forEach(header => {
    header.addEventListener('click', e => {
      if (e.target.closest('button')) return;  // let buttons through
      const body = header.nextElementSibling;
      body.classList.toggle('collapsed');
    });
  });

  // Wire up inputs inside cards
  el.querySelectorAll('[data-mod-idx]').forEach(input => {
    input.addEventListener('change', e => syncModuleField(e.target));
    input.addEventListener('input',  e => syncModuleField(e.target));
  });
}

function moduleCardHtml(m, i, total) {
  const title = m.kind === 'drawer_module' ? '서랍 모듈' : '선반/수납 모듈';
  const summary = `${m.width}×${m.depth}×${m.height}mm`;
  const upBtn   = i > 0
    ? `<button class="btn-icon" title="위로" onclick="kabinet.moveModule(${i},-1);event.stopPropagation()">↑</button>` : '';
  const downBtn = i < total - 1
    ? `<button class="btn-icon" title="아래로" onclick="kabinet.moveModule(${i},1);event.stopPropagation()">↓</button>` : '';

  return `
<div class="module-card">
  <div class="module-card-header">
    <span class="drag-handle">⠿</span>
    <span class="mod-title">${i+1}. ${title}</span>
    <span class="mod-summary">${summary}</span>
    ${upBtn}${downBtn}
    <button class="btn-icon danger" title="삭제"
            onclick="kabinet.removeModule(${i});event.stopPropagation()">✕</button>
  </div>
  <div class="module-card-body">
    ${commonFields(m, i)}
    ${m.kind === 'drawer_module' ? drawerFields(m, i) : shelfFields(m, i)}
  </div>
</div>`;
}

function commonFields(m, i) {
  return `
    <div class="field-row">
      <label>폭 (Width)</label>
      <input type="number" data-mod-idx="${i}" data-key="width"
             value="${m.width}" min="100" max="3000">
      <span class="unit">mm</span>
    </div>
    <div class="field-row">
      <label>깊이 (Depth)</label>
      <input type="number" data-mod-idx="${i}" data-key="depth"
             value="${m.depth}" min="100" max="1200">
      <span class="unit">mm</span>
    </div>
    <div class="field-row">
      <label>높이 (Height)</label>
      <input type="number" data-mod-idx="${i}" data-key="height"
             value="${m.height}" min="50" max="3000">
      <span class="unit">mm</span>
    </div>
    <div class="field-row">
      <label>몸통 두께</label>
      <input type="number" data-mod-idx="${i}" data-key="body_thickness"
             value="${m.body_thickness}" min="9" max="36">
      <span class="unit">mm</span>
    </div>
    <div class="field-row">
      <label>뒷판 두께</label>
      <input type="number" data-mod-idx="${i}" data-key="back_thickness"
             value="${m.back_thickness}" min="6" max="18">
      <span class="unit">mm</span>
    </div>`;
}

function drawerFields(m, i) {
  return `
    <div class="field-row">
      <label>서랍 수</label>
      <input type="number" data-mod-idx="${i}" data-key="drawer_count"
             value="${m.drawer_count}" min="1" max="6">
      <span class="unit">개</span>
    </div>
    <div class="field-row">
      <label>슬라이드 타입</label>
      <select data-mod-idx="${i}" data-key="drawer_type">
        <option value="undermount" ${m.drawer_type === 'undermount' ? 'selected' : ''}>언더레일</option>
        <option value="side_mount" ${m.drawer_type === 'side_mount' ? 'selected' : ''}>일반 사이드</option>
      </select>
    </div>
    <div class="field-row">
      <label>전판 두께</label>
      <input type="number" data-mod-idx="${i}" data-key="drawer_thickness"
             value="${m.drawer_thickness}" min="9" max="30">
      <span class="unit">mm</span>
    </div>`;
}

function shelfFields(m, i) {
  const dcOpts = ['none','single','pair'].map(v =>
    `<option value="${v}" ${m.door_config === v ? 'selected' : ''}>` +
    ({ none:'없음', single:'단문', pair:'양개문' }[v]) + '</option>').join('');

  const shelvesList = (m.shelves || []).map((s, si) =>
    `<div class="sub-item">
       <span>선반 at ${s.height_from_bottom}mm · T${s.thickness}</span>
       <button onclick="removeShelf(${i},${si})">✕</button>
     </div>`).join('');

  const accList = (m.accessories || []).map((a, ai) => {
    const label = { hanging_rod:'옷걸이봉', system_hanger:'시스템행거', shelf_accessory:'선반 액세서리' }[a.kind] || a.kind;
    return `<div class="sub-item">
              <span>${label} at ${a.height_from_bottom}mm</span>
              <button onclick="removeAccessory(${i},${ai})">✕</button>
            </div>`;
  }).join('');

  return `
    <div class="field-row">
      <label>도어 구성</label>
      <select data-mod-idx="${i}" data-key="door_config">${dcOpts}</select>
    </div>
    <div class="field-row">
      <label>도어 두께</label>
      <input type="number" data-mod-idx="${i}" data-key="door_thickness"
             value="${m.door_thickness}" min="9" max="30">
      <span class="unit">mm</span>
    </div>

    <div class="sub-list">
      <div class="sub-list-title">내부 선반</div>
      <div id="shelves-${i}">${shelvesList || '<span style="color:var(--text-dim);font-size:11px">없음</span>'}</div>
      <button class="btn-add" style="margin-top:4px" onclick="promptAddShelf(${i})">＋ 선반 추가</button>
    </div>

    <div class="sub-list">
      <div class="sub-list-title">액세서리</div>
      <div id="accs-${i}">${accList || '<span style="color:var(--text-dim);font-size:11px">없음</span>'}</div>
      <div style="display:flex;gap:4px;margin-top:4px">
        <button class="btn-add" onclick="promptAddAccessory(${i},'hanging_rod')">옷걸이봉</button>
        <button class="btn-add" onclick="promptAddAccessory(${i},'system_hanger')">행거</button>
        <button class="btn-add" onclick="promptAddAccessory(${i},'shelf_accessory')">선반</button>
      </div>
    </div>`;
}

// ── Sync a changed input into state ─────────────────────────────────────
function syncModuleField(el) {
  const idx = parseInt(el.dataset.modIdx);
  const key = el.dataset.key;
  const state = kabinet.getState();
  if (isNaN(idx) || !key || !state.modules[idx]) return;
  const val = el.type === 'number' ? +el.value : el.value;
  state.modules[idx][key] = val;
  // Update summary in header
  const card = el.closest('.module-card');
  if (card) {
    const m = state.modules[idx];
    const summary = card.querySelector('.mod-summary');
    if (summary) summary.textContent = `${m.width}×${m.depth}×${m.height}mm`;
  }
}

// ── Shelf CRUD ───────────────────────────────────────────────────────────
function promptAddShelf(modIdx) {
  const hStr = prompt('선반 높이 (바닥에서, mm):', '200');
  if (!hStr) return;
  const tStr = prompt('선반 두께 (mm):', '18');
  const state = kabinet.getState();
  const m = state.modules[modIdx];
  if (!m.shelves) m.shelves = [];
  m.shelves.push({
    height_from_bottom: parseFloat(hStr) || 200,
    thickness: parseFloat(tStr) || 18,
    depth_inset: 20
  });
  renderModuleList();
}

function removeShelf(modIdx, shelfIdx) {
  const state = kabinet.getState();
  state.modules[modIdx].shelves.splice(shelfIdx, 1);
  renderModuleList();
}

// ── Accessory CRUD ───────────────────────────────────────────────────────
function promptAddAccessory(modIdx, kind) {
  const hStr = prompt('설치 높이 (바닥에서, mm):', '300');
  if (!hStr) return;
  const state = kabinet.getState();
  const m = state.modules[modIdx];
  if (!m.accessories) m.accessories = [];
  const acc = { kind, height_from_bottom: parseFloat(hStr) || 300 };
  if (kind === 'hanging_rod') {
    acc.diameter   = 32;
    acc.depth_inset = 75;
  } else if (kind === 'system_hanger') {
    acc.rail_height    = 30;
    acc.rail_thickness = 5;
  } else if (kind === 'shelf_accessory') {
    acc.thickness  = 18;
    acc.depth_inset = 20;
  }
  m.accessories.push(acc);
  renderModuleList();
}

function removeAccessory(modIdx, accIdx) {
  const state = kabinet.getState();
  state.modules[modIdx].accessories.splice(accIdx, 1);
  renderModuleList();
}
