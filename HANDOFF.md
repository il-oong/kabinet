# Kabinet 인수인계 (최신 상태는 아래 「제작도면(시트) 기능 — 최신 인계」 절 먼저)

새 세션에서 이 파일부터 읽고 이어서 작업하세요. 사용자 선호: **한국어로 답변, 코드는 항상 PR 먼저 만든 뒤 머지, Railway 사용(이 저장소는 SketchUp 플러그인이라 해당 없음)**, 컨텍스트 70% 넘으면 중단하고 정리.

## (v1.26.1) ep-2 재구성
- `________ep-2` = ep-1 DXF 안에 이미 포함된 2번째 시트(도어·EP 상세). ep-1/ep-2 모두 A 재질·현장 안내로 재생성. 미확정: 상부장 높이 740(ep-1) vs 540(ep-2), 키큰장 도어 7칸(362/370/370/363/46/324/385) 생성기 미지원, 냉장고 높이 1910 추정.

## (v1.26.0) 최종본(A) 분석 + B(___-1) 재구성
- reference/ 보관(A·B·변환 DXF·샘플 PDF·originals), `tools/sheet/dump_reference.py` → `REFERENCE_SPEC.md` + `reference/spec/*.md`, CLAUDE.md §6. B 선반 높이 380 vs 원본 판독 347/322/368 은 미확정(README 확인표).
- A = 우리 v1.25.9 아일랜드 DXF 를 사용자가 AutoCAD 에서 수정·저장한 것(§15). 생성기 기본값만 A 기준으로 변경(재질/현장 안내). 아일랜드의 CAD 수정값(로봇청소기장 상부 H320, 싱크 컷 920×432 등)은 JSON 에 아직 미반영 — 필요하면 사용자 확인 후 반영. B = 기존 `___-1` 샘플과 같은 도면(홈바장 2060×892×620), 목찬넬 가정(추정). `tools/sheet/compare_to_reference.py`.

## (v1.25.9) 장 결합 시공(측판 2장)
- island: `inner_widths_row`, 측판 쌍 rect(BODY·평면), 모듈 외곽 폭 dims(clip_span), generic/Ruby 동일(`clipped`, `inner_row`). verify `--twin-panels`. core 는 이미 독립 박스(조사 결과 INSTALL.md). 남은 확인: 원본 모듈 폭의 EP 포함 여부, 가전 자리(식기세척기) 양옆 측판 처리.

## (v1.25.8) 아일랜드 서랍면 걸레받이 50 + 페이크도어
- `Model.kickA`(overall.kick_A=50), `fronts(m,n,k,bot)`, A면 모듈 type `fake`(페이크도어), `a_fronts` = (kickA,25), 단면 B/A 걸레받이 단차, 확인표 갱신. 남은 확인: 서랍면/싱크면 걸레받이 단차 처리, 페이크도어 고정 방식, 장식 찬넬 수량.

## (v1.25.7) 주방 하부장 수정
- generic: `tb(d, md)`(channel_tb), `fronts()` 하단 틈 25, 하부 찬넬 사각·단면·상세 ③(`edge_section(up=True)`), 뷰 패널 중앙 정렬, `______/furniture.json`(H900=상판12+몸통888, channel_tb). Ruby 동일(`tb?`). 남은 일: 샘플 PDF 31~42쪽 하부 찬넬 표현과 직접 대조, 모서리 문제 판단(시트 뷰 위치 vs 방 안 위치) 사용자 확인.

## (v1.25.6) 힌지 제거 · DIMENSION · 천판 EP 제거 · 현장 주소/안내 쪽
- Python 치수 = `dim_h/dim_v/inner_dim` → ("D",…) 항목 → DXF 는 `add_linear_dim(...).render()`(DIMSTYLE KAB), PDF 는 `expand_dims` 로 낱개 전개. Ruby 는 `Canvas#dim_scope` + `item_dims` → `DIM_nnn_S#` BLOCK(임시). 다음 과제: Ruby DxfWriter 에 DIMENSION + `*D` 익명 블록 이식(gen_dxf_skeleton.py 에 `*D` 훅 필요).
- 천판 EP: 아일랜드/channel 가구는 제거(`ep_band` no-op, `TOP_IN=body_H-18`, 도어 상단 = body_H-25). generic/Ruby 는 channel 이면 ep top 자동 false.
- 현장 안내(INFO) 쪽: Ruby `Pages.info`, `Frame.info`, UI 카드 `#sh-info-card`, cfg `site_info`; Python `page_info`/`site_info_of`/`DEFAULT_SITE_INFO`. 표제란 주소 2줄(`site_text`).
- 남은 일: Ruby DIMENSION 이식, 실기 열림 확인(DIMENSION·블록), generic 의 inner_dim 류 소형 치수 DIMENSION 화 완료 여부 점검.

