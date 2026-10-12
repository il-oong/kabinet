#!/usr/bin/env node
// UserPromptSubmit: UI/디자인 관련 요청이면 ui-ux-pro-max 스킬 사용을 상기시킨다.
let raw = '';
process.stdin.on('data', d => { raw += d; });
process.stdin.on('end', () => {
  let prompt = '';
  try { prompt = String(JSON.parse(raw).prompt || ''); } catch (e) { return; }
  const ui = /\b(ui|ux|css|layout|design|component|style|palette|font|typography|dashboard|landing|page)\b|화면|디자인|레이아웃|스타일|색상|폰트|버튼|대시보드|랜딩|페이지|UI/i;
  if (!ui.test(prompt)) return;
  process.stdout.write(
    'UI/UX 관련 요청입니다. ui-ux-pro-max 스킬을 로드해 검색 도구 ' +
    '(python3 "$CLAUDE_PROJECT_DIR/.claude/skills/ui-ux-pro-max/scripts/search.py" "<query>" --domain <domain>)로 ' +
    '근거를 확인한 뒤 적용하세요.');
});
