/* =====================================================================
   Kabinet — Module list renderer (modules.js)
   ===================================================================== */

/* ── 힌지 수 계산 ────────────────────────────────────────────────────── */
function hingeCount(doorHeightMm) {
  if (doorHeightMm <= 600)  return 2;
  if (doorHeightMm <= 1200) return 3;
  if (doorHeightMm <= 1800) return 4;
  return 5;
}

/* ── 모듈 리스트 렌더링 ──────────────────────────────────────────────── */
function renderModuleList() {
  const state = kabinet.getState();
  const el    = document.getElementById('module-list');
  if (!el) return;

  if (state.modules.length === 0) {
    el.innerHTML = '<p style="color:var(--text-dim);font-size:12px;padding:12px 0">' +
                   '아래 버튼으로 모듈을 추가하세요.</p>';
    kabinet.updateHeightSummary();
    return;
  }

  el.innerHTML = state.modules
    .map((m, i) => moduleCardHtml(m, i, state.modules.length))
    .join('');

  // Collapse toggles
  el.querySelectorAll('.module-card-header').forEach(header => {
    header.addEventListener('click', e => {
      if (e.target.closest('button')) return;
      header.nextElementSibling.classList.toggle('collapsed');
    });
  });

  // Input sync
  el.querySelectorAll('[data-mod-idx]').forEach(input => {
    input.addEventListener('change', e => syncModuleField(e.target));
    input.addEventListener('input',  e => syncModuleField(e.target));
  });

  kabinet.updateHeightSummary();
}

/* ── 모듈 카드 HTML ───────────────────────────────────────────────────── */
function moduleCardHtml(m, i, total) {
  const title   = m.kind === 'drawer_module' ? '서랍 모듈' : '선반/수납 모듈';
  const summary = m.width + '×' + m.depth + '×' + m.height + 'mm';
  const upBtn   = i > 0
    ? '<button class="btn-icon" title="위로" onclick="kabinet.moveModule(' + i + ',-1);event.stopPropagation()">↑</button>' : '';
  const downBtn = i < total - 1
    ? '<button class="btn-icon" title="아래로" onclick="kabinet.moveModule(' + i + ',1);event.stopPropagation()">↓</button>' : '';

  return '<div class="module-card">' +
    '<div class="module-card-header">' +
      '<span class="drag-handle">⠿</span>' +
      '<span class="mod-title">' + (i+1) + '. ' + title + '</span>' +
      '<span class="mod-summary">' + summary + '</span>' +
      upBtn + downBtn +
      '<button class="btn-icon danger" title="삭제" ' +
        'onclick="kabinet.removeModule(' + i + ');event.stopPropagation()">✕</button>' +
    '</div>' +
    '<div class="module-card-body">' +
      commonFields(m, i) +
      (m.kind === 'drawer_module' ? drawerFields(m, i) : shelfFields(m, i)) +
    '</div>' +
  '</div>';
}

/* ── 공통 필드 ──────────────────────────────────────────────────────── */
function commonFields(m, i) {
  const matOpts = [
    ['LPM','LPM (저압 멜라민)'],['PET','PET'],['UV_gloss','UV 도장'],
    ['acrylic','아크릴'],['high_gloss','하이그로시'],['phenix','페닉스'],
    ['HPL','HPL'],['MDF_paint','MDF 도장'],['plywood','합판'],['solid_wood','집성목']
  ].map(([v, l]) =>
    '<option value="' + v + '"' + (m.material === v ? ' selected' : '') + '>' + l + '</option>'
  ).join('');

  return '<div class="field-row">' +
      '<label>폭</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="width" ' +
             'value="' + m.width + '" min="100" max="3000">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row">' +
      '<label>깊이</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="depth" ' +
             'value="' + m.depth + '" min="100" max="1200">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row">' +
      '<label>높이</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="height" ' +
             'value="' + m.height + '" min="50" max="3000">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row">' +
      '<label>몸통 두께</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="body_thickness" ' +
             'value="' + m.body_thickness + '" min="9" max="36">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row">' +
      '<label>뒷판 두께</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="back_thickness" ' +
             'value="' + m.back_thickness + '" min="6" max="18">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row">' +
      '<label>소재</label>' +
      '<select data-mod-idx="' + i + '" data-key="material">' + matOpts + '</select></div>';
}