## (v1.25.5) EP·몸통 겹침 해소
- `clip_span`(island)/`clipped`·`ep_bounds`·`ep_row`(generic·Ruby): EP 쪽 끝 모듈을 EP 안쪽으로 줄임, 가로 3단 치수(모듈/EP|몸통|EP/전체), 모듈선은 천판 EP 아래까지, 전판 상단은 천판 EP 아래. 검사 `verify_dxf.py --no-overlap-ep`, `test/sheet_no_overlap_ep_test.rb`. 남은 확인: 도면 모듈 폭이 EP 포함인지(현재 포함으로 가정, 확인표 '[변경] EP·몸통 폭').

## (v1.25.4) 로봇청소기장 500/18/302 + 측판 EP 바닥까지
- `build_sheet.py`: ROBOT_BAY=500(바닥 기준), 로봇청소기장 풀높이 원도어·걸레받이/하판 제외, `ep_ends`=바닥까지, `ep_band`=측판 EP 사이, 걸레받이는 EP 사이. generic·Ruby 동일 규칙. 업로드 DWG 분석: aspose 변환본은 좌표가 약 1/25.53 배율로 나옴(레이어 `0` 워터마크 제외, 텍스트는 폴리선 획). 남은 확인: NO.002 `FD_DOOR`(OPEN 베이 위 2단 사각형) 의도, 측판 EP 접합(맞댐/45°), 도어 하단 처리.

## (v1.25.3) 로봇청소기장 베이 450 + 힌지 금지
- 로봇청소기장 = 원도어, 하단 450 비움 → 선반 18T → 상부 252(추정, `ROBOT_BAY`). 힌지/도어 열림은 시트 생성기·산출물 전수 검색 결과 0건(평면도 출입문 호만 제거), `test/sheet_no_hinge_test.rb` + `verify_dxf.py --no-hinge` 로 방지. 남은 일: `output/drawing2d.rb`(플러그인 일반 2D 도면)의 개폐 방향 V 표시를 지울지 사용자 확인.

## (v1.25.2) 아일랜드장 샘플 수정
- 사용자 지시 반영: H900/상판 80/몸통 820(순 720)/걸레받이 100, 로봇청소기장·인출장(폭 300 `장(2단)` 추정) 원도어, 식기세척기 높이 35 초과 경고. `tools/sheet/build_sheet.py`(Model 이 TOP_IN/BOT_IN/HH 갱신, 모듈 type `pullout` 추가), `output_samples/furniture.json`·`_____-1/furniture.json` 수정, 산출물 재생성(`_____-1/sheet_1대1.dxf` 포함). 남은 확인: 인출장이 실제로 어느 모듈인지, 식기세척기 모델/높이. verify_dxf 치수 문자 검사의 '싱크면/서랍면' 접미사 오탐 해소(불일치 0).

## (v1.25.1) 제작도면 DXF — 최신 인계 (이 절이 가장 최신; v1.25.1 = PR #39 리뷰 4건 수정, 아래는 v1.25.0 인계에 이어짐)
- v1.25.1: ① 채널 손잡이 모듈 단위(`Model` 모듈별 'channel') ② generic 측면 시트 표제란 축척=den_top ③ `to_real_scale.py` 블록 대응·축척 못 찾으면 오류 ④ 뷰 블록에 치수·마커·캡션 포함 + `verify_dxf.py` 도곽 블록 검사·치수 검사 오탐(보조선) 제거. 남은 치수 문자 불일치: 아일랜드 side 시트 4건(650/450 구간), `______` furniture 2건(3 mm 구간) — 라벨 위치/검사 기준 확인 필요.

