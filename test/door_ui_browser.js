// 사이드바 도어 도구 UI 점검 — node test/door_ui_browser.js  (playwright, SketchUp 브리지는 mock)
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
  const labels = await page.$$eval('.sb-tools .sb-action, .sb-tools button', els => els.map(e => e.textContent.trim()));
  for (const l of ['도어 열기/닫기', '열린 도어 각도 적용', '선택 → 도어 지정', '도어 지정 해제']) {
    assert(labels.some(x => x.includes(l)), '사이드바 항목 없음: ' + l + ' / ' + labels.join('|'));
  }
  assert(await page.inputValue('#tool-door-angle') === '80', '기본 각도 80');
  const last = async () => JSON.parse((await page.evaluate(() => window.__calls.filter(c => c.name === 'kabinet:tool').pop())).v);
  await page.fill('#tool-door-angle', '110');
  await page.dispatchEvent('#tool-door-angle', 'change');
  await page.evaluate(() => kabinet.runSidebarAction('door_toggle'));
  let c = await last(); assert(c.name === 'door_toggle' && c.angle === 110, 'toggle angle 110: ' + JSON.stringify(c));
  await page.evaluate(() => kabinet.runSidebarAction('door_angle'));
  c = await last(); assert(c.name === 'door_angle' && c.angle === 110, 'angle apply: ' + JSON.stringify(c));
  await page.fill('#tool-door-angle', '999');
  await page.evaluate(() => kabinet.runSidebarAction('door_toggle'));
  c = await last(); assert(c.angle === 175, '범위 175 제한: ' + JSON.stringify(c));
  await page.fill('#tool-door-angle', '2');
  await page.evaluate(() => kabinet.runSidebarAction('door_toggle'));
  c = await last(); assert(c.angle === 5, '범위 5 제한: ' + JSON.stringify(c));
  await page.selectOption('#tool-door-side', 'right');
  await page.evaluate(() => kabinet.runSidebarAction('door_designate'));
  c = await last(); assert(c.name === 'door_designate' && c.side === 'right', 'designate right: ' + JSON.stringify(c));
  await page.evaluate(() => kabinet.runSidebarAction('door_undesignate'));
  c = await last(); assert(c.name === 'door_undesignate', 'undesignate: ' + JSON.stringify(c));
  await page.screenshot({ path: path.resolve(__dirname, 'door-ui.png') });
  await browser.close();
  console.log('door_ui_browser OK');
})().catch(e => { console.error(e); process.exit(1); });
