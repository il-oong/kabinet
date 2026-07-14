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
  const state = kabinet.getState();
  const isRun = !!state.run_mode;

  const TITLES = {
    drawer_module: isRun ? '서랍 섹션'   : '서랍 모듈',
    shelf_module:  isRun ? '선반/수납 섹션' : '선반/수납 모듈',
    desk_module:   '책상 모듈',
    bed_gap:       '🛏 침대 공간'
  };
  const title   = TITLES[m.kind] || m.kind;
  const runH    = state.run_height || 740;
  const dispH   = isRun ? runH : (m.height || 0);
  let summary;
  if (m.kind === 'bed_gap') {
    summary = (m.label || '침대 공간') + ' ' + m.width + 'mm';
  } else if (m.kind === 'shelf_module') {
    const dcLabel = {none:'오픈', single:'단문', pair:'양개'}[m.door_config || 'none'] || '';
    summary = m.width + '×' + (m.depth || '?') + '×' + dispH + 'mm' + (dcLabel ? '  ' + dcLabel : '');
  } else if (m.kind === 'drawer_module') {
    summary = m.width + '×' + (m.depth || '?') + '×' + dispH + 'mm  서랍 ' + (m.drawer_count || 1) + '단';
  } else {
    summary = m.width + '×' + (m.depth || '?') + '×' + dispH + 'mm';
  }

  const upBtn   = i > 0
    ? '<button class="btn-icon" title="위로" onclick="kabinet.moveModule(' + i + ',-1);event.stopPropagation()">↑</button>' : '';
  const downBtn = i < total - 1
    ? '<button class="btn-icon" title="아래로" onclick="kabinet.moveModule(' + i + ',1);event.stopPropagation()">↓</button>' : '';

  let bodyHtml;
  if (m.kind === 'bed_gap') {
    bodyHtml = bedGapFields(m, i);
  } else if (m.kind === 'desk_module') {
    bodyHtml = deskFields(m, i);
  } else if (m.kind === 'drawer_module') {
    bodyHtml = commonFields(m, i) + drawerFields(m, i);
  } else {
    bodyHtml = commonFields(m, i) + shelfFields(m, i);
  }

  return '<div class="module-card">' +
    '<div class="module-card-header">' +
      '<span class="drag-handle">⠿</span>' +
      '<span class="mod-title">' + (i+1) + '. ' + title + '</span>' +
      '<span class="mod-summary">' + summary + '</span>' +
      upBtn + downBtn +
      '<button class="btn-icon danger" title="삭제" ' +
        'onclick="kabinet.removeModule(' + i + ');event.stopPropagation()">✕</button>' +
    '</div>' +
    '<div class="module-card-body">' + bodyHtml + '</div>' +
  '</div>';
}

/* ── 공통 필드 (W / D / H 주요치수 + 세부치수 접이) ─────────────────── */
function commonFields(m, i) {
  const state = kabinet.getState();
  const isRun = !!state.run_mode;
  const runH  = state.run_height || 740;

  const matOpts = [
    ['LPM','LPM (저압 멜라민)'],['PET','PET'],['UV_gloss','UV 도장'],
    ['acrylic','아크릴'],['high_gloss','하이그로시'],['phenix','페닉스'],
    ['HPL','HPL'],['MDF_paint','MDF 도장'],['plywood','합판'],['solid_wood','집성목']
  ].map(([v, l]) =>
    '<option value="' + v + '"' + (m.material === v ? ' selected' : '') + '>' + l + '</option>'
  ).join('');

  const heightField = isRun
    ? '<div class="field-row"><label>높이</label>' +
        '<input type="number" value="' + runH + '" disabled style="opacity:0.5">' +
        '<span class="unit">mm (런 공통)</span></div>'
    : '<div class="field-row"><label>높이</label>' +
        '<input type="number" data-mod-idx="' + i + '" data-key="height" ' +
               'value="' + m.height + '" min="50" max="3000">' +
        '<span class="unit">mm</span></div>';

  // ── 주요 치수 (항상 표시) ─────────────────────────────────────────
  const mainBlock =
    '<div class="main-fields">' +
      '<div class="field-row">' +
        '<label>' + (isRun ? '섹션 폭' : '폭') + '</label>' +
        '<input type="number" data-mod-idx="' + i + '" data-key="width" ' +
               'value="' + m.width + '" min="100" max="3000">' +
        '<span class="unit">mm</span></div>' +
      '<div class="field-row"><label>깊이</label>' +
        '<input type="number" data-mod-idx="' + i + '" data-key="depth" ' +
               'value="' + m.depth + '" min="100" max="1200">' +
        '<span class="unit">mm</span></div>' +
      heightField +
    '</div>';

  // ── 세부 치수 (접이) ────────────────────────────────────────────────
  const detailBlock =
    '<details><summary class="detail-summary">세부 치수 / 소재</summary>' +
      '<div class="field-row"><label>몸통 두께</label>' +
        '<input type="number" data-mod-idx="' + i + '" data-key="body_thickness" ' +
               'value="' + m.body_thickness + '" min="9" max="36">' +
        '<span class="unit">mm</span></div>' +
      '<div class="field-row"><label>뒷판 두께</label>' +
        '<input type="number" data-mod-idx="' + i + '" data-key="back_thickness" ' +
               'value="' + m.back_thickness + '" min="6" max="18">' +
        '<span class="unit">mm</span></div>' +
      '<div class="field-row"><label>소재</label>' +
        '<select data-mod-idx="' + i + '" data-key="material">' + matOpts + '</select></div>' +
    '</details>';

  return mainBlock + detailBlock;
}