## (v1.25.0) 제작도면 DXF 인계
- 브랜치 `claude/dazzling-babbage-v46o8h`(master 최신 위, PR 미생성·미머지 — 사용자 확인 후 처리). 버전 1.25.0, `kabinet.rbz` 재빌드 완료.
- **완료**: ① `SHEET_FORMAT_ANALYSIS.md` §14(Ruby vs Python 비교표·구조 결함) ② **DXF 호환**: `output/sheet/dxf_skeleton.rb`(자동 생성, `tools/sheet/gen_dxf_skeleton.py`)+`dxf_writer.rb` 재작성 — ezdxf R2004 골격 그대로(LAYOUT/ACAD_* 딕셔너리/CLASSES/DIMSTYLE/BLOCK_RECORD 340/$HANDSEED 계산), IMAGE 는 ASCII 상대경로(`<영문>_images/img_01.jpg`)+옵션 `images:false`(UI 「사진 포함」), `verify_dxf.py --structure-only`(핸들 중복·미해결 참조) ③ **내용 동등성**: Ruby 키플랜·절단선/번호 마커·단면 1~2·목찬넬·가전·싱크 이식, 모델 스키마 = `furniture.json`(generic), `tools/sheet/export_sheet.rb`, `tools/sheet/compare_ruby_python.py`(샘플 4건 중 ___-1/________ep-1 포함 모두 PASS) ④ **1:1 실치수**(Ruby `real_scale` 기본 켜짐/UI, Python WIP 와 같은 개념: 시트별 배수 den) ⑤ 해칭 = 영역당 HATCH(ANSI31) 1개(Ruby·Python 모두), 뷰·도곽을 이름 있는 BLOCK+INSERT(옵션 `blocks`/UI 「뷰를 블록으로」, Python `--no-blocks`) ⑥ 테스트: `test/sheet_dxf_test.rb`(구조·images:false·real_scale·블록·HATCH), `sheet_encoding_test`, `sheet_ui_browser.js`, 전체 `test/*_test.rb` 통과, Ruby 2.7 검사(오탐 2건 제외) 통과.
- **남은 일**: (a) [v1.25.1 에서 120mm 8건은 검사 오탐으로 해소, 위 잔여 참조] (b) 한국 CAD 실기 열림 확인(INSTALL.md v1.25.0 실기 항목) — 안 열리면 「사진 포함」 끄고 재시도, 그래도 안 되면 CAD 이름·오류 문구 수집 (c) 아일랜드 전용 JSON(`output_samples/_____-1/furniture.json`, B_side/A_side 스키마)은 Ruby 모델로 변환 미구현 — 비교는 generic JSON 으로 함 (d) 상세 쪽(1/5·1/2 확대)은 실물 1:1 아님 (e) PR/머지는 사용자 확인 후.
- **다음 세션 시작**: `git switch claude/dazzling-babbage-v46o8h && git pull`, `ruby test/sheet_dxf_test.rb`, `python3 -I tools/sheet/compare_ruby_python.py output_samples/___-1/furniture.json`, `python3 -I tools/sheet/verify_dxf.py <dxf>`. 하네스가 WIP 자동 커밋을 만들 수 있으니 `git add` 는 경로 지정으로.

