# Kabinet 인수인계 (v1.17.0 기준)

새 세션에서 이 파일부터 읽고 이어서 작업하세요. 사용자 선호: **한국어로 답변, 코드는 항상 PR 먼저 만든 뒤 머지, Railway 사용(이 저장소는 SketchUp 플러그인이라 해당 없음)**, 컨텍스트 70% 넘으면 중단하고 정리.

## 현재 상태
- master = v1.17.0 (PR #16~#22 머지됨). 설치 파일 `kabinet.rbz`(루트)는 항상 최신으로 재빌드해 커밋: `python3 build/package.py && cp build/kabinet-<버전>.rbz kabinet.rbz`
- 사용자 PC는 v1.8 → 수동 설치 필요했음. 이후 창의 **더보기 > GitHub에서 업데이트**로 갱신(master의 kabinet.rbz를 받아 설치).
- 테스트: `for t in test/*_test.rb; do ruby $t; done` + 브라우저 `test/live_preview_browser.js`(playwright, /opt/pw-browsers/chromium). SketchUp 실기 테스트는 한 번도 못 함 — 사용자가 사진으로 피드백.
- 버전 올릴 때 `kabinet/version.rb` + `kabinet/ui/web/index.html`(`?v=` 캐시 파라미터, 상단 v표시)를 같이 바꾸고 `INSTALL.md` 맨 위에 변경 기록 추가.

## 구조 요약
- `kabinet/core/*` 순수 계산/생성(assembly, shelf_module, drawer_module, desk_module, door_panel, fitting, cut_list, validation, **gaps**(도어 간격), **common**(가구 공통사항), **countertop**(상판 평면 계산))
- `kabinet/commands/*` SketchUp 명령(generate, regenerate, face_panel, space_divide, **countertop**, **common**, **slab_thickness**)
- `kabinet/ui/dialog.rb` HtmlDialog 콜백 전부, `panel_tools.rb`(면→패널/공간분할 도구), `place_tool.rb`(생성 위치 클릭), `front_view_tool.rb`(도면 정면 방향 표시), `live_preview.rb`
- `kabinet/ui/web/app.js`(상태·사이드바·프리셋 `FURNITURE_PRESETS`·공통사항·붙박이장 내부구성), `modules.js`(모듈 카드), `drawing.js`(도면·보관함 화면), `index.html`, `styles.css`
- 도면 출력은 LayOut(`output/furniture_sheet.rb`, `space_sheet.rb`) — DXF/CAD UI는 제거함(코드는 남아 있음).
- 공통사항 규칙은 **JS `applyCommon`과 Ruby `Core::Common.apply`가 같아야 함**(test/common_test.rb가 27개 프리셋으로 대조).

## 진행 기록
- (최신 세션) 프리셋 재구성은 사용자가 **"기존 유지 + 보강만"** 으로 결정. 27개 프리셋 전부 Schema 검증·Assembly 빌드 통과, 붙박이장 900×2300·주방 하부장 900×880 실측 일치 확인 → `test/preset_audit_test.rb` 추가. 남은 경고는 처짐 권고(18T 800mm 초과 스팬, 슬라이딩 행거봉 1524mm)뿐이며 경고로만 표시.

## 사용자가 요청했고 아직 안 한 것 (우선순위순)
1. **프리셋 (결정: 기존 유지, 전면 교체 안 함 — 위 진행 기록 참고; 아래는 참고용 원 요청)** — "이전 목록 모델 지우고 지금까지 경험으로 더 발전된 세트로 갈아엎기".
   - `kabinet/ui/web/app.js` 상단 `FURNITURE_PRESETS`(약 10~855행)와 `index.html`의 `<select id="f-furniture-type">` optgroup 목록이 원본(사이드바는 이 select를 읽어 그림). 둘 다 새 세트로 교체하고, `kabinet/constants.rb`의 참고용 목록, `test/common_test.rb`(프리셋 수 비교)·`test/export_furniture_presets.js`는 그대로 동작해야 함.
   - 반영할 경험(사용자 피드백): 붙박이장 W900·H2300·걸레받이50·푸시 손잡이 + 내부 구성(`wardrobe_layout`: long/double/drawer_hang/shelves, `wardrobe_opts`, `inner_drawers`), 주방 하부장 H880(걸레받이 80 + 몸통 780 + 상판 20), 책상 다리 30×30, 선반은 18T(처짐 경고는 경고로만), 가구 공통사항 적용 후에도 검증 통과, 도어 간격은 `door_gaps`.
   - 제안 세트(검토 후 사용자 확인 권장): 붙박이장(900 단품, 3칸 런 2700), 슬라이딩 붙박이장, 주방 하부장(도어 900 / 서랍 600 / 싱크 1200 런), 주방 상부장, 키큰장(냉장고장·팬트리), 신발장, 책장, TV장, 화장대, 책상(기본/서랍), 침대장, 아이방 붙박이.
   - 검증: 모든 프리셋을 `Schema.normalize/validate!` + `Assembly` 빌드(test/front_projection_test.rb의 방식) 통과, 높이/폭 실측 일치, `Core::Validation.warnings` 확인.
2. **"클릭한 면 → 18T로 수정이 굉장히 불편"** — 사용자 불만. 현재 대안으로 "선택 판재 두께 → T 일괄 변경"(`Commands::SlabThickness`)을 넣었으나 사용자 반응 미확인. 면 클릭 도구(`FacePanelTool`)는 그룹 안에서 판재 면을 클릭하면 반대면을 밀어 두께 변경(`FacePanel.resize_in_place`). 불편 지점을 사진/설명으로 다시 물어보고 개선.
3. **도어 열림/닫힘 표현 방법** — 사용자 질문 미답변. 현재 도면은 도어 닫힌 상태 기준. 열림 표현(예: 도어 열림 호/힌지 방향 기호, 미리보기에서 도어 숨김 토글 `live-preview-internal`)을 설명하고 필요 시 추가.
4. **"이미 만든 가구를 클릭해 총 폭·높이·판재 두께 바꾸기"** — 이미 가능: 가구 선택 → 창 "선택 불러오기" → 값 수정 → "수정 적용"(`Regenerate`). 두께 일괄은 "가구 공통사항". 사용자에게 이 흐름을 안내하고, 더 쉬운 방식(가구 클릭 시 창이 자동으로 불러오기) 원하면 SelectionObserver 추가 검토.
5. **내부 서랍 위치·크기 예시/커스텀, 외부 서랍** — v1.17에서 구현(붙박이장 기본 정보 > 내부 구성). 사용자 확인 대기.
6. 주방 상판 설치(v1.13): 사용자 실기 확인 대기. 공간 균등 분할 칸 수 입력창(v1.15에서 오류 수정) 확인 대기.

## 알려진 위험/주의
- SketchUp에서 실행해 본 적이 없는 코드가 많음(PlaceTool, FrontViewTool, SlabThickness, Countertop, 내부 서랍, 보관함 썸네일). 오류 사진이 오면 먼저 호출 메서드가 해당 클래스에 있는지, `Sketchup::` API 존재 여부 확인.
- 시스템 환경: 원격 컨테이너라 SketchUp 설치 불가. 가짜 객체 테스트(test/support/geom.rb)로만 검증 가능.
- 웹 검색으로 한샘 등 붙박이장 내부 치수를 찾지 못함 → 내부 구성 치수는 일반 실무 값(상부 선반 위 공간 330, 이단 행거 약 1/2 높이 등) 사용. 사용자에게 실제 업체 도면(사진)을 요청하면 정확해짐.