/* ── 서랍 모듈 필드 ─────────────────────────────────────────────────── */
function drawerFields(m, i) {
  const handleOpts = handleOptions(m.handle_type);
  const bt     = m.body_thickness || 18;
  const dc     = m.drawer_count  || 1;
  const openH  = m.height - 2 * bt;
  const frontH = Math.round((openH - 4 - 3 * (dc - 1)) / dc);
  const showHole = (m.handle_type === 'bar');

  // ── 주요 설정 (항상 표시)
  const mainBlock =
    '<div class="main-fields">' +
      '<div class="field-row"><label>서랍 수</label>' +
        '<input type="number" data-mod-idx="' + i + '" data-key="drawer_count" ' +
               'value="' + (m.drawer_count||1) + '" min="1" max="6">' +
        '<span class="unit">개</span></div>' +
      '<div class="calc-info" style="margin:0;font-size:11px;color:var(--text-dim)">' +
        '전판 높이 약 ' + frontH + 'mm × ' + dc + '개' +
      '</div>' +
    '</div>';

  // ── 서랍 세부 (접이)
  const detailBlock =
    '<details><summary class="detail-summary">서랍 세부 옵션</summary>' +
      '<div class="field-row"><label>슬라이드 타입</label>' +
        '<select data-mod-idx="' + i + '" data-key="drawer_type">' +
          '<option value="undermount"' + (m.drawer_type==='undermount'?' selected':'') + '>언더레일 (Blum)</option>' +
          '<option value="side_mount"' + (m.drawer_type==='side_mount'?' selected':'') + '>사이드마운트</option>' +
        '</select></div>' +
      '<div class="field-row"><label>전판 두께</label>' +
        '<input type="number" data-mod-idx="' + i + '" data-key="drawer_thickness" ' +
               'value="' + (m.drawer_thickness||18) + '" min="9" max="30">' +
        '<span class="unit">mm</span></div>' +
    '</details>' +
    '<details><summary class="detail-summary">손잡이</summary>' +
      '<div class="field-row"><label>손잡이 타입</label>' +
        '<select data-mod-idx="' + i + '" data-key="handle_type">' + handleOpts + '</select></div>' +
      (showHole ?
        '<div class="field-row"><label>홀간 거리</label>' +
          '<input type="number" data-mod-idx="' + i + '" data-key="handle_hole_mm" ' +
                 'value="' + (m.handle_hole_mm||128) + '" min="32" max="320">' +
          '<span class="unit">mm</span></div>' : '') +
    '</details>';

  return mainBlock + detailBlock;
}

