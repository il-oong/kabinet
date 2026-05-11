/* =====================================================================
   Kabinet — Main application state and bridge layer
   ===================================================================== */

const kabinet = (() => {
  // ── Initial state (mirrors Schema JSON) ─────────────────────────────
  const DEFAULT_STATE = {
    version: 1,
    name: '내 가구',
    width: 900,
    max_depth: 580,
    base_height: 0,
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 20 },
    modules: []
  };

  let state = deepClone(DEFAULT_STATE);
  let currentEntityID = null;   // set when editing an existing assembly

  // ── Tab management ───────────────────────────────────────────────────
  function switchTab(name, btn) {
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.tab-bar button').forEach(b => b.classList.remove('active'));
    document.getElementById('tab-' + name).classList.add('active');
    if (btn) btn.classList.add('active');
    if (name === 'modules') renderModuleList();
    if (name === 'presets') listPresets();
  }

  // ── Field helpers ────────────────────────────────────────────────────
  function onField(key, value) {
    state[key] = value;
  }

  function onTopPanelToggle(checked) {
    state.top_panel = checked ? { thickness: 20 } : null;
    document.getElementById('top-panel-fields').style.display = checked ? '' : 'none';
  }

  function onTopPanelField(key, value) {
    if (!state.top_panel) state.top_panel = {};
    state.top_panel[key] = value;
  }

  function onEP(key, value) {
    state.ep[key] = value;
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
    const views = Array.from(checks).map(c => c.value);
    if (views.length === 0) { setStatus('뷰를 하나 이상 선택하세요.', 'error'); return; }
    const payload = JSON.stringify({ views, entityID: currentEntityID });
    sketchup['kabinet:export_drawings'](payload);
    setStatus('도면 출력 요청 중…', '');
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
    const el = document.getElementById('preset-list');
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
      setStatus('프리셋 적용됨.', 'ok');
    } catch (e) { setStatus('프리셋 오류: ' + e.message, 'error'); }
  }

  function deletePreset(name) {
    sketchup['kabinet:delete_preset'](name);
  }

  // ── Module list (delegates to modules.js) ────────────────────────────
  function addModule(kind) {
    const mod = kind === 'drawer_module'
      ? { kind, width: state.width, depth: state.max_depth, height: 200,
          body_thickness: 18, back_thickness: 9,
          drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 18 }
      : { kind, width: state.width, depth: state.max_depth, height: 400,
          body_thickness: 18, back_thickness: 9,
          door_config: 'none', door_thickness: 18, shelves: [], accessories: [] };
    state.modules.push(mod);
    renderModuleList();
  }

  function removeModule(idx) {
    state.modules.splice(idx, 1);
    renderModuleList();
  }

  function moveModule(idx, dir) {
    const to = idx + dir;
    if (to < 0 || to >= state.modules.length) return;
    [state.modules[idx], state.modules[to]] = [state.modules[to], state.modules[idx]];
    renderModuleList();
  }

  // ── Status ───────────────────────────────────────────────────────────
  function onSuccess(msg) { setStatus(msg || '완료.', 'ok'); }
  function onError(msg)   { setStatus('오류: ' + msg, 'error'); }

  function setStatus(msg, cls) {
    const bar = document.getElementById('status-bar');
    bar.textContent = msg;
    bar.className = 'status-bar' + (cls ? ' ' + cls : '');
  }

  // ── Validation ───────────────────────────────────────────────────────
  function validateState() {
    if (!state.name) { setStatus('이름을 입력하세요.', 'error'); return false; }
    if (state.width <= 0) { setStatus('폭은 0보다 커야 합니다.', 'error'); return false; }
    if (state.max_depth <= 0) { setStatus('깊이는 0보다 커야 합니다.', 'error'); return false; }
    if (state.modules.length === 0) { setStatus('모듈을 1개 이상 추가하세요.', 'error'); return false; }
    for (let i = 0; i < state.modules.length; i++) {
      const m = state.modules[i];
      if (m.height <= 0) { setStatus(`모듈 ${i+1}: 높이가 0보다 커야 합니다.`, 'error'); return false; }
      if (m.depth <= 0)  { setStatus(`모듈 ${i+1}: 깊이가 0보다 커야 합니다.`, 'error'); return false; }
      if (m.kind === 'drawer_module' && (m.drawer_count < 1 || m.drawer_count > 6)) {
        setStatus(`모듈 ${i+1}: 서랍 수는 1~6개 사이여야 합니다.`, 'error'); return false;
      }
    }
    return true;
  }

  // ── Sync form ↔ state ────────────────────────────────────────────────
  function syncFormFromState() {
    setVal('f-name', state.name);
    setVal('f-width', state.width);
    setVal('f-depth', state.max_depth);
    setVal('f-base', state.base_height || 0);
    const hasTop = !!state.top_panel;
    document.getElementById('f-top-use').checked = hasTop;
    document.getElementById('top-panel-fields').style.display = hasTop ? '' : 'none';
    if (hasTop) setVal('f-top-t', state.top_panel.thickness);
    document.getElementById('f-ep-left').checked = !!(state.ep && state.ep.left);
    document.getElementById('f-ep-right').checked = !!(state.ep && state.ep.right);
    setVal('f-ep-t', state.ep ? state.ep.thickness : 18);
    if (currentEntityID) document.getElementById('f-export-id').value = currentEntityID;
  }

  function setVal(id, val) {
    const el = document.getElementById(id);
    if (el) el.value = val;
  }

  // ── Utilities ────────────────────────────────────────────────────────
  function deepClone(o) { return JSON.parse(JSON.stringify(o)); }
  function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

  function getState() { return state; }

  // ── Public API ───────────────────────────────────────────────────────
  return {
    switchTab, onField, onTopPanelToggle, onTopPanelField, onEP,
    generate, regenerate, loadSelection, loadSpec,
    exportDrawings, loadSelectionForExport,
    savePreset, listPresets, loadPresets, applyPreset, deletePreset,
    addModule, removeModule, moveModule,
    onSuccess, onError,
    getState
  };
})();
