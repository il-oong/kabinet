# Kabinet — 설치 및 검증 가이드

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