/* ── 선반/수납 모듈 필드 ─────────────────────────────────────────────── */
function shelfFields(m, i) {
  const dcOpts = ['none','single','pair'].map(v =>
    '<option value="' + v + '"' + (m.door_config===v?' selected':'') + '>' +
    ({none:'없음 (오픈)', single:'단문 (1개)', pair:'양개문 (2개)'}[v]) + '</option>').join('');

  const dtOpts = [
    ['swing','여닫이 (Swing)'],['sliding','미닫이 (Sliding)'],
    ['folding','접이식 (Folding)'],['lift_up','리프트업 (Lift-Up)'],['none','없음']
  ].map(([v,l]) =>
    '<option value="' + v + '"' + ((m.door_type||'swing')===v?' selected':'') + '>' + l + '</option>'
  ).join('');

  const handleOpts = handleOptions(m.handle_type);
  const dc         = m.door_config || 'none';
  const hasDoor    = dc !== 'none';
  const doorH      = m.height - 4;
  const hingeN     = hasDoor ? hingeCount(doorH) : 0;
  const hingeInfo  = hasDoor ? '경첩 ' + hingeN + '개 (도어 높이 ' + doorH + 'mm)' : '오픈 선반 (도어 없음)';
  const showHole   = (m.handle_type === 'bar');

  // ── 전체폭 선반 목록
  const shelvesList = (m.shelves || []).map((s, si) =>
    '<div class="sub-item">' +
      '<span>선반 ' + s.height_from_bottom + 'mm · T' + s.thickness + '</span>' +
      '<button onclick="removeShelf(' + i + ',' + si + ')">✕</button>' +
    '</div>').join('');

  // ── 액세서리 목록
  const accList = (m.accessories || []).map((a, ai) => {
    const label = {hanging_rod:'옷걸이봉',system_hanger:'시스템행거',shelf_accessory:'선반 액세서리'}[a.kind] || a.kind;
    return '<div class="sub-item">' +
      '<span>' + label + ' at ' + a.height_from_bottom + 'mm</span>' +
      '<button onclick="removeAccessory(' + i + ',' + ai + ')">✕</button>' +
    '</div>';
  }).join('');

  // ── 세로 분할판 목록
  const divList = (m.vertical_dividers || []).map((d, di) =>
    '<div class="sub-item">' +
      '<span>분할 at ' + d.x + 'mm · T' + (d.thickness||18) + '</span>' +
      '<button onclick="removeDivider(' + i + ',' + di + ')">✕</button>' +
    '</div>').join('');

  // ── 셀 수 계산
  const cellCount = (m.vertical_dividers || []).length + 1;
  const cellLabel = cellCount === 1 ? '(분할판 없음 — 단일 칸)' : cellCount + '개 셀 (0~' + (cellCount-1) + ')';

  // ── 셀별 선반 목록
  const csLabel = (m.cell_shelves || []).map((cs, csi) =>
    '<div class="sub-item">' +
      '<span>셀' + cs.cell + ' · ' + cs.height_from_bottom + 'mm · T' + (cs.thickness||18) + '</span>' +
      '<button onclick="removeCellShelf(' + i + ',' + csi + ')">✕</button>' +
    '</div>').join('');

  // ── 셀별 서랍 목록
  const cdLabel = (m.cell_drawers || []).map((cd, cdi) =>
    '<div class="sub-item">' +
      '<span>셀' + cd.cell + ' 서랍 ' + (cd.count||2) + '개 · ' + (cd.type||'undermount') + '</span>' +
      '<button onclick="removeCellDrawer(' + i + ',' + cdi + ')">✕</button>' +
    '</div>').join('');

  // ── 도어 주요 (항상 표시) ──────────────────────────────────────────
  const doorMain =
    '<div class="main-fields">' +
      '<div class="field-row"><label>도어 구성</label>' +
        '<select data-mod-idx="' + i + '" data-key="door_config">' + dcOpts + '</select></div>' +
      (hasDoor
        ? '<div class="field-row"><label>도어 타입</label>' +
            '<select data-mod-idx="' + i + '" data-key="door_type">' + dtOpts + '</select></div>'
        : '') +
      '<div class="calc-info" style="margin:0;font-size:11px;color:var(--text-dim)">' +
        hingeInfo +
      '</div>' +
    '</div>';

  return doorMain + (

    // ── 도어 세부 설정 (접이) ──────────────────────────────────────────
    (hasDoor
      ? '<details><summary class="detail-summary">도어 세부 설정</summary>' +
          '<div class="field-row"><label>도어 장착</label>' +
            '<select data-mod-idx="' + i + '" data-key="door_mount">' +
              '<option value="overlay"' + ((m.door_mount||'overlay')==='overlay'?' selected':'') + '>오버레이 — 측판 위 덮음 (기본)</option>' +
              '<option value="inset"'   + ((m.door_mount||'overlay')==='inset'  ?' selected':'') + '>인셋 — 카케이스 내부 면일치</option>' +
            '</select></div>' +
          '<div class="field-row"><label>도어 두께</label>' +
            '<input type="number" data-mod-idx="' + i + '" data-key="door_thickness" ' +
                   'value="' + (m.door_thickness||18) + '" min="9" max="30">' +
            '<span class="unit">mm</span></div>' +
          '<div class="field-row"><label>측면 갭</label>' +
            '<input type="number" data-mod-idx="' + i + '" data-key="door_side_gap_mm" ' +
                   'value="' + (m.door_side_gap_mm != null ? m.door_side_gap_mm : 2) + '" min="0" max="5" step="0.5">' +
            '<span class="unit">mm (0=플러시)</span></div>' +
        '</details>'
      : '') +

    // ── 손잡이 (접이) ──────────────────────────────────────────────────
    (hasDoor
      ? '<details><summary class="detail-summary">손잡이</summary>' +
          '<div class="field-row"><label>손잡이 타입</label>' +
            '<select data-mod-idx="' + i + '" data-key="handle_type">' + handleOpts + '</select></div>' +
          (showHole
            ? '<div class="field-row"><label>홀간 거리</label>' +
                '<input type="number" data-mod-idx="' + i + '" data-key="handle_hole_mm" ' +
                       'value="' + (m.handle_hole_mm||128) + '" min="32" max="320">' +
                '<span class="unit">mm</span></div>'
            : '') +
        '</details>'
      : '') +

    // ── 측판 설정 (접이) ──────────────────────────────────────────────
    '<details><summary class="detail-summary">측판 설정</summary>' +
    '<div class="toggle-row"><label>좌 측판 생략 <span style="font-size:10px;color:var(--text-dim)">(EP / 인접 모듈이 측벽)</span></label>' +
      '<input type="checkbox" data-mod-idx="' + i + '" data-key="suppress_left_side"' +
      (m.suppress_left_side ? ' checked' : '') + '></div>' +
    '<div class="toggle-row"><label>우 측판 생략 <span style="font-size:10px;color:var(--text-dim)">(EP / 인접 모듈이 측벽)</span></label>' +
      '<input type="checkbox" data-mod-idx="' + i + '" data-key="suppress_right_side"' +
      (m.suppress_right_side ? ' checked' : '') + '></div>' +
    '</details>' +

    // ── 내부 구성 ────────────────────────────────────────
    '<details><summary class="detail-summary">내부 구성</summary>' +

    // 전체폭 선반
    '<div class="sub-list">' +
      '<div class="sub-list-title">전체폭 선반</div>' +
      '<div id="shelves-' + i + '">' +
        (shelvesList || '<span style="color:var(--text-dim);font-size:11px">없음</span>') +
      '</div>' +
      '<button class="btn-add" style="margin-top:4px" onclick="promptAddShelf(' + i + ')">＋ 선반</button>' +
    '</div>' +

    // 세로 분할판
    '<div class="sub-list">' +
      '<div class="sub-list-title">🔲 세로 분할판 ' +
        '<span style="font-size:10px;color:var(--text-dim);font-weight:normal">' + cellLabel + '</span>' +
      '</div>' +
      '<div id="dividers-' + i + '">' +
        (divList || '<span style="color:var(--text-dim);font-size:11px">없음 (단일 공간)</span>') +
      '</div>' +
      '<button class="btn-add" style="margin-top:4px" onclick="promptAddDivider(' + i + ')">＋ 세로 분할</button>' +
    '</div>' +

    // 셀별 선반
    '<div class="sub-list">' +
      '<div class="sub-list-title">📐 셀별 선반</div>' +
      '<div id="cshelves-' + i + '">' +
        (csLabel || '<span style="color:var(--text-dim);font-size:11px">없음</span>') +
      '</div>' +
      '<button class="btn-add" style="margin-top:4px" onclick="promptAddCellShelf(' + i + ')">＋ 셀 선반</button>' +
    '</div>' +

    // 셀별 서랍
    '<div class="sub-list">' +
      '<div class="sub-list-title">🗂 셀별 서랍 컬럼</div>' +
      '<div id="cdrawers-' + i + '">' +
        (cdLabel || '<span style="color:var(--text-dim);font-size:11px">없음</span>') +
      '</div>' +
      '<button class="btn-add" style="margin-top:4px" onclick="promptAddCellDrawer(' + i + ')">＋ 셀 서랍</button>' +
    '</div>' +
    '</details>' +

    // ── 액세서리 ─────────────────────────────────────────
    '<details><summary class="detail-summary">액세서리</summary>' +
    '<div class="sub-list">' +
      '<div id="accs-' + i + '">' +
        (accList || '<span style="color:var(--text-dim);font-size:11px">없음</span>') +
      '</div>' +
      '<div style="display:flex;gap:4px;margin-top:4px">' +
        '<button class="btn-add" onclick="promptAddAccessory(' + i + ',\'hanging_rod\')">옷걸이봉</button>' +
        '<button class="btn-add" onclick="promptAddAccessory(' + i + ',\'system_hanger\')">행거레일</button>' +
      '</div>' +
    '</div>' +
    '</details>'
  );
}

