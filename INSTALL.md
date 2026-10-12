# Kabinet — 설치 및 검증 가이드

## v1.11.0 — 한 창에서 전부 관리 (폴더형 사이드바 · 프리셋 합치기)

- **왼쪽 사이드바 = 메뉴 전체**: 도구 / 도면·출력 / 기본 프리셋(카테고리별) / 내 프리셋을 접이식 폴더로 정리. 상단 검색창으로 프리셋·도구를 한 번에 검색. 접힘 상태는 기억됨.
- **도구 폴더**: 면 → 패널(두께 입력칸 포함), 공간 분할 + 도어, 선택 가구 불러오기, 선택 가구 재생성을 창에서 바로 실행.
- **면 → 패널 도구 개선**: Kabinet 가구 부재 면에서도 동작(부재는 그대로 두고 바깥쪽에 새 패널 추가). 우클릭 메뉴로 9/12/15/18/20/25T 선택, Enter로 두께 입력 창, 커서 옆에 사용법 표시, 마지막 두께 기억.
- **프리셋 합치기**: 프리셋 오른쪽 ＋ 버튼으로 추가 → 순서 조정 → "합쳐서 불러오기"로 가로(런) 한 가구로 결합. 공통 높이 지정 가능. 세로로 2단 이상 쌓인 프리셋(TV장·화장대 등)은 합칠 수 없다고 안내.
- **내 프리셋 폴더**: 저장 시 "폴더" 칸을 채우면 사이드바에 폴더로 묶임(내부적으로 `폴더/이름`). 사이드바에서 바로 삭제.
- **직접 모델링한 가구 도면**: 선택 → 발주도면 DXF, 선택 → 재단목록 CSV(하위 판재별 두께×폭×길이·수량 집계)를 창 안에서 실행.
- 기본 프리셋 27종 전체를 스키마 검증 통과 확인. 선반 스팬 800mm 초과 프리셋(주방 하부장·신발장·TV장·오픈 선반장)은 선반을 25T로 변경.
- 기본 창 폭 720px (좌측 사이드바 + 우측 본문).
- **메뉴 단순화**: Extensions > Kabinet 메뉴와 툴바는 **"Kabinet 열기"** 하나. 면 → 패널·공간 분할 등은 창 안 사이드바에서 실행 (예전 메뉴의 "면 → 18T 패널"은 창이 아니라 모델링 도구라 눌러도 창이 안 떴음).
- **GitHub에서 업데이트가 실제로 GitHub에서 받음**: master의 `kabinet.rbz`를 내려받아 `Sketchup.install_from_archive`로 설치 (기존엔 개발자 PC 로컬 폴더에서 복사하던 기능이라 다른 PC에선 실패). 창 사이드바 "설정 · 업데이트" 폴더에서도 실행 가능.
  - ⚠ v1.10.0 이하에서 넘어올 때는 이 기능이 없으므로 **한 번만** `kabinet.rbz`를 Window > Extension Manager > Install Extension으로 직접 설치하세요. 그 다음부터는 메뉴 업데이트로 됩니다.
- 창 열기 실패 시 원인을 메시지로 표시, 이미 열려 있으면 앞으로 가져옴.

## v1.10.0 — 면 → 18T 패널 / 공간 분할 + 도어 균등

메뉴: Extensions > Kabinet — 카케이스 생성기

**면 → 18T 패널 (면 클릭)**
- 마우스를 올린 면은 연한 파란색으로 채워지고, 누르고 있는 동안 진한 파란색으로 잡힙니다. 버튼을 놓으면 생성됩니다. 공간 분할 도구도 같으며, 칸막이·도어 미리보기는 반투명 주황·초록으로 채워집니다.
- 판재(두께가 있는 그룹/솔리드)의 면을 클릭하면 반대편 평행면까지 거리를 두께로 인식하고, 클릭한 면을 기준으로 18T 패널로 다시 만듭니다. 원본이 단순 판재 그룹이면 교체됩니다(Ctrl+Z로 복원).
- 두께 없는 면(사각형만 그린 상태)은 보이는 쪽으로 18T를 돌출합니다. Tab: 방향 반전. VCB에 숫자(mm)를 입력하면 이후 두께가 바뀝니다.
- Kabinet 어셈블리 부재는 수정하지 않습니다(‘선택 어셈블리 편집’ 사용).