/* ── 서랍 모듈 필드 ─────────────────────────────────────────────────── */
function drawerFields(m, i) {
  const handleOpts = handleOptions(m.handle_type);

  // 서랍 전판 예상 높이
  const bt   = m.body_thickness || 18;
  const dc   = m.drawer_count  || 1;
  const openH = m.height - 2 * bt;
  const frontH = Math.round((openH - 4 - 3 * (dc - 1)) / dc);

  return '<div class="field-row">' +
      '<label>서랍 수</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="drawer_count" ' +
             'value="' + (m.drawer_count||1) + '" min="1" max="6">' +
      '<span class="unit">개</span></div>' +
    '<div class="field-row">' +
      '<label>슬라이드 타입</label>' +
      '<select data-mod-idx="' + i + '" data-key="drawer_type">' +
        '<option value="undermount"' + (m.drawer_type==='undermount'?' selected':'') + '>언더레일 (Blum)</option>' +
        '<option value="side_mount"' + (m.drawer_type==='side_mount'?' selected':'') + '>사이드마운트</option>' +
      '</select></div>' +
    '<div class="field-row">' +
      '<label>전판 두께</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="drawer_thickness" ' +
             'value="' + (m.drawer_thickness||18) + '" min="9" max="30">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row">' +
      '<label>손잡이</label>' +
      '<select data-mod-idx="' + i + '" data-key="handle_type">' + handleOpts + '</select></div>' +
    '<div class="calc-info">📐 전판 높이 약 <strong>' + frontH + 'mm</strong> × ' + dc + '개</div>';
}

/* ── 선반/수납 모듈 필드 ─────────────────────────────────────────────── */
function shelfFields(m, i) {
  const dcOpts = ['none','single','pair'].map(v =>
    '<option value="' + v + '"' + (m.door_config===v?' selected':'') + '>' +
    ({none:'없음', single:'단문', pair:'양개문'}[v]) + '</option>').join('');

  const dtOpts = [
    ['swing','여닫이 (Swing)'],
    ['sliding','미닫이 (Sliding)'],
    ['folding','접이식 (Folding)'],
    ['lift_up','리프트업 (Lift-Up)'],
    ['none','없음']
  ].map(([v,l]) =>
    '<option value="' + v + '"' + ((m.door_type||'swing')===v?' selected':'') + '>' + l + '</option>'
  ).join('');

  const handleOpts = handleOptions(m.handle_type);

  // 힌지 정보
  const dc        = m.door_config || 'none';
  const doorH     = m.height - 4;   // gap_top(2) + gap_bottom(2)
  const hingeN    = dc !== 'none' ? hingeCount(doorH) : 0;
  const hingeInfo = dc !== 'none'
    ? '경첩 ' + hingeN + '개 (도어 높이 ' + doorH + 'mm 기준)'
    : '도어 없음';

  const shelvesList = (m.shelves || []).map((s, si) =>
    '<div class="sub-item">' +
      '<span>선반 at ' + s.height_from_bottom + 'mm · T' + s.thickness + '</span>' +
      '<button onclick="removeShelf(' + i + ',' + si + ')">✕</button>' +
    '</div>').join('');

  const accList = (m.accessories || []).map((a, ai) => {
    const label = {
      hanging_rod: '옷걸이봉', system_hanger: '시스템행거', shelf_accessory: '선반 액세서리'
    }[a.kind] || a.kind;
    return '<div class="sub-item">' +
             '<span>' + label + ' at ' + a.height_from_bottom + 'mm</span>' +
             '<button onclick="removeAccessory(' + i + ',' + ai + ')">✕</button>' +
           '</div>';
  }).join('');

  return '<div class="field-row">' +
      '<label>도어 구성</label>' +
      '<select data-mod-idx="' + i + '" data-key="door_config">' + dcOpts + '</select></div>' +
    '<div class="field-row">' +
      '<label>도어 타입</label>' +
      '<select data-mod-idx="' + i + '" data-key="door_type">' + dtOpts + '</select></div>' +
    '<div class="field-row">' +
      '<label>도어 두께</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="door_thickness" ' +
             'value="' + (m.door_thickness||18) + '" min="9" max="30">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row">' +
      '<label>손잡이</label>' +
      '<select data-mod-idx="' + i + '" data-key="handle_type">' + handleOpts + '</select></div>' +
    '<div class="calc-info">🔩 ' + hingeInfo + '</div>' +

    '<div class="sub-list">' +
      '<div class="sub-list-title">내부 선반</div>' +
      '<div id="shelves-' + i + '">' +
        (shelvesList || '<span style="color:var(--text-dim);font-size:11px">없음</span>') +
      '</div>' +
      '<button class="btn-add" style="margin-top:4px" onclick="promptAddShelf(' + i + ')">＋ 선반 추가</button>' +
    '</div>' +

    '<div class="sub-list">' +
      '<div class="sub-list-title">액세서리</div>' +
      '<div id="accs-' + i + '">' +
        (accList || '<span style="color:var(--text-dim);font-size:11px">없음</span>') +
      '</div>' +
      '<div style="display:flex;gap:4px;margin-top:4px">' +
        '<button class="btn-add" onclick="promptAddAccessory(' + i + ',\'hanging_rod\')">옷걸이봉</button>' +
        '<button class="btn-add" onclick="promptAddAccessory(' + i + ',\'system_hanger\')">행거레일</button>' +
        '<button class="btn-add" onclick="promptAddAccessory(' + i + ',\'shelf_accessory\')">선반</button>' +
      '</div>' +
    '</div>';
}