/* ── 침대 공간 필드 (bed_gap) ────────────────────────────────────────── */
function bedGapFields(m, i) {
  const bedSizes = [
    [1000, '싱글 1000mm'], [1200, '더블 1200mm'],
    [1400, '퀸 small 1400mm'], [1600, '퀸 1600mm'],
    [1800, '킹 1800mm'], [2000, '슈퍼킹 2000mm']
  ];
  const sizeOpts = bedSizes.map(([w, l]) =>
    '<option value="' + w + '"' + (+m.width === w ? ' selected' : '') + '>' + l + '</option>'
  ).join('');

  return '<div style="background:var(--bg);border:1px dashed var(--border);border-radius:var(--radius);' +
         'padding:10px;margin-bottom:6px;text-align:center;font-size:12px;color:var(--text-dim)">' +
         '🛏 침대 공간 — 지오메트리 없음, 런 모드에서 폭만 차지합니다</div>' +
    '<div class="field-row"><label>침대 폭</label>' +
      '<select data-mod-idx="' + i + '" data-key="width">' + sizeOpts + '</select>' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>직접 입력</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="width" ' +
             'value="' + (m.width||1600) + '" min="800" max="2400">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>레이블</label>' +
      '<input type="text" data-mod-idx="' + i + '" data-key="label" ' +
             'value="' + (m.label||'침대 공간') + '"></div>';
}

