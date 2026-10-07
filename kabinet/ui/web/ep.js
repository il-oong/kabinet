'use strict';
const byId = id => document.getElementById(id);
let library = [];
let pending = false;
function busy(message) {
  pending = true;
  document.querySelectorAll('button').forEach(button => { button.disabled = true; });
  byId('status').className = '';
  byId('status').textContent = message;
}
window.epResult = function (message, error) {
  pending = false;
  document.querySelectorAll('button').forEach(button => { button.disabled = false; });
  byId('status').textContent = message;
  byId('status').className = error ? 'error' : '';
};
byId('board-form').addEventListener('submit', event => {
  event.preventDefault();
  busy('EP 판재를 만들고 있습니다…');
  try {
    window.sketchup.ep_create(JSON.stringify({width: byId('width').value, thickness: byId('thickness').value, height: byId('height').value}));
  } catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
});
window.epLibrary = function (items) {
  library = items;
  renderLibrary();
};
function renderLibrary() {
  const container = byId('library-list');
  container.textContent = '';
  const query = byId('library-search').value.trim().toLocaleLowerCase();
  const items = library.filter(item => item.name.toLocaleLowerCase().includes(query));
  if (!items.length) {
    const empty = document.createElement('p');
    empty.className = 'hint';
    empty.textContent = library.length ? '검색한 가구가 없습니다.' : '아직 저장한 가구가 없습니다.';
    container.appendChild(empty);
  }
  items.forEach(item => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'library-item';
    button.disabled = pending;
    const title = document.createElement('strong');
    title.textContent = item.name;
    const detail = document.createElement('span');
    const dims = Array.isArray(item.dimensions_mm) ? item.dimensions_mm.join(' × ') + ' mm · ' : '';
    detail.textContent = dims + item.saved_at.slice(0, 16).replace('T', ' ');
    button.append(title, detail);
    button.addEventListener('click', () => {
      busy('저장한 가구를 불러오고 있습니다…');
      try { window.sketchup.ep_library_place(item.id); }
      catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
    });
    container.appendChild(button);
  });
}
byId('library-search').addEventListener('input', renderLibrary);
byId('library-form').addEventListener('submit', event => {
  event.preventDefault();
  const name = byId('library-name').value.trim();
  if (!name) { epResult('저장할 가구 이름을 입력하세요.', true); return; }
  busy('선택한 가구를 보관함에 저장하고 있습니다…');
  try { window.sketchup.ep_library_save(name); }
  catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
});
document.addEventListener('DOMContentLoaded', () => {
  if (window.sketchup) window.sketchup.ep_library_list();
  else epLibrary([]);
});
byId('export').addEventListener('click', () => {
  busy('선택 가구의 도면을 작성하고 있습니다. 잠시 기다려 주세요…');
  try {
    window.sketchup.ep_export(JSON.stringify({title: byId('title').value.trim() || '가구 도면', internal: byId('internal').checked}));
  } catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
});
