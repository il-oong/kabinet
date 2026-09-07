// Run in the local UI via agent-browser eval --stdin. SketchUp bridge is mocked.
(async () => {
  const assert = (ok, message) => { if (!ok) throw new Error(message); };
  const settle = () => new Promise(resolve => setTimeout(resolve, 450));
  const calls = [];
  window.sketchup = new Proxy({}, { get: (_, name) => value => {
    calls.push({ name, value });
    if (name === 'kabinet:preview') {
      const data = JSON.parse(value);
      kabinetLivePreview.onResult({ revision: data.revision, ok: true });
    }
  } });
  const previews = () => calls.filter(c => c.name === 'kabinet:preview');
  const change = (id, value) => {
    const el = document.getElementById(id);
    el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
  };
  kabinet.loadFurniturePreset('wardrobe');
  kabinetLivePreview.toggle(true);
  await settle();
  assert(previews().length === 1, 'Preset must send one preview');
  let data = JSON.parse(previews().pop().value);
  assert(data.spec.ep.thickness === 20 && data.spec.modules[0].door_thickness === 20 && data.spec.modules[0].body_thickness === 18, '18/20/20 defaults');

  calls.length = 0;
  change('f-width', '1300'); change('f-width', '1400'); change('f-width', '1500');
  await settle();
  assert(previews().length === 1, 'Typing must debounce');
  data = JSON.parse(previews()[0].value);
  assert(data.spec.width === 1500 && data.spec.modules[0].width === 1460, 'Final width and EP allowance');

  change('f-depth', '620');
  await settle();
  assert(kabinet.getState().modules[0].depth === 620, 'Depth follows overall depth');
  const input = document.querySelector('[data-mod-idx="0"][data-key="body_thickness"]');
  input.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
  const internal = document.getElementById('live-preview-internal');
  internal.checked = true; internal.dispatchEvent(new Event('change', { bubbles: true }));
  await settle();
  data = JSON.parse(previews().pop().value);
  assert(data.internal && data.selectedModule === 0, 'Internal view and selected module');
  kabinetLivePreview.setView('top');
  assert(calls.some(c => c.name === 'kabinet:preview_view' && c.value === 'top'), 'Camera bridge');

  calls.length = 0;
  change('f-width', '1600');
  kabinetLivePreview.toggle(false);
  await settle();
  assert(previews().length === 0, 'Stop cancels pending preview');
  kabinetLivePreview.toggle(true);
  await settle();
  calls.length = 0;
  change('f-width', '');
  await settle();
  assert(previews().length === 0 && calls.some(c => c.name === 'kabinet:preview_stop'), 'Blank input hides stale geometry');
  change('f-width', '1500');
  await settle();
  data = JSON.parse(previews().pop().value);
  kabinetLivePreview.onResult({ revision: data.revision - 1, ok: false, message: 'STALE' });
  assert(!document.getElementById('live-preview-status').textContent.includes('STALE'), 'Stale result ignored');

  calls.length = 0;
  kabinet.smartApply();
  assert(calls.some(c => c.name === 'kabinet:generate'), 'First apply generates');
  kabinet.onApplied({ spec: JSON.parse(JSON.stringify(kabinet.getState())), entityID: '42' });
  kabinet.onField('width', 1550);
  kabinet.smartApply();
  assert(calls.some(c => c.name === 'kabinet:regenerate' && JSON.parse(c.value).entityID === '42'), 'Second apply updates existing entity');
  kabinet.onError('test failure');
  change('f-width', '1560');
  await settle();
  assert(previews().length > 0, 'Preview recovers after apply failure');

  const legacy = JSON.parse(JSON.stringify(kabinet.getState()));
  legacy.ep.thickness = 18; legacy.modules[0].door_thickness = 18;
  kabinet.loadSpec({ spec: legacy, entityID: '99' });
  await settle();
  assert(kabinet.getState().ep.thickness === 18 && kabinet.getState().modules[0].door_thickness === 18, 'Existing thicknesses preserved');
  kabinetLivePreview.onStopped();
  assert(!document.getElementById('live-preview-enabled').checked, 'Tool deactivation updates toggle');
  kabinet.loadFurniturePreset('wardrobe');
  internal.checked = false;
  kabinetLivePreview.toggle(true);
  await settle();
  return 'PASS: debounce, defaults, width/depth, selection, internal view, camera, stop, invalid input, stale callbacks, apply identity, recovery, legacy values';
})();
