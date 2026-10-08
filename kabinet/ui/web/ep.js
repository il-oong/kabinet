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
  renderLibrary();
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
  const folders = [...new Set(items.map(item => item.folder || '미분류'))].sort((a, b) => a.localeCompare(b, 'ko'));
  const filter = byId('library-filter');
  const selected = filter.value;
  filter.replaceChildren(new Option('전체 폴더', ''), ...folders.map(folder => new Option(folder, folder)));
  filter.value = folders.includes(selected) ? selected : '';
  byId('library-folders').replaceChildren(...folders.map(folder => new Option(folder, folder)));
  renderLibrary();
};
function renderLibrary() {
  const container = byId('library-list');
  container.textContent = '';
  const query = byId('library-search').value.trim().toLocaleLowerCase();
  const selectedFolder = byId('library-filter').value;
  const items = library.filter(item => {
    const folder = item.folder || '미분류';
    return (!selectedFolder || folder === selectedFolder) &&
      (item.name.toLocaleLowerCase().includes(query) || folder.toLocaleLowerCase().includes(query));
  });
  if (!items.length) {
    const empty = document.createElement('p');
    empty.className = 'hint';
    empty.textContent = library.length ? '검색한 가구가 없습니다.' : '아직 저장한 가구가 없습니다.';
    container.appendChild(empty);
  }
  items.forEach(item => {
    const row = document.createElement('div');
    row.className = 'library-row';
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'library-item';
    button.disabled = pending;
    const title = document.createElement('strong');
    title.textContent = item.name;
    const detail = document.createElement('span');
    const dims = Array.isArray(item.dimensions_mm) ? item.dimensions_mm.join(' × ') + ' mm · ' : '';
    detail.textContent = (item.folder || '미분류') + ' · ' + dims + item.saved_at.slice(0, 16).replace('T', ' ');
    button.append(title, detail);
    button.addEventListener('click', () => {
      busy('저장한 가구를 불러오고 있습니다…');
      try { window.sketchup.ep_library_place(item.id); }
      catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
    });
    const edit = document.createElement('button');
    edit.type = 'button';
    edit.className = 'library-edit secondary';
    edit.textContent = '이름·폴더 변경';
    edit.disabled = pending;
    const form = document.createElement('form');
    form.className = 'library-edit-form';
    form.hidden = true;
    const name = document.createElement('input');
    name.value = item.name;
    name.maxLength = 60;
    name.required = true;
    name.setAttribute('aria-label', '가구 이름');
    const folder = document.createElement('input');
    folder.value = item.folder || '미분류';
    folder.maxLength = 40;
    folder.setAttribute('list', 'library-folders');
    folder.setAttribute('aria-label', '보관 폴더');
    const save = document.createElement('button');
    save.type = 'submit';
    save.textContent = '변경 저장';
    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.className = 'secondary';
    cancel.textContent = '취소';
    cancel.addEventListener('click', () => { form.hidden = true; });
    edit.addEventListener('click', () => { form.hidden = !form.hidden; if (!form.hidden) name.focus(); });
    form.append(name, folder, save, cancel);
    form.addEventListener('submit', event => {
      event.preventDefault();
      if (!name.value.trim()) { epResult('가구 이름을 입력하세요.', true); return; }
      busy('가구 이름과 폴더를 변경하고 있습니다…');
      try { window.sketchup.ep_library_update(JSON.stringify({id: item.id, name: name.value.trim(), folder: folder.value.trim()})); }
      catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
    });
    row.append(button, edit, form);
    container.appendChild(row);
  });
}
byId('library-search').addEventListener('input', renderLibrary);
byId('library-filter').addEventListener('change', renderLibrary);
byId('library-form').addEventListener('submit', event => {
  event.preventDefault();
  const name = byId('library-name').value.trim();
  if (!name) { epResult('저장할 가구 이름을 입력하세요.', true); return; }
  busy('선택한 가구를 보관함에 저장하고 있습니다…');
  try { window.sketchup.ep_library_save(JSON.stringify({name, folder: byId('library-folder').value.trim()})); }
  catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
});
document.addEventListener('DOMContentLoaded', () => {
  const today = new Date();
  byId('drawing-date').value = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,'0')}-${String(today.getDate()).padStart(2,'0')}`;
  byId('survey-date').value = byId('drawing-date').value;
  if (window.sketchup) window.sketchup.ep_library_list();
  else epLibrary([]);
});
byId('export').addEventListener('click', () => {
  busy(byId('space-mode').checked ? '공간 도면을 작성하고 있습니다. 잠시 기다려 주세요…' : '선택 가구의 도면을 작성하고 있습니다. 잠시 기다려 주세요…');
  try {
    window.sketchup.ep_export(JSON.stringify({title: byId('title').value.trim() || '가구 도면', internal: byId('internal').checked, iso_direction: byId('iso-direction').value, furniture_name: byId('furniture-name').value.trim(), site: byId('site').value.trim(), drawing_date: byId('drawing-date').value, author: byId('author').value.trim(), memo: byId('memo').value.trim(), surface_left: byId('surface-left').value, surface_right: byId('surface-right').value, surface_back: byId('surface-back').value, space_mode: byId('space-mode').checked, space_name: byId('space-name').value.trim(), ceiling_height: byId('ceiling-height').value, survey_date: byId('survey-date').value, wall_views: byId('wall-views').checked}));
  } catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
});

document.querySelectorAll('[data-role]').forEach(button => button.addEventListener('click', () => {
  busy('선택 부품을 구분하고 있습니다…');
  try { window.sketchup.ep_role(button.dataset.role); }
  catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
}));
document.querySelectorAll('[data-front]').forEach(button => button.addEventListener('click', () => {
  busy('가구의 정면 방향을 확인하고 있습니다…');
  try { window.sketchup.ep_front(button.dataset.front); }
  catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
}));

byId('space-mode').addEventListener('change', () => {
  byId('space-options').hidden = !byId('space-mode').checked;
  byId('furniture-options').hidden = byId('space-mode').checked;
  document.querySelectorAll('[data-furniture-only]').forEach(element => { element.hidden = byId('space-mode').checked; });
  byId('export').textContent = byId('space-mode').checked ? '공간 도면 출력 · LayOut + PDF' : '도면 출력 · LayOut + PDF';
});
document.querySelectorAll('[data-space-role]').forEach(button => button.addEventListener('click', () => {
  busy('공간 부품을 지정하고 있습니다…');
  try { window.sketchup.ep_space_role(button.dataset.spaceRole); }
  catch (error) { epResult('SketchUp의 Kabinet 창에서 실행하세요.', true); }
}));