/* ── 책상 모듈 필드 ──────────────────────────────────────────────────── */
function deskFields(m, i) {
  const legOpts = [['box','사각 다리 (플랫팩)'],['round','원형 다리 (12면)']].map(([v,l]) =>
    '<option value="' + v + '"' + ((m.leg_type||'box')===v?' selected':'') + '>' + l + '</option>'
  ).join('');

  // 페데스탈 상태
  const ped     = m.pedestal     || {};
  const hasPed  = ped.enabled !== false && Object.keys(ped).length > 0;
  const pedPos  = ped.position   || 'right';

  // 상판 하부 서랍 상태
  const uu      = m.under_unit   || {};
  const hasUU   = uu.enabled !== false && Object.keys(uu).length > 0;
  const uuPos   = uu.position    || 'right';

  // 치수 정보
  const top_t   = m.top_thickness || 25;
  const legH    = (m.height || 750) - top_t;

  return '<div class="sub-section-title" style="font-weight:600;margin:6px 0 4px;color:var(--accent)">📐 치수 / 구조</div>' +
    '<div class="field-row"><label>폭</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="width" ' +
             'value="' + (m.width||1400) + '" min="300" max="3000">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>깊이</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="depth" ' +
             'value="' + (m.depth||700) + '" min="300" max="1200">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>전체 높이</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="height" ' +
             'value="' + (m.height||750) + '" min="400" max="1200">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>상판 두께</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="top_thickness" ' +
             'value="' + top_t + '" min="15" max="60">' +
      '<span class="unit">mm</span></div>' +
    '<div class="calc-info">📏 다리 높이: <strong>' + legH + 'mm</strong></div>' +

    '<div class="sub-section-title" style="font-weight:600;margin:10px 0 4px;color:var(--accent)">🦵 다리</div>' +
    '<div class="field-row"><label>다리 타입</label>' +
      '<select data-mod-idx="' + i + '" data-key="leg_type">' + legOpts + '</select></div>' +
    '<div class="field-row"><label>다리 폭</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="leg_w" ' +
             'value="' + (m.leg_w||60) + '" min="20" max="200">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>다리 깊이</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="leg_d" ' +
             'value="' + (m.leg_d||60) + '" min="20" max="200">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>좌우 안쪽 여백</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="leg_inset_x" ' +
             'value="' + (m.leg_inset_x||30) + '" min="0" max="200">' +
      '<span class="unit">mm</span></div>' +
    '<div class="field-row"><label>앞뒤 안쪽 여백</label>' +
      '<input type="number" data-mod-idx="' + i + '" data-key="leg_inset_y" ' +
             'value="' + (m.leg_inset_y||30) + '" min="0" max="200">' +
      '<span class="unit">mm</span></div>' +
    deskToggleRow('가림판 (모데스티)', m.has_modesty_panel, i, 'has_modesty_panel') +

    // ── 페데스탈
    '<div class="sub-section-title" style="font-weight:600;margin:10px 0 4px;color:var(--accent)">🗄 지지 서랍장 (페데스탈)</div>' +
    deskToggleRow('페데스탈 사용', hasPed, i, '_ped_enabled', 'toggleDeskPed(' + i + ',this.checked)') +
    '<div id="ped-fields-' + i + '" style="' + (hasPed?'':'display:none') + '">' +
      '<div class="field-row"><label>위치</label>' +
        '<select onchange="deskNestedField(' + i + ',\'pedestal\',\'position\',this.value)">' +
          '<option value="right"' + (pedPos==='right'?' selected':'') + '>우측</option>' +
          '<option value="left"'  + (pedPos==='left'?' selected':'')  + '>좌측</option>' +
        '</select></div>' +
      '<div class="field-row"><label>폭</label>' +
        numInput('deskNestedField(' + i + ",\\'pedestal\\',\\'width\\',+this.value)", ped.width||450, 150, 900) +
        '<span class="unit">mm</span></div>' +
      '<div class="field-row"><label>서랍 수</label>' +
        numInput('deskNestedField(' + i + ",\\'pedestal\\',\\'drawer_count\\',+this.value)", ped.drawer_count||3, 1, 6) +
        '<span class="unit">개</span></div>' +
    '</div>' +

    // ── 상판 하부 서랍
    '<div class="sub-section-title" style="font-weight:600;margin:10px 0 4px;color:var(--accent)">📦 상판 하부 서랍 유닛</div>' +
    deskToggleRow('하부 서랍 사용', hasUU, i, '_uu_enabled', 'toggleDeskUU(' + i + ',this.checked)') +
    '<div id="uu-fields-' + i + '" style="' + (hasUU?'':'display:none') + '">' +
      '<div class="field-row"><label>위치</label>' +
        '<select onchange="deskNestedField(' + i + ',\'under_unit\',\'position\',this.value)">' +
          '<option value="right"'  + (uuPos==='right'?' selected':'')  + '>우측</option>' +
          '<option value="left"'   + (uuPos==='left'?' selected':'')   + '>좌측</option>' +
          '<option value="center"' + (uuPos==='center'?' selected':'') + '>중앙</option>' +
        '</select></div>' +
      '<div class="field-row"><label>폭</label>' +
        numInput('deskNestedField(' + i + ",\\'under_unit\\',\\'width\\',+this.value)", uu.width||400, 150, 800) +
        '<span class="unit">mm</span></div>' +
      '<div class="field-row"><label>높이</label>' +
        numInput('deskNestedField(' + i + ",\\'under_unit\\',\\'height\\',+this.value)", uu.height||130, 80, 300) +
        '<span class="unit">mm</span></div>' +
      '<div class="field-row"><label>서랍 수</label>' +
        numInput('deskNestedField(' + i + ",\\'under_unit\\',\\'drawer_count\\',+this.value)", uu.drawer_count||1, 1, 4) +
        '<span class="unit">개</span></div>' +
    '</div>';
}

