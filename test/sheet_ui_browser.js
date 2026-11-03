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
  assert((await page.locator('.sh-row').count()) === 7, '7 default pages');
  const titles = () => page.$$eval('.sh-row .sh-type', els => els.map(e => e.textContent));
  let t = await titles();
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
  await page.waitForTimeout(500);
  const cfg = await page.evaluate(() => kabinetSheet.getConfig());
  assert(cfg.pages[4].subject === 'A동 주방 가구' && cfg.pages[4].sheet_no === 'NO.012' && cfg.pages[4].scale === '30', 'edited fields');
  assert(cfg.pages[2].hidden === true && cfg.site === '판교 푸르지오 그랑블' && cfg.bg === 'dark', 'hidden/site/bg');
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
  await page.screenshot({ path: path.resolve(__dirname, 'sheet-ui.png') });
  await browser.close();
  console.log('sheet_ui_browser OK');
})().catch(e => { console.error(e); process.exit(1); });