## (v1.24.0) CAD 도면 DXF → 시트 재구성 — 최신 인계 (맨 앞 절보다 최신)
- 브랜치 `claude/tender-darwin-852d8m`. 사용자가 올린 CAD 도면 DXF 5개(아일랜드장·홈바장·냉장고장 데코·현관장·주방 하부장; 각 파일 = 몸통/도어/상판 3장 도곽)를 **치수(DIMENSION)+라벨(MTEXT)** 로 읽어 시트로 재구성하는 Ruby 기능 추가. 결과 `output_samples/reconstructed/*.dxf,json`.
- **(미해결, 최우선) 사용자 CAD 에서 생성 DXF 가 안 열림**: 화면에 `Press ENTER to continue:` 만 뜨고 도면이 안 나옴(AC1015·AC1018 모두 동일). ezdxf 는 오류 0 으로 읽음. 가장 유력한 원인 = `output/sheet/dxf_writer.rb` 의 OBJECTS 가 빈 루트 DICTIONARY 하나뿐(LAYOUT/ACAD_LAYOUT/ACAD_GROUP/MATERIAL 등 없음)이고 CLASSES·DIMSTYLE Standard 도 비어 있음. 같은 파일을 ezdxf 로 재저장(`readfile→saveas`, LAYOUT 2개·딕셔너리 12개 생성)한 v2 를 사용자에게 보내 열리는지 확인 요청함. v2 가 열리면: Ruby 작성기에 LAYOUT(Model/Layout1)·ACAD_LAYOUT/ACAD_GROUP/ACAD_MATERIAL 딕셔너리·DIMSTYLE Standard·CLASSES 를 추가(ezdxf 재저장본 OBJECTS 를 참고). 안 열리면 사용자에게 CAD 이름과 Enter 전 오류 문구를 받아야 함.
- 구현: `output/sheet/dxf_reader.rb`, `dxf_import.rb`(DxfImport.from_file → {name, models, report}), UI 버튼/콜백(`sheet.js#importCad`, `dialog.rb kabinet:sheet_import_cad`, `sheet_bridge.rb#import_cad`), CLI `tools/sheet/import_dxf.rb`, 테스트 `test/sheet_import_test.rb`(합성 DXF).
- 입력 DXF 특징: mm 단위(INSUNITS 4), UTF-8, 레이어 `DS-定制柜体/台面/五金`, `SH-尺寸标注`(DIMENSION, 실측값 group 42), 도곽 INSERT `_Frame*`(레이어 `图框`). 모듈 라벨은 평면도 안(면별 y 밴드), 큰 제목 MTEXT(h≥60)가 가구명.
- **남은 일(우선순위)**: ① 끊긴 치수 행 처리 — 아일랜드장은 B면 326|900|300|474|614|486|500 인데 현재 2개만 읽음(`chains_of` 가 끝점이 이어진 행만 인식; 라벨 x 위치+가전 구간 갭 보간 필요) ② 라벨 없는 도면(현관장) 모듈 분할을 정면도 선(몸통 세로선)에서 추출 ③ 홈바장 첫 모듈 라벨 없음(M1) 확인 ④ 상판 도곽(3번째)에서 싱크 컷·상판 분할 읽기 ⑤ 도어 도곽에서 도어 분할 ⑥ SketchUp 실기 확인(openpanel 한글 경로) ⑦ 필요 시 master 로 머지(PR 먼저).
- 분석 도구 메모: 이 컨테이너에 `pip install ezdxf matplotlib` 후 `ezdxf.addons.drawing` 으로 PNG 렌더해 육안 확인 가능.