/* helper: number input snippet */
function numInput(onchange, val, min, max) {
  return '<input type="number" value="' + val + '" min="' + min + '" max="' + max +
         '" oninput="' + onchange + '">';
}

/* helper: toggle row for desk fields (no data-mod-idx, manual handler) */
function deskToggleRow(label, checked, modIdx, key, customHandler) {
  const handler = customHandler ||
    ('deskBoolField(' + modIdx + ",'" + key + "',this.checked)");
  return '<div class="toggle-row"><label>' + label + '</label>' +
    '<input type="checkbox"' + (checked ? ' checked' : '') +
    ' onchange="' + handler + '"></div>';
}

/* ── 손잡이 옵션 HTML ─────────────────────────────────────────────────── */
function handleOptions(current) {
  const types = [
    ['none','없음'],['bar','바 핸들'],['knob','원형 손잡이'],
    ['cup_pull','컵 풀'],['channel','채널 (핸들리스)'],['push_open','푸시 오픈']
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

  const val = el.type === 'checkbox' ? el.checked :
              el.type === 'number'   ? +el.value  : el.value;
  state.modules[idx][key] = val;

  const card = el.closest('.module-card');
  if (card) {
    const m       = state.modules[idx];
    const summary = card.querySelector('.mod-summary');
    if (summary) {
      const runH  = state.run_mode ? state.run_height || 740 : m.height;
      if (m.kind === 'bed_gap') {
        summary.textContent = (m.label || '침대 공간') + ' ' + m.width + 'mm';
      } else if (m.kind === 'shelf_module') {
        const dcL = {none:'오픈', single:'단문', pair:'양개'}[m.door_config || 'none'] || '';
        summary.textContent = m.width + '×' + (m.depth||'?') + '×' + runH + 'mm' + (dcL ? '  '+dcL : '');
      } else if (m.kind === 'drawer_module') {
        summary.textContent = m.width + '×' + (m.depth||'?') + '×' + runH + 'mm  서랍 ' + (m.drawer_count||1) + '단';
      } else {
        summary.textContent = m.width + '×' + (m.depth||'?') + '×' + runH + 'mm';
      }
    }
  }

  if (key === 'height' || key === 'door_config' || key === 'handle_type' || key === 'drawer_count' ||
      (key === 'width' && state.run_mode) || key === 'label') {
    kabinet.updateTotalHeight();
    kabinet.updateHeightSummary();
    // Re-render to update conditional sections (door_type row, hinge info, etc.)
    if (key === 'door_config' || key === 'handle_type' || key === 'drawer_count') renderModuleList();
  }
}

/* ── 책상 특수 필드 핸들러 ───────────────────────────────────────────── */
function deskBoolField(modIdx, key, value) {
  kabinet.getState().modules[modIdx][key] = value;
}

function deskNestedField(modIdx, section, key, value) {
  const m = kabinet.getState().modules[modIdx];
  if (!m[section]) m[section] = {};
  m[section][key] = value;
}

function toggleDeskPed(modIdx, enabled) {
  const m = kabinet.getState().modules[modIdx];
  if (!m.pedestal) m.pedestal = {};
  m.pedestal.enabled = enabled;
  document.getElementById('ped-fields-' + modIdx).style.display = enabled ? '' : 'none';
  if (enabled && !m.pedestal.position) {
    m.pedestal = { enabled: true, position: 'right', width: 450, drawer_count: 3, drawer_type: 'undermount' };
  }
}

function toggleDeskUU(modIdx, enabled) {
  const m = kabinet.getState().modules[modIdx];
  if (!m.under_unit) m.under_unit = {};
  m.under_unit.enabled = enabled;
  document.getElementById('uu-fields-' + modIdx).style.display = enabled ? '' : 'none';
  if (enabled && !m.under_unit.position) {
    m.under_unit = { enabled: true, position: 'right', width: 400, height: 130, drawer_count: 1, drawer_type: 'undermount' };
  }
}

/* ── 전체폭 선반 CRUD ───────────────────────────────────────────────── */
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

/* ── 세로 분할판 CRUD ───────────────────────────────────────────────── */
function promptAddDivider(modIdx) {
  const m    = kabinet.getState().modules[modIdx];
  const innerW = m.width - 2 * (m.body_thickness || 18);
  const xStr = prompt(
    '분할판 위치 (내부 좌측에서, mm)\n내부 폭: ' + innerW + 'mm', '300');
  if (xStr === null) return;
  const x = parseFloat(xStr);
  if (!x || x <= 0 || x >= innerW) {
    alert('위치가 범위를 벗어났습니다. 1 ~ ' + (innerW-1) + ' 사이로 입력하세요.'); return;
  }
  if (!m.vertical_dividers) m.vertical_dividers = [];
  m.vertical_dividers.push({ x, thickness: 18 });
  m.vertical_dividers.sort((a, b) => a.x - b.x);
  renderModuleList();
}

function removeDivider(modIdx, divIdx) {
  const m = kabinet.getState().modules[modIdx];
  m.vertical_dividers.splice(divIdx, 1);
  // 셀 번호가 달라지므로 cell_shelves, cell_drawers도 초기화 (안전)
  renderModuleList();
}

/* ── 셀별 선반 CRUD ─────────────────────────────────────────────────── */
function promptAddCellShelf(modIdx) {
  const m         = kabinet.getState().modules[modIdx];
  const cellCount = (m.vertical_dividers || []).length + 1;
  const cellStr   = prompt('셀 번호 (0~' + (cellCount-1) + ', 좌→우):', '0');
  if (cellStr === null) return;
  const cell = parseInt(cellStr);
  if (isNaN(cell) || cell < 0 || cell >= cellCount) {
    alert('셀 번호가 범위를 벗어났습니다.'); return;
  }
  const hStr = prompt('선반 높이 (바닥에서, mm):', '200');
  if (!hStr) return;
  const tStr = prompt('선반 두께 (mm):', '18');
  if (!m.cell_shelves) m.cell_shelves = [];
  m.cell_shelves.push({
    cell,
    height_from_bottom: parseFloat(hStr) || 200,
    thickness:          parseFloat(tStr) || 18,
    depth_inset:        0
  });
  renderModuleList();
}

function removeCellShelf(modIdx, csIdx) {
  kabinet.getState().modules[modIdx].cell_shelves.splice(csIdx, 1);
  renderModuleList();
}

/* ── 셀별 서랍 CRUD ─────────────────────────────────────────────────── */
function promptAddCellDrawer(modIdx) {
  const m         = kabinet.getState().modules[modIdx];
  const cellCount = (m.vertical_dividers || []).length + 1;
  const cellStr   = prompt('서랍을 채울 셀 번호 (0~' + (cellCount-1) + ', 좌→우):', '0');
  if (cellStr === null) return;
  const cell = parseInt(cellStr);
  if (isNaN(cell) || cell < 0 || cell >= cellCount) {
    alert('셀 번호가 범위를 벗어났습니다.'); return;
  }
  const countStr = prompt('서랍 수:', '2');
  if (!countStr) return;
  const count = parseInt(countStr) || 2;

  if (!m.cell_drawers) m.cell_drawers = [];
  // 같은 셀에 기존 항목이 있으면 교체
  m.cell_drawers = m.cell_drawers.filter(cd => cd.cell !== cell);
  m.cell_drawers.push({ cell, count, type: 'undermount', thickness: 18 });
  renderModuleList();
}

function removeCellDrawer(modIdx, cdIdx) {
  kabinet.getState().modules[modIdx].cell_drawers.splice(cdIdx, 1);
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
    acc.diameter = 32; acc.depth_inset = 75;
  } else if (kind === 'system_hanger') {
    acc.rail_height = 30; acc.rail_thickness = 5;
  }
  m.accessories.push(acc);
  renderModuleList();
}

function removeAccessory(modIdx, accIdx) {
  kabinet.getState().modules[modIdx].accessories.splice(accIdx, 1);
  renderModuleList();
}
