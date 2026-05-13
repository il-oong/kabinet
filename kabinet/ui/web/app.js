/* =====================================================================
   Kabinet — Main application state and bridge layer
   ===================================================================== */

/* ── 가구 유형 기본 프리셋 ──────────────────────────────────────────────
   width/max_depth/base_height 는 어셈블리 치수.
   모듈 width 는 어셈블리 width 와 동일하게 설정.
   총 높이 계산: base_height + Σ(module.height) + top_panel.thickness
================================================================== */
const FURNITURE_PRESETS = {
  wardrobe: {
    name: '붙박이장',
    furniture_type: 'wardrobe',
    width: 1200, max_depth: 580, base_height: 100,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 100(걸레받이) + 1982 + 18(상판) = 2100mm
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 580, height: 1982,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1000, depth_inset: 75, diameter: 32 }
        ]
      }
    ],
    _info: '표준 붙박이장 W1200×D580×H2100 | 걸레받이100 + 양개여닫이 + 상의 행거'
  },

  kitchen_base: {
    name: '주방 하부장',
    furniture_type: 'kitchen_base',
    width: 900, max_depth: 580, base_height: 80,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: { thickness: 20 },
    // 총 높이: 80(걸레받이) + 740(단일 몸통) + 20(상판) = 840mm
    // 주방 하부장은 단일 카케이스 몸통으로 구성 (도어+선반 내부 배치)
    modules: [
      { kind: 'shelf_module', width: 900, depth: 580, height: 740,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 330, thickness: 18, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '주방 하부장 W900×D580×H840 | 걸레받이80+단일몸통740+상판20. 작업대 840mm'
  },

  kitchen_upper: {
    name: '주방 상부장',
    furniture_type: 'kitchen_upper',
    width: 900, max_depth: 320, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 15 },
    top_panel: null,
    // 총 높이: 0 + 700 = 700mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 320, height: 700,
        body_thickness: 15, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 15,
        door_material: 'LPM', handle_type: 'knob', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 15, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '주방 상부장 W900×D320×H700 | 바닥 설치 높이 1500mm 위 권장'
  },

  vanity: {
    name: '화장대',
    furniture_type: 'vanity',
    width: 900, max_depth: 350, base_height: 0,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 20 },
    // 총 높이: 0 + 230 + 450 + 20 = 700mm (화장대 표준 700~750mm)
    modules: [
      { kind: 'drawer_module', width: 900, depth: 350, height: 230,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'cup_pull', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 900, depth: 250, height: 450,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'cup_pull', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [], accessories: []
      }
    ],
    _info: '화장대 W900×D350×H700 | 서랍 2개 + 하부 수납. 상판 높이 700mm'
  },

  shoe_cabinet: {
    name: '신발장',
    furniture_type: 'shoe_cabinet',
    width: 900, max_depth: 350, base_height: 0,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1782 + 18 = 1800mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 350, height: 1782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 160, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 380, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 600, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 820, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1040, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1260, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1480, thickness: 18, depth_inset: 20 }
        ],
        accessories: []
      }
    ],
    _info: '신발장 W900×D350×H1800 | 선반 7개 (220mm 피치). 푸시오픈 권장'
  },

  bookshelf: {
    name: '책장',
    furniture_type: 'bookshelf',
    width: 900, max_depth: 300, base_height: 0,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1782 + 18 = 1800mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 300, height: 1782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 18,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 280, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 560, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 840, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 1120, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 1450, thickness: 18, depth_inset: 0 }
        ],
        accessories: []
      }
    ],
    _info: '오픈 책장 W900×D300×H1800 | 선반 5개 (32mm 가변 가능)'
  },

  tv_unit: {
    name: 'TV장',
    furniture_type: 'tv_unit',
    width: 1800, max_depth: 450, base_height: 80,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 25 },
    // 총 높이: 80 + 200 + 495 + 25 = 800mm (입식 표준 TV장)
    modules: [
      { kind: 'drawer_module', width: 1800, depth: 450, height: 200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 1800, depth: 450, height: 495,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 220, thickness: 18, depth_inset: 0 }],
        accessories: []
      }
    ],
    _info: 'TV장 W1800×D450×H800 | 받침80+서랍200+수납495+상판25. 입식형'
  },

  // ── 카탈로그 신규 프리셋 ─────────────────────────────────────────────────

  display_800: {
    name: '수납장 800',
    furniture_type: 'display_800',
    width: 800, max_depth: 400, base_height: 0,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    modules: [
      { kind: 'shelf_module', width: 800, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 300, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 600, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 850, thickness: 18, depth_inset: 20 }
        ],
        accessories: []
      }
    ],
    _info: '수납장 W800×D400×H1050 | 양개문·선반3개. 거실/서재 범용 수납'
  },

  display_1200: {
    name: '수납장 1200',
    furniture_type: 'display_1200',
    width: 1200, max_depth: 400, base_height: 0,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 300, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 600, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 850, thickness: 18, depth_inset: 20 }
        ],
        accessories: []
      }
    ],
    _info: '수납장 W1200×D400×H1050 | 양개문·선반3개. 거실/서재 범용 수납'
  },

  drawer_tower: {
    name: '서랍장 타워',
    furniture_type: 'drawer_tower',
    width: 400, max_depth: 450, base_height: 0,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm (서랍 4단)
    modules: [
      { kind: 'drawer_module', width: 400, depth: 450, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 4, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '서랍장 타워 W400×D450×H1050 | 서랍 4단. 침실/드레스룸 범용'
  },

  wardrobe_sliding: {
    name: '슬라이딩 붙박이장',
    furniture_type: 'wardrobe_sliding',
    width: 1600, max_depth: 600, base_height: 100,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 100 + 1982 + 18 = 2100mm
    modules: [
      { kind: 'shelf_module', width: 1600, depth: 600, height: 1982,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'sliding', door_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 500, thickness: 18, depth_inset: 20 }
        ],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1000, depth_inset: 75, diameter: 32 },
          { kind: 'hanging_rod', height_from_bottom: 500,  depth_inset: 75, diameter: 32 }
        ]
      }
    ],
    _info: '슬라이딩 붙박이장 W1600×D600×H2100 | 미닫이 2짝·상하 행거. 드레스룸'
  },

  // ── 수평 런 모드 프리셋 ───────────────────────────────────────────────────

  kitchen_run: {
    name: '주방 런 1800',
    furniture_type: 'kitchen_run',
    width: 1800, max_depth: 580, base_height: 80,
    material: 'LPM',
    run_mode: true,
    run_height: 660,          // 작업대 하부 내부 높이 (받침80+본체660+상판20=760mm, 작업대는 별도)
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 20 },
    // 수평 배열: 600(서랍) + 600(선반도어) + 600(선반도어)
    // 총 외부 폭: 18(EP좌) + 1800 + 18(EP우) = 1836mm
    // 총 외부 높이: 80 + 660 + 20 = 760mm (작업대 높이)
    modules: [
      { kind: 'drawer_module', width: 600, depth: 580, height: 660,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 600, depth: 580, height: 660,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 18, depth_inset: 20 }],
        accessories: []
      },
      { kind: 'shelf_module', width: 600, depth: 580, height: 660,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 18, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '주방 런 1800mm | 서랍(600)+수납(600)+수납(600). 런높이 660 → 작업대 760mm'
  }
};

