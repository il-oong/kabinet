// 도면 시트 탭 UI 점검 — node test/sheet_ui_browser.js  (playwright + /opt/pw-browsers/chromium, SketchUp 브리지는 mock)
const path = require('path');
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const assert = (ok, m) => { if (!ok) throw new Error(m); };
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
  const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
  await page.addInitScript(() => {
    window.__calls = [];
    window.sketchup = new Proxy({}, { get: (_, name) => v => { window.__calls.push({ name, v }); } });
  });
  await page.goto('file://' + path.resolve(__dirname, '../kabinet/ui/web/index.html'));
  await page.waitForTimeout(300);
  await page.evaluate(() => kabinet.runSidebarAction('sheet_dxf'));
  assert(await page.isVisible('#view-sheet'), 'sheet view visible');
  assert((await page.locator('.sh-row').count()) === 8, '8 default pages (현장 안내 + 7)');
  const titles = () => page.$$eval('.sh-row .sh-type', els => els.map(e => e.textContent));
  let t = await titles();
  assert(t[0] === '현장 안내', '현장 안내 first: ' + t);
  assert((await page.inputValue('#sh-si-cautions')).includes('정문으로 출입해주세요') && (await page.inputValue('#sh-site')).includes('광교호수공원로 80'), 'site info defaults in UI');
  await page.fill('#sh-si-special', '2. 특이사항 : 테스트');
  await page.locator('.sh-row').nth(0).locator('button[data-act="down"]').click();     // 순서 이동
  t = await titles(); assert(t[1] === '현장 안내', 'info moved down: ' + t);
  await page.locator('.sh-row').nth(1).locator('button[data-act="up"]').click();
  assert((await page.evaluate(() => kabinetSheet.getConfig().site_info.special)) === '2. 특이사항 : 테스트', 'site_info saved in config');
  await page.locator('.sh-row').nth(0).locator('button[data-act="del"]').click();       // 이하 기존 시나리오는 7쪽 기준
  assert((await page.locator('.sh-row').count()) === 7, 'info deleted -> 7');
  t = await titles();
  assert(t[0] === '현장사진' && t[1] === '상담 3D' && t[2] === '평면도', 'default order: ' + t);
  // 위/아래 버튼
  await page.locator('.sh-row').nth(1).locator('button[data-act="up"]').click();
  t = await titles(); assert(t[0] === '상담 3D' && t[1] === '현장사진', 'move up: ' + t);
  await page.locator('.sh-row').nth(0).locator('button[data-act="down"]').click();
  t = await titles(); assert(t[0] === '현장사진', 'move down: ' + t);
  // 드래그: 마지막(생산 확인표)을 맨 앞 행으로
  await page.evaluate(() => {
    const rows = document.querySelectorAll('.sh-row');
    const dt = new DataTransfer();
    rows[6].dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
    rows[0].dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt }));
    rows[0].dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt }));
  });
  t = await titles(); assert(t[0] === '생산 확인표', 'drag to first: ' + t);
  // 편집: 제목 / SHEET NO. / SCALE / 숨김
  const row = page.locator('.sh-row').nth(4);
  await row.locator('input[data-k="subject"]').fill('A동 주방 가구');
  await row.locator('input[data-k="sheet_no"]').fill('NO.012');
  await row.locator('input[data-k="scale"]').fill('30');
  await page.locator('.sh-row').nth(2).locator('input[data-k="hidden"]').check();
  // 추가 / 삭제
  await page.selectOption('#sh-add-type', 'furniture');
  await page.click('text=＋ 페이지 추가');
  assert((await page.locator('.sh-row').count()) === 8, 'added');
  await page.locator('.sh-row').nth(7).locator('button[data-act="del"]').click();
  assert((await page.locator('.sh-row').count()) === 7, 'deleted');
  await page.fill('#sh-site', '판교 푸르지오 그랑블');
  await page.fill('#sh-furniture_name', '__-1');
  await page.selectOption('#sh-bg', 'dark');
  assert(await page.isChecked('#sh-images') && await page.isChecked('#sh-real_scale') && await page.isChecked('#sh-blocks'), '사진 포함·실치수·블록 기본 켜짐');
  await page.uncheck('#sh-images');
  await page.waitForTimeout(500);
  const cfg = await page.evaluate(() => kabinetSheet.getConfig());
  assert(cfg.pages[4].subject === 'A동 주방 가구' && cfg.pages[4].sheet_no === 'NO.012' && cfg.pages[4].scale === '30', 'edited fields');
  assert(cfg.pages[2].hidden === true && cfg.site === '판교 푸르지오 그랑블' && cfg.bg === 'dark', 'hidden/site/bg');
  assert(cfg.images === false && cfg.real_scale === true && cfg.blocks === true, 'images off / real_scale on in config');
  const saves = await page.evaluate(() => window.__calls.filter(c => c.name === 'kabinet:sheet_save'));
  assert(saves.length >= 1 && JSON.parse(saves[saves.length - 1].v).pages.length === 7, 'save bridge called with 7 pages');
  // 내보내기: 숨김 제외 6쪽
  await page.evaluate(() => kabinetSheet.exportDxf());
  const ex = await page.evaluate(() => window.__calls.filter(c => c.name === 'kabinet:sheet_export').pop());
  assert(ex && JSON.parse(ex.v).page_ids.length === 6, 'export excludes hidden');
  // 다시 열기(저장 복원)
  await page.reload(); await page.waitForTimeout(300);
  await page.evaluate(() => kabinet.runSidebarAction('sheet_dxf'));
  const t2 = await titles();
  assert(t2[0] === '생산 확인표' && (await page.locator('.sh-row').count()) === 7, 'persist across reload: ' + t2);
  // ── 이미지 페이지: 현장사진 / 상담 3D ──
  await page.evaluate(() => { const c = kabinetSheet.getConfig(); c.pages.forEach(p => { p.hidden = false; }); kabinetSheet.render(); });
  const ids = await page.evaluate(() => { const c = kabinetSheet.getConfig(); return { photos: c.pages.find(p => p.type === 'photos').id, view3d: c.pages.find(p => p.type === 'view3d').id }; });
  await page.evaluate((id) => kabinetSheet.addImages(id, ['/tmp/a/현장1.jpg', '/tmp/a/현장2.png', '/tmp/a/현장3.jpg']), ids.photos);
  assert((await page.locator('.sh-extra[data-pid="' + ids.photos + '"] .sh-img').count()) === 3, '3 photos listed');
  await page.locator('.sh-extra[data-pid="' + ids.photos + '"] input[data-idx="1"]').fill('거실 전경');
  await page.locator('.sh-extra[data-pid="' + ids.photos + '"] button[data-iact="iup"][data-idx="1"]').click();
  let imgs = await page.evaluate((id) => kabinetSheet.getConfig().pages.find(p => p.id === id).images, ids.photos);
  assert(imgs[0].caption === '거실 전경' && imgs[0].path.endsWith('현장2.png') && imgs[1].caption === '현장1', 'caption + reorder ' + JSON.stringify(imgs));
  await page.locator('.sh-extra[data-pid="' + ids.photos + '"] button[data-iact="idel"][data-idx="2"]').click();
  assert((await page.locator('.sh-extra[data-pid="' + ids.photos + '"] .sh-img').count()) === 2, 'delete image');
  await page.locator('.sh-extra[data-pid="' + ids.photos + '"] button[data-iact="ifile"]').click();
  await page.locator('.sh-extra[data-pid="' + ids.photos + '"] button[data-iact="ifolder"]').click();
  await page.evaluate(() => kabinetSheet.setState({ config: kabinetSheet.getConfig(), furniture: { has_furniture: true, name: '붙박이장', size: '1,800x2,300x600' }, scenes: ['장면 1', '장면 2'] }));
  await page.locator('.sh-extra[data-pid="' + ids.view3d + '"] button[data-iact="icapture"]').click();
  await page.locator('.sh-extra[data-pid="' + ids.view3d + '"] select[data-iscene]').selectOption('1');
  await page.locator('.sh-extra[data-pid="' + ids.view3d + '"] button[data-iact="iscene"]').click();
  const calls = await page.evaluate(() => window.__calls.map(c => c.name + ':' + c.v));
  assert(calls.some(c => c.startsWith('kabinet:sheet_pick_image:') && c.includes(ids.photos)), 'pick image bridge');
  assert(calls.some(c => c.startsWith('kabinet:sheet_pick_folder:')), 'pick folder bridge');
  assert(calls.some(c => c.startsWith('kabinet:sheet_capture:') && c.includes('"scene":-1')), 'capture current view bridge');
  assert(calls.some(c => c.startsWith('kabinet:sheet_capture:') && c.includes('"scene":1')), 'capture scene bridge');
  await page.evaluate((id) => kabinetSheet.addImages(id, ['/tmp/a/3d.png'], '현재 화면'), ids.view3d);
  assert((await page.locator('.sh-extra[data-pid="' + ids.view3d + '"] .sh-img').count()) === 1, '3D image added');
  await page.screenshot({ path: path.resolve(__dirname, 'sheet-ui.png'), fullPage: true });
  await browser.close();
  console.log('sheet_ui_browser OK');
})().catch(e => { console.error(e); process.exit(1); });
