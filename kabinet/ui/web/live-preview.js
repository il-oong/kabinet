/* SketchUp wireframe preview. A revision prevents stale callback messages. */
const kabinetLivePreview = (() => {
  let enabled = true;
  let paused = false;
  let timer = null;
  let revision = 0;
  let last = '';
  let selectedModule = null;

  function bridge(name, value) {
    if (typeof sketchup === 'undefined' || typeof sketchup[name] !== 'function') return false;
    sketchup[name](value);
    return true;
  }

  function status(message, error = false) {
    const el = document.getElementById('live-preview-status');
    if (el) { el.textContent = message; el.classList.toggle('error', error); }
  }

  function payload() {
    return { spec: kabinet.getState(), entityID: kabinet.getEntityID(),
      internal: !!document.getElementById('live-preview-internal')?.checked,
      selectedModule };
  }

  function schedule() {
    if (!enabled || paused) return;
    clearTimeout(timer);
    const data = payload();
    const fingerprint = JSON.stringify(data);
    if (fingerprint === last) return;
    const request = ++revision;
    status('입력을 마치면 SketchUp 미리보기가 갱신됩니다…');
    timer = setTimeout(() => {
      if (!enabled || paused || request !== revision) return;
      timer = null;
      // Do not let blank/invalid number fields leave an old preview looking current.
      const invalid = Array.from(document.querySelectorAll('input[type="number"]'))
        .some(el => el.offsetParent !== null && (el.value === '' || !el.validity.valid));
      if (invalid || !data.spec.modules.length) {
        bridge('kabinet:preview_stop', '');
        last = '';
        status(invalid ? '입력 범위에 맞는 숫자를 입력하세요. 미리보기를 잠시 숨겼습니다.' : '프리셋을 선택하거나 모듈을 추가하세요.', invalid);
        return;
      }
      last = fingerprint;
      data.revision = request;
      status('SketchUp 미리보기 계산 중…');
      if (!bridge('kabinet:preview', JSON.stringify(data))) {
        status('SketchUp에서 확장을 열면 3D 미리보기가 표시됩니다.');
      }
    }, 350);
  }

  function toggle(value) {
    enabled = value;
    paused = false;
    clearTimeout(timer);
    revision++;
    last = '';
    document.getElementById('live-preview-enabled').checked = enabled;
    if (enabled) schedule();
    else {
      bridge('kabinet:preview_stop', '');
      status('미리보기 종료 · 입력값은 유지되며 모델은 변경되지 않았습니다.');
    }
  }

  function pauseForApply() {
    paused = true;
    clearTimeout(timer);
    revision++;
    document.getElementById('btn-apply').disabled = true;
  }

  function finishApply(ok) {
    paused = false;
    document.getElementById('btn-apply').disabled = false;
    last = ok ? JSON.stringify(payload()) : '';
    status(ok ? '모델 반영 완료 · 다음 변경부터 다시 미리봅니다.' : '반영되지 않았습니다. 입력값을 확인하세요.', !ok);
  }

  function reset() {
    clearTimeout(timer);
    revision++;
    last = '';
    paused = false;
    document.getElementById('btn-apply').disabled = false;
  }

  function onStopped() {
    enabled = false;
    paused = false;
    clearTimeout(timer);
    revision++;
    last = '';
    const input = document.getElementById('live-preview-enabled');
    if (input) input.checked = false;
    status('미리보기 종료 · 다시 보려면 실시간 미리보기를 켜세요.');
  }

  function onResult(result) {
    if (result.revision !== revision || !enabled || paused) return;
    if (!result.ok) last = '';
    status(result.ok ? '파란 선: 변경안 · 주황색: 선택 모듈 · 모델 반영으로 확정' : result.message, !result.ok);
  }

  function setView(name) {
    bridge('kabinet:preview_view', name);
  }

  document.addEventListener('DOMContentLoaded', () => {
    // Bubbling runs after inline and module field handlers, including nested options.
    ['input', 'change', 'click'].forEach(event => document.addEventListener(event, () => schedule()));
    document.addEventListener('focusin', event => {
      const input = event.target.closest('[data-mod-idx]');
      selectedModule = input ? Number(input.dataset.modIdx) : null;
      schedule();
    });
    bridge('kabinet:ready', '');
    schedule();
  });
  return { schedule, toggle, pauseForApply, finishApply, reset, onStopped, onResult, setView };
})();