/* ── 손잡이 옵션 HTML ─────────────────────────────────────────────────── */
function handleOptions(current) {
  const types = [
    ['none',       '없음'],
    ['bar',        '바 핸들 (Bar)'],
    ['knob',       '원형 손잡이 (Knob)'],
    ['cup_pull',   '컵 풀 (Cup Pull)'],
    ['channel',    '채널 (Handleless)'],
    ['push_open',  '푸시 오픈']
  ];
  return types.map(([v, l]) =>
    '<option value="' + v + '"' + ((current || 'none') === v ? ' selected' : '') + '>' + l + '</option>'
  ).join('');
}

/* ── 필드 sync ───────────────────────────────────────────────────────── */
function syncModuleField(el) {
  const idx   = parseInt(el.dataset.modIdx);
  const key   = el.dataset.key;
  const state = kabinet.getState();
  if (isNaN(idx) || !key || !state.modules[idx]) return;

  const val = el.type === 'number' ? +el.value : el.value;
  state.modules[idx][key] = val;

  // Update summary in card header
  const card = el.closest('.module-card');
  if (card) {
    const m       = state.modules[idx];
    const summary = card.querySelector('.mod-summary');
    if (summary) summary.textContent = m.width + '×' + m.depth + '×' + m.height + 'mm';
  }

  // Refresh height-sensitive displays
  if (key === 'height' || key === 'door_config') {
    kabinet.updateTotalHeight();
    kabinet.updateHeightSummary();
    // Re-render if door_config changed (hinge count changes)
    if (key === 'door_config') renderModuleList();
  }
}

/* ── 선반 CRUD ──────────────────────────────────────────────────────── */
function promptAddShelf(modIdx) {
  const hStr = prompt('선반 높이 (바닥에서, mm):', '200');
  if (!hStr) return;
  const tStr = prompt('선반 두께 (mm):', '18');
  const state = kabinet.getState();
  const m     = state.modules[modIdx];
  if (!m.shelves) m.shelves = [];
  m.shelves.push({
    height_from_bottom: parseFloat(hStr) || 200,
    thickness:          parseFloat(tStr) || 18,
    depth_inset:        20
  });
  renderModuleList();
}

function removeShelf(modIdx, shelfIdx) {
  kabinet.getState().modules[modIdx].shelves.splice(shelfIdx, 1);
  renderModuleList();
}

/* ── 액세서리 CRUD ──────────────────────────────────────────────────── */
function promptAddAccessory(modIdx, kind) {
  const hStr = prompt('설치 높이 (바닥에서, mm):', kind === 'hanging_rod' ? '950' : '300');
  if (!hStr) return;
  const state = kabinet.getState();
  const m     = state.modules[modIdx];
  if (!m.accessories) m.accessories = [];
  const acc = { kind, height_from_bottom: parseFloat(hStr) || 300 };
  if (kind === 'hanging_rod') {
    acc.diameter    = 32;
    acc.depth_inset = 75;
  } else if (kind === 'system_hanger') {
    acc.rail_height    = 30;
    acc.rail_thickness = 5;
  } else if (kind === 'shelf_accessory') {
    acc.thickness   = 18;
    acc.depth_inset = 20;
  }
  m.accessories.push(acc);
  renderModuleList();
}

function removeAccessory(modIdx, accIdx) {
  kabinet.getState().modules[modIdx].accessories.splice(accIdx, 1);
  renderModuleList();
}