**공간 분할 + 도어 균등 (공간 클릭)** — 툴바 'Kabinet' 버튼 또는 메뉴
- 캐비닛 안쪽 면(뒷판·측판 안쪽 등)에 마우스를 올리면 6방향 레이캐스트로 내부 공간을 인식해 파란 박스를 보여주고, 현재 설정의 칸막이(주황)와 도어(초록) 미리보기가 함께 나옵니다. 전면이 열려 있으면 이웃 판의 앞끝에 맞춥니다.
- 클릭 한 번으로 칸막이(기본 18T)와 도어(기본 20T)가 균등 분할되어 생성됩니다. 설정은 키로 바로 바꾸고 다음 실행에도 기억됩니다.
  - ↑/↓ 또는 숫자 입력(VCB): 칸 수 / Tab: 세로 칸막이↔가로 선반 / ←/→: 도어 오버레이·인셋·없음 / Enter: 칸막이·도어 두께 설정
- 도어는 칸마다 1장, 갭은 기존 Fitting 기준(외곽 2mm, 사이 3mm). 폭 600mm 초과 시 경고합니다.
- 생성물은 ‘공간 분할’ 그룹 안에 칸막이/도어 그룹으로 들어가며, 어셈블리 재생성·재단표와는 연동되지 않습니다.

검증: 균등 분할·도어 치수 계산은 `ruby test/space_divider_test.rb`로 검증했습니다. SketchUp API(레이캐스트·pushpull 등) 부분은 실제 SketchUp에서 확인이 필요합니다.

## v1.9.0 — SketchUp 실시간 미리보기

설치 파일: `build/kabinet-1.9.0.rbz`. 기존 루트의 `kabinet.rbz`는 이전 패키지이며 이번 변경을 포함하지 않습니다.

1. SketchUp의 확장 관리자 → 확장 설치 → `build/kabinet-1.9.0.rbz` 선택.
2. 작업을 저장하고 SketchUp을 재시작합니다.
3. Kabinet 창에서 프리셋을 선택합니다. ‘SketchUp 실시간 미리보기’는 기본으로 켜져 있습니다.
4. 폭·깊이·높이·문·선반 등을 바꾸고 약 0.35초 기다리면 SketchUp에 파란 선으로 변경안이 보입니다.
5. 모듈 입력칸을 선택하면 그 모듈은 주황색입니다. ‘문·전판 숨김’으로 내부 선을 확인하고 정면/측면/평면/입체 버튼으로 시점을 전환합니다.
6. 새 가구는 ‘가구 생성’, 불러온 가구는 ‘수정 적용’으로 확정합니다. 생성 직후부터는 같은 가구를 수정합니다.
7. ‘미리보기 종료’, Esc, 다른 도구 선택, 창 닫기로 종료합니다. 입력값은 유지되며 미리보기 자체는 원본 가구를 변경하지 않습니다.

기존 가구 수정: 가구 그룹 선택 → ‘선택 불러오기’ → 치수 변경 → ‘수정 적용’. 그룹 내부 편집 중에는 먼저 편집을 종료하세요. 다른 SketchUp 문서로 바꾸면 창을 다시 열거나 해당 문서에서 ‘선택 불러오기’를 실행하세요.

### 표시와 기본값

- 미리보기는 실제 Assembly/Builder 계산 경로를 메모리에서 실행한 선 표시입니다. 재질 렌더링이나 문 열림 애니메이션은 포함하지 않습니다.
- 기존 모델은 숨기거나 지우지 않습니다. 기존 모델 위에 파란 변경안을 겹쳐 비교합니다. ‘문·전판 숨김’도 파란 미리보기 선에만 적용됩니다.
- SketchUp 좌상단 크기는 실제 선 외곽 기준이며 손잡이를 포함합니다. 입력창의 기존 정면 미리보기 깊이는 몸통 기준입니다.
- 신규 기본 몸통 18T, EP·도어 및 일반 서랍 전판 20T. 불러온 기존 가구/저장 프리셋의 명시적 두께는 유지합니다.
- 전체 깊이 변경 시 모듈 깊이를 기존 비율대로 조정합니다. 전체 높이에는 상부 EP 두께도 반영합니다.
- 미리보기 그래픽은 모델 엔티티·재단표·저장 파일·실행 취소 이력에 들어가지 않습니다. ‘모델 반영’ 단계에서만 실제 생성/수정 작업을 실행합니다.
- 일반 SketchUp 도구로 전환하면 미리보기가 종료됩니다. 입력창의 체크를 다시 켜면 재개됩니다.