## 제작도면(시트) 기능 — 최신 인계 (이 절이 가장 최신)
- **브랜치/버전**: 작업 브랜치 `claude/dazzling-babbage-v46o8h`(master 에는 아직 머지 안 됨 — 사용자가 요청할 때만 PR). 이 브랜치 = **v1.23.1**(`kabinet/version.rb`, `index.html ?v=`), `kabinet.rbz` 재빌드 완료(`python3 build/package.py && cp build/kabinet-1.23.1.rbz kabinet.rbz`). v1.23.0 은 master 에 머지됨(PR #34).
- **Python 프로토타입(완성, PDF+DXF)**: `tools/sheet/build_sheet.py` → `output_samples/test_sheet.pdf/.dxf/_dark.dxf`, `furniture.json`, `preview-*.png`. 양식 분석·결정사항·테스트 결과·개정 이력은 `SHEET_FORMAT_ANALYSIS.md` (§2~§8 양식 좌표, §12 입력 DWG 분석, §13.x 테스트 결과). 주방 아일랜드(싱크면+서랍면) 1건 전용 페이지(평면 / NO.001~003 / 상세 / 확인표)까지.
- **Ruby 이식(DXF만, 4단계 모두 커밋됨)**:
  - ① 생성기 — `kabinet/output/sheet/*`(순수 Ruby: styles/canvas/frame/model/pages/dxf_writer(AC1015, CP949, IMAGE)/builder/image_info) + `output/sheet.rb`. 테스트 `test/sheet_dxf_test.rb`(레이어·시트 수·배경 옵션·IMAGE/IMAGEDEF·상대경로·한글), 교차검증(수동) `tools/sheet/verify_dxf.py`(ezdxf audit 0 확인).
  - ② 페이지 구성 UI — 사이드바 「도면 시트 (DXF)」(`ui/web/sheet.js`, `index.html #view-sheet`): 순서(▲▼·드래그)·추가/삭제·숨김·제목/SHEET NO./SCALE, 가구명/현장명/DATE, 배경·폰트 스타일. 모델 attribute `kabinet_sheet/config_json` 저장(`ui/sheet_bridge.rb`). 테스트 `test/sheet_bridge_test.rb`, 브라우저 `node test/sheet_ui_browser.js`(스크린샷 `test/sheet-ui.png`).
  - ③ 현장사진(맨 앞)·상담 3D 쪽 — 파일 추가(UI.openpanel)/폴더 추가/현재 화면·장면 캡처(`SheetBridge.capture`, view.write_image), 격자 1/2/4/6, 캡션, DXF `<이름>_images/` 복사·상대경로.
  - ④ 버전/문서 — INSTALL.md 맨 위 v1.23.0 항목(사용법 + **실기 확인 항목 6개**).
- **(v1.23.1) 한글 Windows 인코딩 버그 수정**: 실기에서 `incompatible character encodings: UTF-8 and CP949`(이미지 추가). 원인 = openpanel/Dir/File.basename 이 준 CP949 태그 경로를 UTF-8 한글 문자열과 결합. 수정 = `output/sheet/text.rb`(`Text.utf8/deep_utf8/resolve_path/native/to_cp949`) + Builder/DxfWriter/ImageInfo/SheetBridge/dialog 콜백(`SheetBridge.guard/js/add_images_script`) 정규화, 오류에 동작명 표시·콘솔 backtrace. 재현·회귀 `test/sheet_encoding_test.rb`. 새 코드에서 외부 문자열을 다룰 땐 반드시 `Text.utf8` 경유. 브랜치는 PR #34 머지 후 master 최신에서 다시 생성함.\n- **(추가 도면 5건 재구성)** 입력 5개는 모두 텍스트 DXF(AC1032, CP949; DWG 변환 불필요, ezdxf 로 DIMENSION/MTEXT 직접 판독). 결과: `output_samples/<파일stem>/`(sheet.pdf, sheet.dxf, sheet_dark.dxf, furniture.json, README.md, preview-N.png). 범용 빌더 `tools/sheet/build_generic.py`(build_sheet.py 의 도곽·치수·마커·EP/찬넬·렌더러를 import 해 재사용 — 아일랜드 전용 build_sheet.py 는 그대로라 test_sheet.* 회귀 없음; 완전 통합 리팩터는 미완). 한계/남은 일: 평면·단면은 일렬 직사각 모듈 가정(L형 현관장은 근사), 두 번째 시트(ep-2/홈바장-2)·세부 칸 분할 미반영, 측면도 하단 라벨 겹침 약간, 용도·치수는 README 의 "추정" 참고. 파일명 한글이 빠져 있어 가구명은 stem 임시값(`--name` 으로 재생성).
- **남은 일**: ⓐ SketchUp 실기 테스트(위 6개) ⓑ Ruby 시트에 주방 아일랜드 양면/단면 2개/EP·목찬넬 세부를 일반화해 이식(현재 Ruby 가구 시트는 일렬 모듈 일반형) ⓒ PDF 시트 Ruby 이식(미착수 — Python 만 가능) ⓓ 이미지 자동 리사이즈(현재 원본 복사) ⓔ `drawing_import.js` 의 `window.kabinetDrawingImport` 미노출(사이드바 `open()` 호출이 무효일 수 있음, 확인 필요) ⓕ 필요 시 master 로 PR.
- **옛 기록 표시**: 아래 `현재 상태`·`진행 기록`의 v1.17~v1.21 표기와 "DXF/CAD UI는 제거함" 등은 작성 당시 기준 — 지금은 위 시트 기능이 DXF 출력의 최신입니다. 실제 버전은 `kabinet/version.rb`.

## 현재 상태
- (옛 기록, 작성 당시) master = v1.17.0 (PR #16~#22 머지됨; 이후 v1.22.1 까지 진행, 위 최신 절 참조). 설치 파일 `kabinet.rbz`(루트)는 항상 최신으로 재빌드해 커밋: `python3 build/package.py && cp build/kabinet-<버전>.rbz kabinet.rbz`
- 사용자 PC는 v1.8 → 수동 설치 필요했음. 이후 창의 **더보기 > GitHub에서 업데이트**로 갱신(master의 kabinet.rbz를 받아 설치).
- 테스트: `for t in test/*_test.rb; do ruby $t; done` + 브라우저 `test/live_preview_browser.js`(playwright, /opt/pw-browsers/chromium). SketchUp 실기 테스트는 한 번도 못 함 — 사용자가 사진으로 피드백.
- 버전 올릴 때 `kabinet/version.rb` + `kabinet/ui/web/index.html`(`?v=` 캐시 파라미터, 상단 v표시)를 같이 바꾸고 `INSTALL.md` 맨 위에 변경 기록 추가.

## 구조 요약
- `kabinet/core/*` 순수 계산/생성(assembly, shelf_module, drawer_module, desk_module, door_panel, fitting, cut_list, validation, **gaps**(도어 간격), **common**(가구 공통사항), **countertop**(상판 평면 계산))
- `kabinet/commands/*` SketchUp 명령(generate, regenerate, face_panel, space_divide, **countertop**, **common**, **slab_thickness**)
- `kabinet/ui/dialog.rb` HtmlDialog 콜백 전부, `panel_tools.rb`(면→패널/공간분할 도구), `place_tool.rb`(생성 위치 클릭), `front_view_tool.rb`(도면 정면 방향 표시), `live_preview.rb`
- `kabinet/ui/web/app.js`(상태·사이드바·프리셋 `FURNITURE_PRESETS`·공통사항·붙박이장 내부구성), `modules.js`(모듈 카드), `drawing.js`(도면·보관함 화면), `index.html`, `styles.css`
- 도면 출력은 LayOut(`output/furniture_sheet.rb`, `space_sheet.rb`) — 옛 DXF/CAD UI는 제거함(코드는 남아 있음). **새 제작도면 시트 DXF 는 `output/sheet/*` + 사이드바 「도면 시트 (DXF)」**(위 최신 절).
- 공통사항 규칙은 **JS `applyCommon`과 Ruby `Core::Common.apply`가 같아야 함**(test/common_test.rb가 27개 프리셋으로 대조).

## 진행 기록
- (v1.21.1) 도면 치수표에 JSON 붙여넣기(`importJson`). **DWG 읽기 메모**: DWG(AC1021)는 플러그인이 직접 못 읽음. 클라우드에서는 `pip install aspose-cad ezdxf` 후 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` 로 DWG→DXF 변환 가능(평가판). 오톤도 DWG는 치수·문자가 폴리라인으로 분해돼 있고(텍스트/DIMENSION 0개), 레이어 `DS-定制柜体`(몸통)·`DS-定制柜门`(도어)·`DS-定制台面`(상판)·`SH-尺寸标注`(치수)로 나뉨. 좌표 스케일 ≈ 25.5mm/단위(3400×2550 입면이 133.2×99.9). 입면 뷰별 도어 사각형으로 위치·폭을 얻을 수 있음을 확인했으나 자동 변환은 미구현.
- (v1.21.0) **도면 치수표 → 3D 가구**: `ui/web/drawing_import.js`(표 UI) + `app.js`의 `buildDrawingSpec(row)`(프리셋 구조 유지·치수만 변경, state 임시 교체 후 복원) + `commands/drawing_import.rb`(여러 가구를 위치·회전대로 생성) + `dialog.rb` 콜백 `kabinet:drawing_import`. 테스트 `test/drawing_import_test.rb`. PDF 도면은 Claude가 읽어 표 값으로 옮김(플러그인은 PDF 파싱 불가).
- (v1.20.0) 도면 가구 프리셋 6종(`otondo_*`, 18T) · 모서리 R(`Builder.rounded_box`, 책상 `top_radius`/`top_round_corners`, `top_panel.corner_radius`) · 모든 판재는 각 그룹(테스트로 검증). 기존 프리셋 전체 18T 통일은 미실시(높이 재계산 필요).
- (v1.19.x) 도어 열기/닫기(`commands/door_toggle.rb`, 80°), 면 클릭 두께 변경 수정(`Sketchup::Face::PointOutside`), 한 덩어리 그룹 벽 두께 변경 — SketchUp 실기 확인 대기.
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