/* ====================================================================== */
const kabinet = (() => {
  // ── Initial state (mirrors Schema JSON) ─────────────────────────────
  const DEFAULT_STATE = {
    version: 1,
    name: '내 가구',
    furniture_type: '',
    width: 900,
    max_depth: 580,
    base_height: 0,
    material: 'LPM',
    edge_banding_mm: 1.0,
    run_mode: false,
    run_height: 740,
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 20 },
    modules: []
  };

  let state = deepClone(DEFAULT_STATE);
  let currentEntityID = null;

  // ── Tab management ───────────────────────────────────────────────────
  function switchTab(name, btn) {
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.tab-bar button').forEach(b => b.classList.remove('active'));
    document.getElementById('tab-' + name).classList.add('active');
    if (btn) btn.classList.add('active');
    if (name === 'modules')  { renderModuleList(); updateHeightSummary(); }
    if (name === 'presets')  listPresets();
    if (name === 'assembly') updateTotalHeight();
  }

  // ── Furniture type preset loader ─────────────────────────────────────
  function loadFurniturePreset(type) {
    const preset = FURNITURE_PRESETS[type];
    if (!preset) return;
    state = deepClone(preset);
    delete state._info;
    currentEntityID = null;
    syncFormFromState();
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();

    // Show info box
    const info = document.getElementById('preset-info');
    if (info && preset._info) {
      info.textContent = preset._info;
      info.style.display = '';
    }

    // Keep dropdown in sync
    const sel = document.getElementById('f-furniture-type');
    if (sel) sel.value = type;

    setStatus('프리셋 로드: ' + (preset.name || type), 'ok');
  }

  // ── Field helpers ────────────────────────────────────────────────────
  function onField(key, value) {
    state[key] = value;
    if (key === 'width' || key === 'max_depth' || key === 'base_height') {
      updateTotalHeight();
    }
  }

  function onTopPanelToggle(checked) {
    state.top_panel = checked ? { thickness: 20 } : null;
    document.getElementById('top-panel-fields').style.display = checked ? '' : 'none';
    updateTotalHeight();
  }

  function onTopPanelField(key, value) {
    if (!state.top_panel) state.top_panel = {};
    state.top_panel[key] = value;
    updateTotalHeight();
  }

  function onEP(key, value) {
    state.ep[key] = value;
  }

  // ── Run mode toggle ──────────────────────────────────────────────────
  function onRunMode(checked) {
    state.run_mode = checked;
    // Show/hide run-height row
    const rhRow = document.getElementById('run-height-row');
    if (rhRow) rhRow.style.display = checked ? '' : 'none';
    // Show/hide total-run-width in assembly tab
    const twRow = document.getElementById('total-width-row');
    if (twRow) twRow.style.display = checked ? '' : 'none';
    // In run_mode, the distribute-height feature works on run_height instead
    const distRow  = document.getElementById('distribute-row');
    const distHint = document.getElementById('distribute-hint');
    if (distRow)  distRow.style.display  = checked ? 'none' : '';
    if (distHint) distHint.style.display = checked ? 'none' : '';
    updateTotalHeight();
    renderModuleList();
  }

  // ── Unified width: copy assembly width to all modules ────────────────
  function syncWidthToModules() {
    const w = state.width;
    state.modules.forEach(m => { m.width = w; });
    renderModuleList();
    setStatus('모든 모듈 폭을 ' + w + 'mm로 적용했습니다.', 'ok');
  }

  // ── Height distribution ──────────────────────────────────────────────
  function distributeHeight() {
    if (state.modules.length === 0) {
      setStatus('모듈이 없습니다.', 'error'); return;
    }
    const targetEl = document.getElementById('f-target-height');
    const target = parseFloat(targetEl ? targetEl.value : 0);
    if (!target || target <= 0) { setStatus('목표 높이를 입력하세요.', 'error'); return; }
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base = state.base_height || 0;
    const remaining = target - topT - base;
    if (remaining <= 0) { setStatus('목표 높이가 너무 작습니다.', 'error'); return; }
    const perMod = Math.round(remaining / state.modules.length);
    state.modules.forEach(m => { m.height = perMod; });
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
    setStatus('높이를 균등 분배했습니다 (각 ' + perMod + 'mm).', 'ok');
  }

  // ── Total height/width display ───────────────────────────────────────
  function updateTotalHeight() {
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base = state.base_height || 0;

    if (state.run_mode) {
      // Height = base + run_height + top panel
      const runH  = state.run_height || 740;
      const total = base + runH + topT;
      const el    = document.getElementById('total-height-display');
      if (el) el.textContent = total;

      // Also show total run width from section widths
      const totalW = state.modules.reduce((s, m) => s + (m.width || 0), 0);
      const twEl   = document.getElementById('total-run-width-display');
      if (twEl) twEl.textContent = totalW;
    } else {
      const modsH = state.modules.reduce((s, m) => s + (m.height || 0), 0);
      const total = base + modsH + topT;
      const el    = document.getElementById('total-height-display');
      if (el) el.textContent = total;

      // Sync target-height input with current total if user hasn't edited it
      const tgt = document.getElementById('f-target-height');
      if (tgt && !tgt._userEdited) tgt.value = total;
    }
  }

  // ── Generate / Regenerate ────────────────────────────────────────────
  function generate() {
    if (!validateState()) return;
    setStatus('생성 중…', '');
    sketchup['kabinet:generate'](JSON.stringify(state));
  }

  function regenerate() {
    if (!validateState()) return;
    setStatus('재생성 중…', '');
    const payload = JSON.stringify({ spec: state, entityID: currentEntityID });
    sketchup['kabinet:regenerate'](payload);
  }

  function loadSelection() {
    sketchup['kabinet:load_selection']('');
  }

  // Called from Ruby after load_selection
  function loadSpec(payload) {
    try {
      const { spec, entityID } = typeof payload === 'string' ? JSON.parse(payload) : payload;
      state = spec;
      currentEntityID = entityID || null;
      syncFormFromState();
      renderModuleList();
      updateTotalHeight();
      updateHeightSummary();
      setStatus('어셈블리 로드 완료.', 'ok');
    } catch (e) {
      setStatus('스펙 파싱 오류: ' + e.message, 'error');
    }
  }

  // ── Export ───────────────────────────────────────────────────────────
  function loadSelectionForExport() {
    sketchup['kabinet:load_selection']('');
  }

  function exportDrawings() {
    const checks = document.querySelectorAll('#tab-drawings .view-check input:checked');
    const views  = Array.from(checks).map(c => c.value);
    if (views.length === 0) { setStatus('뷰를 하나 이상 선택하세요.', 'error'); return; }
    const payload = JSON.stringify({ views, entityID: currentEntityID });
    sketchup['kabinet:export_drawings'](payload);
    setStatus('도면 출력 요청 중…', '');
  }

  function exportCutList() {
    if (!validateState()) return;
    setStatus('커트리스트 생성 중…', '');
    sketchup['kabinet:export_cutlist'](JSON.stringify(state));
  }

  // ── Presets ──────────────────────────────────────────────────────────
  function savePreset() {
    const name = document.getElementById('f-preset-name').value.trim();
    if (!name) { setStatus('프리셋 이름을 입력하세요.', 'error'); return; }
    sketchup['kabinet:save_preset'](JSON.stringify({ name, spec: state }));
  }

  function listPresets() {
    sketchup['kabinet:list_presets']('');
  }

  function loadPresets(presets) {
    const el   = document.getElementById('preset-list');
    const keys = Object.keys(presets || {});
    if (keys.length === 0) {
      el.innerHTML = '<span style="color:var(--text-dim);font-size:12px">저장된 프리셋이 없습니다.</span>';
      return;
    }
    el.innerHTML = keys.map(name => `
      <div class="preset-item">
        <span class="preset-name">${esc(name)}</span>
        <button onclick="kabinet.applyPreset(${JSON.stringify(JSON.stringify(presets[name]))})">불러오기</button>
        <button class="del-btn" onclick="kabinet.deletePreset(${JSON.stringify(name)})">✕</button>
      </div>`).join('');
  }

  function applyPreset(specJson) {
    try {
      state = JSON.parse(specJson);
      currentEntityID = null;
      syncFormFromState();
      renderModuleList();
      updateTotalHeight();
      updateHeightSummary();
      setStatus('프리셋 적용됨.', 'ok');
    } catch (e) { setStatus('프리셋 오류: ' + e.message, 'error'); }
  }

  function deletePreset(name) {
    sketchup['kabinet:delete_preset'](name);
  }

  // ── Module list (delegates to modules.js) ────────────────────────────
  function addModule(kind) {
    const w = state.width;
    const mod = kind === 'drawer_module'
      ? { kind, width: w, depth: state.max_depth, height: 200,
          body_thickness: 18, back_thickness: 9, has_back: true,
          drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 18,
          door_material: state.material || 'LPM', handle_type: 'none',
          material: state.material || 'LPM', edge_banding_mm: 1.0 }
      : { kind, width: w, depth: state.max_depth, height: 400,
          body_thickness: 18, back_thickness: 9, has_back: true,
          door_config: 'none', door_type: 'swing', door_thickness: 18,
          door_material: state.material || 'LPM', handle_type: 'none',
          material: state.material || 'LPM', edge_banding_mm: 1.0,
          shelves: [], accessories: [] };
    state.modules.push(mod);
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
  }

  function removeModule(idx) {
    state.modules.splice(idx, 1);
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
  }

  function moveModule(idx, dir) {
    const to = idx + dir;
    if (to < 0 || to >= state.modules.length) return;
    [state.modules[idx], state.modules[to]] = [state.modules[to], state.modules[idx]];
    renderModuleList();
    updateHeightSummary();
  }

  // ── Height summary bar in modules tab ───────────────────────────────
  function updateHeightSummary() {
    const el = document.getElementById('module-height-summary');
    if (!el) return;
    if (state.modules.length === 0) { el.innerHTML = ''; return; }
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base = state.base_height || 0;
    const parts = [];

    if (state.run_mode) {
      // Run mode: show section widths + shared height
      const runH   = state.run_height || 740;
      const totalW = state.modules.reduce((s, m) => s + (m.width || 0), 0);
      const totalH = base + runH + topT;
      if (base > 0)  parts.push('받침 ' + base);
      state.modules.forEach((m, i) => {
        const tag = m.kind === 'drawer_module' ? '서랍' : '선반';
        parts.push('S' + (i+1) + '(' + tag + ') W' + m.width);
      });
      if (topT > 0) parts.push('상판 ' + topT);
      el.innerHTML =
        '<span class="hs-label">런 높이 ' + totalH + 'mm / 섹션 총 폭 ' + totalW + 'mm</span>' +
        '<span class="hs-parts">' + parts.join(' + ') + '</span>';
    } else {
      const modsH = state.modules.reduce((s, m) => s + (m.height || 0), 0);
      const total = base + modsH + topT;
      if (base > 0) parts.push('받침 ' + base);
      state.modules.forEach((m, i) => {
        const tag = m.kind === 'drawer_module' ? '서랍' : '선반';
        parts.push('M' + (i+1) + '(' + tag + ') ' + m.height);
      });
      if (topT > 0) parts.push('상판 ' + topT);
      el.innerHTML =
        '<span class="hs-label">총 높이 ' + total + 'mm</span>' +
        '<span class="hs-parts">' + parts.join(' + ') + '</span>';
    }
  }

  // ── Status ───────────────────────────────────────────────────────────
  function onSuccess(msg) { setStatus(msg || '완료.', 'ok'); }
  function onError(msg)   { setStatus('오류: ' + msg, 'error'); }

  function setStatus(msg, cls) {
    const bar = document.getElementById('status-bar');
    bar.textContent = msg;
    bar.className   = 'status-bar' + (cls ? ' ' + cls : '');
  }

  // ── Validation ───────────────────────────────────────────────────────
  function validateState() {
    if (!state.name)           { setStatus('이름을 입력하세요.', 'error'); return false; }
    if (state.width <= 0)      { setStatus('폭은 0보다 커야 합니다.', 'error'); return false; }
    if (state.max_depth <= 0)  { setStatus('깊이는 0보다 커야 합니다.', 'error'); return false; }
    if (state.modules.length === 0) { setStatus('모듈을 1개 이상 추가하세요.', 'error'); return false; }
    for (let i = 0; i < state.modules.length; i++) {
      const m = state.modules[i];
      if (m.height <= 0) { setStatus('모듈 ' + (i+1) + ': 높이가 0보다 커야 합니다.', 'error'); return false; }
      if (m.depth  <= 0) { setStatus('모듈 ' + (i+1) + ': 깊이가 0보다 커야 합니다.', 'error'); return false; }
      if (m.kind === 'drawer_module' && (m.drawer_count < 1 || m.drawer_count > 6)) {
        setStatus('모듈 ' + (i+1) + ': 서랍 수는 1~6개 사이여야 합니다.', 'error'); return false;
      }
    }
    return true;
  }

  // ── Sync form ↔ state ────────────────────────────────────────────────
  function syncFormFromState() {
    setVal('f-name',   state.name);
    setVal('f-width',  state.width);
    setVal('f-depth',  state.max_depth);
    setVal('f-base',   state.base_height || 0);

    const matSel = document.getElementById('f-material');
    if (matSel) matSel.value = state.material || 'LPM';

    const ftSel = document.getElementById('f-furniture-type');
    if (ftSel) ftSel.value = state.furniture_type || '';

    const hasTop = !!state.top_panel;
    document.getElementById('f-top-use').checked = hasTop;
    document.getElementById('top-panel-fields').style.display = hasTop ? '' : 'none';
    if (hasTop) setVal('f-top-t', state.top_panel.thickness);

    document.getElementById('f-ep-left').checked  = !!(state.ep && state.ep.left);
    document.getElementById('f-ep-right').checked = !!(state.ep && state.ep.right);
    setVal('f-ep-t', state.ep ? state.ep.thickness : 18);

    // Run mode
    const runChk = document.getElementById('f-run-mode');
    if (runChk) {
      runChk.checked = !!state.run_mode;
      onRunMode(!!state.run_mode);   // update visibility of dependent rows
    }
    setVal('f-run-height', state.run_height || 740);

    if (currentEntityID) {
      const expEl = document.getElementById('f-export-id');
      if (expEl) expEl.value = currentEntityID;
    }

    // Reset preset info box
    const info = document.getElementById('preset-info');
    if (info) info.style.display = 'none';

    updateTotalHeight();
  }

  function setVal(id, val) {
    const el = document.getElementById(id);
    if (el) el.value = val;
  }

  // ── Utilities ────────────────────────────────────────────────────────
  function deepClone(o) { return JSON.parse(JSON.stringify(o)); }
  function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }

  function getState() { return state; }

  // ── Wire up target height user-edit flag ─────────────────────────────
  document.addEventListener('DOMContentLoaded', () => {
    const tgt = document.getElementById('f-target-height');
    if (tgt) tgt.addEventListener('input', () => { tgt._userEdited = true; });
    updateTotalHeight();
  });

  // ── Public API ───────────────────────────────────────────────────────
  return {
    switchTab, onField, onTopPanelToggle, onTopPanelField, onEP,
    generate, regenerate, loadSelection, loadSpec,
    exportDrawings, exportCutList, loadSelectionForExport,
    savePreset, listPresets, loadPresets, applyPreset, deletePreset,
    addModule, removeModule, moveModule,
    loadFurniturePreset,
    syncWidthToModules, distributeHeight,
    updateTotalHeight, updateHeightSummary,
    onRunMode,
    onSuccess, onError,
    getState
  };
})();