### 이번 검증과 남은 확인

자동 검증 완료: SketchUp 2022에 포함된 Ruby 2.7.2 런타임으로 Ruby 문법 검사, 27개 프리셋의 생성 계산, 실제 인치 단위 변환, 회전·내부 표시·모듈 구분·종료·원본 불변 검사. 기존 도면 투영 테스트 통과.

브라우저 검사 완료: 연속 입력 합치기, 18/20/20 기본값, 전체 폭·깊이 반영, 빈 입력 처리, 오래된 응답 무시, 생성 후 동일 가구 수정, 오류 후 재시도, 기존 두께 유지. 500×740 입력창 화면 확인.

검증 한계: Ruby 검사는 SketchUp API 대신 테스트용 기하/모델 객체를 사용했고 브라우저는 SketchUp 연결을 모의했습니다. 실제 SketchUp 화면의 선 표시, 도구 전환, 생성·수정 실행 취소는 설치 후 아래 순서로 확인해야 합니다.

- 붙박이장 → 폭 1200에서 1500 → 파란 가구의 폭 변경 확인.
- 내부 보기 및 정면/측면/평면/입체 전환 확인.
- 생성 → 다시 폭 변경 → 수정 적용 → 가구가 하나만 남는지 확인.
- 기존 가구를 불러와 치수 변경 후 Esc → 원본 치수 유지 확인.
- 적용 후 Ctrl+Z 한 번으로 이전 가구 치수 복원 확인.
- 미리보기 중 창 닫기 → 파란 선 제거 및 모델 저장에 임시 가구가 없는지 확인.

개발 검증 실행:

```powershell
node test/export_furniture_presets.js test/presets-check.json
$env:KABINET_PRESETS_JSON = (Resolve-Path test/presets-check.json).Path
python test/run_with_sketchup_ruby.py test/live_preview_test.rb
python test/run_with_sketchup_ruby.py test/group_projection_test.rb
python build/package.py
```

`run_with_sketchup_ruby.py`는 SketchUp 프로그램을 실행하거나 현재 열린 모델에 연결하지 않습니다. 다른 설치 경로는 `KABINET_SKETCHUP_DIR` 환경 변수로 지정합니다. 일반 Ruby가 있다면 `ruby test/live_preview_test.rb`로도 실행할 수 있습니다.

아래 Phase 체크리스트는 이전 버전 기록입니다. 특히 두께·전체 폭·스케일 설명은 위 v1.9.0 안내를 우선합니다.

## 설치 방법

### 방법 A — .rbz 패키징 후 설치 (정식)
1. 개발 PC에 rubyzip 설치 (최초 1회):
   ```
   gem install rubyzip
   ```
2. 프로젝트 루트에서 실행:
   ```
   ruby build/package.rb
   ```
   → `kabinet.rbz` 생성됨.

3. SketchUp 실행 → **Extensions → Extension Manager → Install Extension**
4. `kabinet.rbz` 선택 → 설치 → SketchUp 재시작.

### 방법 B — 개발 중 직접 로드 (빠른 테스트)
SketchUp 루비 콘솔에서:
```ruby
load 'C:/Users/testos/Desktop/개인/스케치업 루비/kabinet_loader.rb'
```

---

## Phase별 검증 체크리스트

### Phase 1 검증 — 단일 캐리스 생성

```ruby
# 루비 콘솔
Kabinet::Commands::Generate.run_carcase(
  width: 900, depth: 580, height: 720, thickness: 18
)
```

**확인 사항:**
- 모델에 그룹 1개 생성됨
- 그룹 내 패널 그룹 5개 (좌측, 우측, 하판, 상판, 뒷판)
- Tape Measure로 측판 두께: 정확히 18mm
- 측판 높이: 720mm, 깊이: 580mm

### Phase 2 검증 — 화장대 (적층 어셈블리)

```ruby
spec = {
  "version" => 1,
  "name"    => "화장대 테스트",
  "width"   => 900,
  "max_depth" => 350,
  "ep" => { "left" => true, "right" => true, "thickness" => 18 },
  "top_panel" => { "thickness" => 20 },
  "base_height" => 0,
  "modules" => [
    { "kind"           => "shelf_module",
      "width"          => 900,
      "depth"          => 250,
      "height"         => 450,
      "body_thickness" => 18,
      "back_thickness" => 9,
      "door_config"    => "pair",
      "door_thickness" => 18,
      "shelves"        => [],
      "accessories"    => [] },
    { "kind"           => "drawer_module",
      "width"          => 900,
      "depth"          => 350,
      "height"         => 230,
      "body_thickness" => 18,
      "back_thickness" => 9,
      "drawer_count"   => 2,
      "drawer_type"    => "undermount",
      "drawer_thickness" => 18 }
  ]
}
Kabinet::Commands::Generate.run_assembly(spec)
```

**확인 사항:**
- 외부 치수: W=936mm (900 + EP 18×2), D=350mm, H=700mm (450+230+20)
- 하부 선반 모듈은 깊이 250mm → 앞쪽으로 100mm 들어감 (뒷면 정렬)
- EP 양쪽 측면 마감 보임
- 쌍 도어 2개 생성 (하부 모듈)
- 서랍 전판 2개 + 서랍 박스 2개 (상부 모듈)

### Phase 3 검증 — 재생성

```ruby
# 1. 화장대 생성 (위 스펙)
# 2. 생성된 그룹 선택
# 3. 상판 두께를 20→30으로 변경하여 재생성
spec_update = { "top_panel" => { "thickness" => 30 } }
Kabinet::Commands::Regenerate.run(spec_update)
```

**확인 사항:**
- 총 높이 = 710mm (30mm 상판으로 변경)
- 측판 두께는 여전히 18mm 유지
- Undo (Ctrl+Z) 한 번으로 되돌아감

**Scale 차단 테스트:**
- 어셈블리 그룹 선택 → S키로 스케일 시도
- 크기 변경이 무효화되고 메시지박스 표시됨

### Phase 4 검증 — 도면 출력

```ruby
# 어셈블리 선택 후
Kabinet::Commands::Export.run(views: [:front, :right, :top, :section])
```

**확인 사항:**
- 저장 폴더 선택 다이얼로그 표시
- PNG 4개 생성 (정면/우측/평면/단면)
- PDF 1개 생성 (4페이지)
- 각 PNG에 치수선 (폭/높이/깊이) 표기됨

### HtmlDialog 검증

1. Extensions → Kabinet → 새 어셈블리
2. 어셈블리 탭에서 이름/폭/깊이 입력
3. 모듈 구성 탭 → 선반/수납 모듈 추가 → 서랍 모듈 추가
4. 서랍 모듈 카드: 서랍 수 2, 언더레일 선택
5. 선반 모듈 카드: 도어 = 양개문, 선반 추가 (200mm)
6. 어셈블리 탭 → [생성] 클릭 → 모델에 가구 생성 확인

---

## 폴더 구조 (최종)

```
스케치업 루비/
├── kabinet_loader.rb        ← Extension 등록 진입점
├── kabinet/
│   ├── main.rb              ← require 체인 + 메뉴 설치
│   ├── version.rb
│   ├── constants.rb         ← 철물/두께 기본값
│   ├── core/
│   │   ├── panel.rb
│   │   ├── carcase.rb
│   │   ├── door_panel.rb
│   │   ├── ep_finish_panel.rb
│   │   ├── accessory.rb
│   │   ├── shelf_module.rb
│   │   ├── drawer_module.rb
│   │   └── assembly.rb
│   ├── geometry/
│   │   ├── transforms.rb
│   │   ├── builder.rb
│   │   └── joinery.rb
│   ├── persistence/
│   │   ├── attributes.rb
│   │   └── schema.rb
│   ├── ui/
│   │   ├── dialog.rb
│   │   ├── menu.rb
│   │   └── web/
│   │       ├── index.html
│   │       ├── styles.css
│   │       ├── app.js
│   │       └── modules.js
│   ├── output/
│   │   ├── dimensions.rb
│   │   ├── views.rb
│   │   ├── png_export.rb
│   │   └── pdf_bundler.rb
│   └── commands/
│       ├── generate.rb
│       ├── regenerate.rb
│       └── export.rb
└── build/
    └── package.rb
```
