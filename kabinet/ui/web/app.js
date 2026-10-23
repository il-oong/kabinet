/* =====================================================================
   Kabinet — Main application state and bridge layer
   ===================================================================== */

/* ── 가구 유형 기본 프리셋 ──────────────────────────────────────────────
   width/max_depth/base_height 는 어셈블리 치수.
   모듈 width 는 어셈블리 width 와 동일하게 설정.
   총 높이 계산: base_height + Σ(module.height) + top_panel.thickness
================================================================== */
const RUN_MODE_ENABLED = false;   // 수평 런 모드: 완성 전까지 UI 에서 숨김 (프리셋·토글)
// 여러 종류 장을 한 덩어리로 묶은 프리셋 — 낱개 장 + 배치로 대체할 때까지 사이드바에서 숨김
const BUNDLED_PRESETS = ['desk_with_pedestal', 'desk_with_side_cabinet', 'kids_desk_upper',
                         'bed_surround', 'bed_surround_with_bridge', 'kids_bed_single'];

const FURNITURE_PRESETS = {
  wardrobe: {
    name: '붙박이장',
    furniture_type: 'wardrobe',
    width: 900, max_depth: 580, base_height: 50,
    wardrobe_layout: 'long',   // 내부 구성: long / double / shelves / drawer_hang
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20, cover_fronts: false },   // 도어가 측면 EP 앞까지 덮음
    top_panel: null,   // 몸통 천판이 최상단 — 도어 윗선이 최종 높이와 맞음
    // 총 높이: 50(걸레받이) + 2250(몸통) = 2300mm
    modules: [
      { kind: 'shelf_module', width: 860, depth: 580, height: 2250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1000, depth_inset: 75, diameter: 32 }
        ]
      }
    ],
    _info: '표준 붙박이장 W900×D580×H2300 | 걸레받이50 + 양개여닫이(푸시) · 내부 구성은 아래 "내부 구성"에서 선택'
  },

  // ── 붙박이장 구성표(오톤도) 기반 몸통 — 도어 1장 폭 400~550 기준 ───────────────
  wardrobe_1door: {
    name: '붙박이장 1도어 (선반장)',
    furniture_type: 'wardrobe',
    width: 540, max_depth: 580, base_height: 50,
    wardrobe_layout: 'shelves',
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20, cover_fronts: false },
    top_panel: null,
    modules: [
      { kind: 'shelf_module', width: 500, depth: 580, height: 2250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'single', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [], accessories: []
      }
    ],
    _info: '붙박이장 1도어 W540(EP 포함)×D580×H2300 | 선반 6단 — 구성표 도어 5개의 가운데 좁은 몸통'
  },
  wardrobe_long_drawer: {
    name: '붙박이장 2도어 (긴옷 + 서랍 3단)',
    furniture_type: 'wardrobe',
    width: 1000, max_depth: 580, base_height: 50,
    wardrobe_layout: 'long_drawer',
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20, cover_fronts: false },
    top_panel: null,
    modules: [
      { kind: 'shelf_module', width: 960, depth: 580, height: 2250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [], accessories: []
      }
    ],
    _info: '붙박이장 2도어 W1000×D580×H2300 | 상부 선반·행거 + 바닥 내부서랍 3단 — 구성표 도어 3·4개의 왼쪽 몸통'
  },
  wardrobe_hang_split: {
    name: '붙박이장 2도어 (행거 + 하부 분할)',
    furniture_type: 'wardrobe',
    width: 1000, max_depth: 580, base_height: 50,
    wardrobe_layout: 'hang_split',
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20, cover_fronts: false },
    top_panel: null,
    modules: [
      { kind: 'shelf_module', width: 960, depth: 580, height: 2250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [], accessories: []
      }
    ],
    _info: '붙박이장 2도어 W1000×D580×H2300 | 상부 행거 + 아래 좌 칸 / 우 선반 4단 — 구성표 도어 5·6개 몸통'
  },
  wardrobe_top_box: {
    name: '붙박이장 적층 상부장',
    furniture_type: 'wardrobe_top',
    width: 1000, max_depth: 580, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20, cover_fronts: false },
    top_panel: null,
    modules: [
      { kind: 'shelf_module', width: 960, depth: 580, height: 250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [], accessories: []
      }
    ],
    _info: '적층 상부장 W1000×D580×H250 | 2300 붙박이장 위에 얹어 2550 (구성표 H-2550 적층) — 높이는 천장에 맞춰 조정'
  },
  wardrobe_vanity_500: {
    name: '붙박이장 사이 화장대 500',
    furniture_type: 'wardrobe_vanity',
    width: 500, max_depth: 580, base_height: 50,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    modules: [
      { kind: 'drawer_module', width: 500, depth: 580, height: 720,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 4, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'v_gap', height: 280, label: '화장대 개방 니치 (간접조명)' },
      { kind: 'shelf_module', width: 500, depth: 580, height: 1250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'single', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [{ height_from_bottom: 420, thickness: 18, depth_inset: 20 }, { height_from_bottom: 830, thickness: 18, depth_inset: 20 }], accessories: []
      }
    ],
    _info: '장 사이 화장대 W500×D580×H2300 | 서랍 4단 + 개방 니치 + 거울 도어장 (거울·조명은 모델링 안 함). 양옆 장 사이에 끼워 배치'
  },
  wardrobe_vanity_900: {
    name: '붙박이장 사이 화장대 900',
    furniture_type: 'wardrobe_vanity',
    width: 900, max_depth: 580, base_height: 50,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    modules: [
      { kind: 'shelf_module', width: 900, depth: 580, height: 430,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [], accessories: []
      },
      { kind: 'drawer_module', width: 900, depth: 580, height: 320,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'v_gap', height: 300, label: '화장대 개방 니치 (간접조명)' },
      { kind: 'shelf_module', width: 900, depth: 580, height: 1200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [{ height_from_bottom: 400, thickness: 18, depth_inset: 20 }, { height_from_bottom: 800, thickness: 18, depth_inset: 20 }], accessories: []
      }
    ],
    _info: '장 사이 화장대 W900×D580×H2300 | 도어 수납 + 서랍 2단 + 개방 니치 + 거울 도어장 (거울·조명은 모델링 안 함)'
  },
  kids_bed_front_shelf: {
    name: '침대 앞 오픈 책장 (D280)',
    furniture_type: 'kids_shelf',
    width: 1138, max_depth: 280, base_height: 50,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 보관함의 1120 침대앞 오픈장 280 (1138×280×2407) 치수 기준. 칸 구성은 추정
    modules: [
      { kind: 'shelf_module', width: 1138, depth: 280, height: 2350,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        vertical_dividers: [{ x: 542, thickness: 18 }],
        cell_shelves: [0, 1].flatMap(c => [1, 2, 3, 4, 5].map(i => ({ cell: c, height_from_bottom: 18 + Math.round(2314 / 6 * i), thickness: 18, depth_inset: 0 }))),
        cell_drawers: [], shelves: [], accessories: [] }
    ],
    _info: '침대 앞 오픈 책장 W1138×D280×H2400 | 세로 2칸 × 6단 — 자녀방 구성표의 침대 앞 책장'
  },

  // ── 주방 하부장: 받침 150 + 몸통 680 = 830mm, 상판 20 을 따로 올려 850 (국내 일반 규격). 몸통 위는 뚫려 있고 앞뒤 목대만 ──
  kitchen_base: {
    name: '주방 하부장 (도어 수납)',
    furniture_type: 'kitchen_base',
    width: 900, max_depth: 580, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판(인조대리석 등)은 '주방 상판 설치'로 따로 — 몸통 위는 목대만
    modules: [
      { kind: 'shelf_module', width: 900, depth: 580, height: 680, open_top: true, door_drop_mm: 20,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [{ height_from_bottom: 330, thickness: 18, depth_inset: 20 }], accessories: []
      }
    ],
    _info: '하부장 W900×D580×H830(+상판 20 = 850) | 양개도어 + 선반 1 · 상부 개방(목대)'
  },
  kitchen_sink: {
    name: '싱크장',
    furniture_type: 'kitchen_sink',
    width: 900, max_depth: 580, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판(인조대리석 등)은 '주방 상판 설치'로 따로 — 몸통 위는 목대만
    modules: [
      { kind: 'shelf_module', width: 900, depth: 580, height: 680, open_top: true, door_drop_mm: 20,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [], accessories: []
      }
    ],
    _info: '싱크장 W900×D580×H830(+상판 20 = 850) | 선반 없음(싱크볼·배관) · 양개도어 · 상부 개방(목대)'
  },
  kitchen_cook: {
    name: '조리장 (2단 서랍장)',
    furniture_type: 'kitchen_cook',
    width: 900, max_depth: 580, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판(인조대리석 등)은 '주방 상판 설치'로 따로 — 몸통 위는 목대만
    modules: [
      { kind: 'drawer_module', width: 900, depth: 580, height: 680, open_top: true, door_drop_mm: 20,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '조리장·2단 서랍장 W900×D580×H830(+상판 20 = 850) | 깊은 서랍 2단 · 쿡탑 컷아웃은 상판에서'
  },
  kitchen_drawer2_inner: {
    name: '2단 서랍장 + 속서랍',
    furniture_type: 'kitchen_drawer2_inner',
    width: 900, max_depth: 580, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판(인조대리석 등)은 '주방 상판 설치'로 따로 — 몸통 위는 목대만
    modules: [
      { kind: 'drawer_module', width: 900, depth: 580, height: 680, open_top: true, door_drop_mm: 20, inner_drawer: true,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '2단 서랍장 + 속서랍 W900×D580×H830(+상판 20 = 850) | 맨 위 서랍 안에 낮은 속서랍 1'
  },
  kitchen_drawer3: {
    name: '3단 서랍장',
    furniture_type: 'kitchen_drawer3',
    width: 600, max_depth: 580, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판(인조대리석 등)은 '주방 상판 설치'로 따로 — 몸통 위는 목대만
    modules: [
      { kind: 'drawer_module', width: 600, depth: 580, height: 680, open_top: true, door_drop_mm: 20,
        drawer_ratios: [2, 1, 1],   // 아래 → 위: 깊은 서랍 1 + 얕은 서랍 2
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '3단 서랍장 W600×D580×H830(+상판 20 = 850) | 얕은 서랍 2 + 깊은 서랍 1 (아래)'
  },
  kitchen_pullout: {
    name: '인출망장',
    furniture_type: 'kitchen_pullout',
    width: 300, max_depth: 580, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판(인조대리석 등)은 '주방 상판 설치'로 따로 — 몸통 위는 목대만
    modules: [
      { kind: 'drawer_module', width: 300, depth: 580, height: 680, open_top: true, door_drop_mm: 20,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 1, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '인출망장 W300×D580×H830(+상판 20 = 850) | 전판 1장이 통째로 앞으로 나오는 세로 인출 (내부 인출망은 철물 — 모델링 안 함). 폭 150~400'
  },
  kitchen_filler: {
    name: '휠라장 (좁은 마감장)',
    furniture_type: 'kitchen_filler',
    width: 150, max_depth: 580, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판(인조대리석 등)은 '주방 상판 설치'로 따로 — 몸통 위는 목대만
    modules: [
      { kind: 'shelf_module', width: 150, depth: 580, height: 680, open_top: true, door_drop_mm: 20,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'single', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [{ height_from_bottom: 330, thickness: 18, depth_inset: 20 }], accessories: []
      }
    ],
    _info: '휠라장 W150×D580×H830(+상판 20 = 850) | 남는 폭 메움용. 폭 100~300'
  },
  kitchen_island: {
    name: '아일랜드장 (서랍형 유닛)',
    furniture_type: 'kitchen_island',
    width: 940, max_depth: 600, base_height: 150,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,   // 상판은 따로 — 식탁형이면 상판을 뒤로 250 이상 내밀어 다리 공간
    // 아일랜드는 서랍형 하부장 유닛을 나란히 놓고 양끝·뒷면을 마감판으로 싸는 구성.
    // 이 프리셋은 그 유닛 1개 (EP 20 + 900 + EP 20). 여러 개 배치해 길이를 만든다.
    modules: [
      { kind: 'drawer_module', width: 900, depth: 600, height: 680, open_top: true, door_drop_mm: 20,
        drawer_ratios: [2, 1, 1],
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '아일랜드 서랍형 유닛 W940(EP 포함)×D600×H830(+상판) | 얕은 서랍 2 + 깊은 서랍 1, 양옆 EP. 뒷면 마감판·상판은 별도'
  },

  kitchen_upper: {
    name: '주방 상부장',
    furniture_type: 'kitchen_upper',
    width: 900, max_depth: 320, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 총 높이: 0 + 700 = 700mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 320, height: 700, center_stile: true, door_drop_mm: 20,   // 처짐 방지 중앙 목대
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 15, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '주방 상부장 W900×D320×H700 | 바닥 설치 높이 1500mm 위 권장'
  },

  vanity: {
    name: '화장대',
    furniture_type: 'vanity',
    width: 900, max_depth: 350, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 20 },
    // 총 높이: 0 + 480(서랍3단) + 200(오픈선반) + 20(상판) = 700mm
    // 하단 서랍: 주수납. 상단 오픈선반: 화장품·소품 진열.
    // 접합부(서랍→선반) suppress_bottom 으로 이중패널 방지.
    modules: [
      { kind: 'drawer_module', width: 900, depth: 350, height: 480,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 900, depth: 350, height: 200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [],
        accessories: []
      }
    ],
    _info: '화장대 W900×D350×H700 | 서랍 3단(480) + 오픈 선반(200) + 상판20. 접합부 단일 패널'
  },

  shoe_cabinet: {
    name: '신발장',
    furniture_type: 'shoe_cabinet',
    width: 900, max_depth: 350, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1782 + 18 = 1800mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 350, height: 1782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 160, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 380, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 600, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 820, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1040, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1260, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1480, thickness: 18, depth_inset: 20 }
        ],
        accessories: []
      }
    ],
    _info: '신발장 W900×D350×H1800 | 선반 7개 (220mm 피치). 푸시오픈 권장'
  },

  bookshelf: {
    name: '책장',
    furniture_type: 'bookshelf',
    width: 900, max_depth: 300, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1782 + 18 = 1800mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 300, height: 1782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        // 책 하중 기준: 864mm 스팬은 18T 처짐 — 25T 사용 (실무 표준)
        shelves: [
          { height_from_bottom: 280, thickness: 25, depth_inset: 0 },
          { height_from_bottom: 560, thickness: 25, depth_inset: 0 },
          { height_from_bottom: 840, thickness: 25, depth_inset: 0 },
          { height_from_bottom: 1120, thickness: 25, depth_inset: 0 },
          { height_from_bottom: 1450, thickness: 25, depth_inset: 0 }
        ],
        accessories: []
      }
    ],
    _info: '오픈 책장 W900×D300×H1800 | 선반 5개 25T (책 하중 대응)'
  },

  tv_unit: {
    name: 'TV장',
    furniture_type: 'tv_unit',
    width: 1800, max_depth: 450, base_height: 80,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 25 },
    // 총 높이: 80 + 200 + 495 + 25 = 800mm (입식 표준 TV장)
    // 실무 보정: 1764 폭 통짜 서랍은 레일 하중 불가 → 3칸 분할 서랍.
    //            상부는 878mm/짝 여닫이 대신 중앙 분할 오픈 선반.
    modules: [
      { kind: 'shelf_module', width: 1764, depth: 450, height: 200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [], accessories: [],
        vertical_dividers: [{ x: 564, thickness: 18 }, { x: 1146, thickness: 18 }],
        cell_shelves: [],
        cell_drawers: [
          { cell: 0, count: 1, type: 'undermount', thickness: 18 },
          { cell: 1, count: 1, type: 'undermount', thickness: 18 },
          { cell: 2, count: 1, type: 'undermount', thickness: 18 }
        ]
      },
      { kind: 'shelf_module', width: 1764, depth: 450, height: 495,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [], accessories: [],
        vertical_dividers: [{ x: 573, thickness: 18 }],
        cell_shelves: [
          { cell: 0, height_from_bottom: 240, thickness: 18, depth_inset: 0 },
          { cell: 1, height_from_bottom: 240, thickness: 18, depth_inset: 0 }
        ],
        cell_drawers: []
      }
    ],
    _info: 'TV장 W1800×D450×H800 | 하부 서랍 3칸(분할) + 상부 오픈 2칸. 입식형'
  },

  // ── 카탈로그 신규 프리셋 ─────────────────────────────────────────────────

  display_800: {
    name: '수납장 800',
    furniture_type: 'display_800',
    width: 800, max_depth: 400, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    modules: [
      { kind: 'shelf_module', width: 800, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 300, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 600, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 850, thickness: 18, depth_inset: 20 }
        ],
        accessories: []
      }
    ],
    _info: '수납장 W800×D400×H1050 | 양개문·선반3개. 거실/서재 범용 수납'
  },

  display_1200: {
    name: '수납장 1200',
    furniture_type: 'display_1200',
    width: 1200, max_depth: 400, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    modules: [
      // 실무 보정: 1164 스팬 18T 선반 처짐 → 중앙 분할판 + 셀 선반
      { kind: 'shelf_module', width: 1200, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [], accessories: [],
        vertical_dividers: [{ x: 573, thickness: 18 }],
        cell_shelves: [
          { cell: 0, height_from_bottom: 300, thickness: 18, depth_inset: 20 },
          { cell: 0, height_from_bottom: 600, thickness: 18, depth_inset: 20 },
          { cell: 0, height_from_bottom: 850, thickness: 18, depth_inset: 20 },
          { cell: 1, height_from_bottom: 300, thickness: 18, depth_inset: 20 },
          { cell: 1, height_from_bottom: 600, thickness: 18, depth_inset: 20 },
          { cell: 1, height_from_bottom: 850, thickness: 18, depth_inset: 20 }
        ],
        cell_drawers: []
      }
    ],
    _info: '수납장 W1200×D400×H1050 | 양개문·중앙분할·셀선반 3+3. 거실/서재 범용'
  },

  drawer_tower: {
    name: '서랍장 타워',
    furniture_type: 'drawer_tower',
    width: 400, max_depth: 450, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm (서랍 4단)
    modules: [
      { kind: 'drawer_module', width: 400, depth: 450, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 4, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '서랍장 타워 W400×D450×H1050 | 서랍 4단. 침실/드레스룸 범용'
  },

  wardrobe_sliding: {
    name: '슬라이딩 붙박이장',
    furniture_type: 'wardrobe_sliding',
    width: 1600, max_depth: 600, base_height: 50,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 총 높이: 100 + 1982 + 18 = 2100mm
    modules: [
      { kind: 'shelf_module', width: 1600, depth: 600, height: 2250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'sliding', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        // 실무 보정: 2단 행거 표준 높이 (상단 ~1850, 하단 ~930 — 상의 2단걸이)
        // 기존 500/1000은 옷이 바닥에 끌리는 높이였음. 1564 스팬 선반은 처짐 → 제거.
        // 1524 스팬 → 25T 선반. 봉은 선반 바로 아래(70)에 달아 옷걸이가 선반에 닿지 않게
        shelves: [
          { height_from_bottom: 1058, thickness: 25, depth_inset: 20 },
          { height_from_bottom: 1902, thickness: 25, depth_inset: 20 }
        ],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1832, depth_inset: 75, diameter: 32 },
          { kind: 'hanging_rod', height_from_bottom: 988,  depth_inset: 75, diameter: 32 }
        ]
      }
    ],
    _info: '슬라이딩 붙박이장 W1600×D600×H2300 | 걸레받이50 · 미닫이 2짝·상부·중간 선반 + 행거 2단(1832/988). 드레스룸'
  },

  // ── 책상 프리셋 ─────────────────────────────────────────────────────────

  desk_basic: {
    name: '기본 책상',
    furniture_type: 'desk_basic',
    width: 1400, max_depth: 700, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,  // 상판이 desk_module 자체에 포함됨
    // 총 높이 = 0 + 750 = 750mm (상판 높이 기준)
    modules: [
      { kind: 'desk_module', width: 1400, depth: 700, height: 750,
        top_thickness: 25, leg_type: 'box', leg_w: 30, leg_d: 30,
        leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false,
        pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '기본 책상 W1400×D700×H750 | 사각 다리 4개. 상판두께 25mm'
  },

  desk_with_pedestal: {
    name: '책상 + 지지 서랍장',
    furniture_type: 'desk_with_pedestal',
    width: 1400, max_depth: 700, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 우측 페데스탈 W450으로 지지 → 우측 다리 생략
    modules: [
      { kind: 'desk_module', width: 1400, depth: 700, height: 750,
        top_thickness: 25, leg_type: 'box', leg_w: 30, leg_d: 30,
        leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false,
        pedestal: {
          enabled: true, position: 'right', width: 450,
          drawer_count: 3, drawer_type: 'undermount'
        },
        under_unit: {
          enabled: true, position: 'left', width: 350, height: 120, drawer_count: 1,
          drawer_type: 'undermount'
        },
        material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '책상 W1400×D700×H750 | 우측 페데스탈(서랍3단)+좌측 상판 하부 서랍'
  },

  desk_l_shape: {
    name: 'L자 책상 (런 모드)',
    furniture_type: 'desk_l_shape',
    width: 2100, max_depth: 700, base_height: 0,
    material: 'LPM',
    run_mode: true, run_height: 725,  // 상판포함 750 → top_thickness=25
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 25 },     // 런 공통 상판
    // 런 모드: 책상(1400) + 코너 선반(700) 배치
    modules: [
      { kind: 'desk_module', width: 1400, depth: 700, height: 725,
        top_thickness: 25, leg_type: 'box', leg_w: 30, leg_d: 30,
        leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false,
        pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'desk_module', width: 700, depth: 700, height: 725,
        top_thickness: 25, leg_type: 'box', leg_w: 30, leg_d: 30,
        leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false,
        pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: 'L자 책상 W2100×D700 | 런 모드 수평 배열. 상판 25mm 포함 총 높이 750mm'
  },

  // ── 자유 설계 선반/격자 프리셋 ────────────────────────────────────────

  shelf_grid: {
    name: '격자형 수납장',
    furniture_type: 'shelf_grid',
    width: 1200, max_depth: 400, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    // 내부: 세로 3칸(분할 2개) → 좌칸 선반, 중칸 서랍, 우칸 선반
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [],
        accessories: [],
        // 내부 폭 = 1200 - 36 = 1164mm → 분할 at 388mm, 788mm
        vertical_dividers: [
          { x: 388, thickness: 18 },
          { x: 788, thickness: 18 }
        ],
        // 셀 0 (좌, 370mm): 선반 2개
        // 셀 1 (중, 370mm): 서랍 3개
        // 셀 2 (우, 376mm): 선반 2개
        cell_shelves: [
          { cell: 0, height_from_bottom: 320, thickness: 18, depth_inset: 0 },
          { cell: 0, height_from_bottom: 640, thickness: 18, depth_inset: 0 },
          { cell: 2, height_from_bottom: 320, thickness: 18, depth_inset: 0 },
          { cell: 2, height_from_bottom: 640, thickness: 18, depth_inset: 0 }
        ],
        cell_drawers: [
          { cell: 1, count: 3, type: 'undermount', thickness: 18 }
        ]
      }
    ],
    _info: '격자형 수납장 W1200×D400×H1050 | 좌우 선반칸 + 중앙 서랍 3단'
  },

  // ── 수평 런 모드 프리셋 ───────────────────────────────────────────────────

  kitchen_run: {
    name: '주방 런 1800',
    furniture_type: 'kitchen_run',
    width: 1800, max_depth: 580, base_height: 80,
    material: 'LPM',
    run_mode: true,
    run_height: 780,          // 작업대 하부 내부 높이 (받침80+본체780+상판20=880mm)
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 20 },
    // 수평 배열: 600(서랍) + 600(선반도어) + 600(선반도어)
    // 총 외부 폭: 18(EP좌) + 1800 + 18(EP우) = 1836mm
    // 총 외부 높이: 80 + 660 + 20 = 760mm (작업대 높이)
    modules: [
      { kind: 'drawer_module', width: 600, depth: 580, height: 780,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 600, depth: 580, height: 780,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 18, depth_inset: 20 }],
        accessories: []
      },
      { kind: 'shelf_module', width: 600, depth: 580, height: 780,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 18, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '주방 런 1800mm | 서랍(600)+수납(600)+수납(600). 런높이 780 → 작업대 880mm'
  },

  // ── 침대장 (베드 서라운드) ────────────────────────────────────────────

  bed_surround: {
    name: '침대장',
    furniture_type: 'bed_surround',
    width: 2800, max_depth: 580, base_height: 80,
    has_kickboard: true,
    material: 'LPM',
    run_mode: true,
    run_height: 2020,   // 80(받침) + 2020(타워) = 2100mm 전체 높이
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,    // 전고 타워 — 상판 없음
    // 좌타워 600 + 침대 공간 1600(퀸사이즈) + 우타워 600 = 2800mm
    modules: [
      { kind: 'shelf_module', width: 600, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 500, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1000, thickness: 18, depth_inset: 20 }
        ],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1932, depth_inset: 75, diameter: 32 }
        ],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      },
      { kind: 'bed_gap', width: 1600, label: '침대 공간 (퀸 1600mm)',
        storage: true, platform_height: 350, bed_depth: 2000,
        drawer_count: 2, drawer_side: 'foot', lift_up_storage: false,
        material: 'LPM', door_material: 'LPM' },
      { kind: 'shelf_module', width: 600, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 400, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 800, thickness: 18, depth_inset: 20 }
        ],
        accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '침대장 W2800 (좌타워600 + 퀸침대1600 + 우타워600) | 전고 H2100mm'
  },

  bed_surround_with_bridge: {
    name: '침대장+브릿지',
    furniture_type: 'bed_surround_with_bridge',
    width: 2800, max_depth: 580, base_height: 80,
    has_kickboard: true,
    material: 'LPM',
    run_mode: true,
    run_height: 1200,   // 하부 타워 높이 (80+1200=1280mm → 침대 헤드와 같은 높이)
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },  // 브릿지 상판 (타워 위를 잇는 가로 패널)
    modules: [
      { kind: 'shelf_module', width: 600, depth: 580, height: 1200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 500, thickness: 18, depth_inset: 20 }],
        accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      },
      { kind: 'bed_gap', width: 1600, label: '침대 공간 (퀸 1600mm)',
        storage: true, platform_height: 350, bed_depth: 2000,
        drawer_count: 2, drawer_side: 'foot', lift_up_storage: false,
        material: 'LPM', door_material: 'LPM' },
      { kind: 'drawer_module', width: 600, depth: 580, height: 1200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', handle_hole_mm: 128,
        material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '침대장+브릿지 W2800 | 좌타워선반 + 퀸침대공간 + 우타워서랍3단. 상부 브릿지 연결'
  },

  // ── 자녀방 (Children's Room) ─────────────────────────────────────────
  // 보고서 기준 치수: 책상고 750mm, 붙박이장 2100mm, 상부장 H400 D280mm

  kids_wardrobe: {
    name: '자녀방 붙박이장',
    furniture_type: 'kids_wardrobe',
    width: 1200, max_depth: 580, base_height: 50,
    wardrobe_layout: 'double',   // 내부 구성: 이단옷장 (아이 옷은 짧아 행거 2단) — 아래 '내부 구성'에서 변경
    has_kickboard: true,
    material: 'LPM',
    run_mode: false,
    ep: { left: false, right: false, thickness: 20, cover_fronts: false },   // 도어가 측면 EP 앞까지 덮음
    top_panel: null,
    // 총 높이: 50(받침) + 2250(몸통) = 2300mm
    modules: [
      { kind: 'shelf_module', width: 1160, depth: 580, height: 2250,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        shelves: [], accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '자녀방 붙박이장 W1200×D580×H2300 | 이단옷장(행거 2단) + 상부 선반 · 내부 구성은 아래에서 변경'
  },

  kids_upper_open: {
    name: '오픈 상부장',
    furniture_type: 'kids_upper_open',
    width: 1200, max_depth: 280, base_height: 0,
    has_kickboard: false,
    material: 'LPM',
    run_mode: false,
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 총 높이: 400mm — 책상·수납장 상부 벽면 설치용
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 280, height: 400,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        // 1170 스팬 15T 처짐 → 중앙 분할 + 셀 선반 (실무 보정)
        shelves: [],
        accessories: [],
        vertical_dividers: [{ x: 577.5, thickness: 15 }],
        cell_shelves: [
          { cell: 0, height_from_bottom: 200, thickness: 15, depth_inset: 20 },
          { cell: 1, height_from_bottom: 200, thickness: 15, depth_inset: 20 }
        ],
        cell_drawers: []
      }
    ],
    _info: '오픈 상부장 W1200×D280×H400 | 책상/수납장 상부 오픈 선반. 하부 LED 조명 권장'
  },

  kids_upper_door: {
    name: '도어 상부장',
    furniture_type: 'kids_upper_door',
    width: 1200, max_depth: 280, base_height: 0,
    has_kickboard: false,
    material: 'LPM',
    run_mode: false,
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 총 높이: 400mm — 방진+정리 효과 도어형
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 280, height: 400,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        // 1170 스팬 15T 처짐 → 중앙 분할 + 셀 선반 (실무 보정)
        shelves: [],
        accessories: [],
        vertical_dividers: [{ x: 577.5, thickness: 15 }],
        cell_shelves: [
          { cell: 0, height_from_bottom: 200, thickness: 15, depth_inset: 20 },
          { cell: 1, height_from_bottom: 200, thickness: 15, depth_inset: 20 }
        ],
        cell_drawers: []
      }
    ],
    _info: '도어 상부장 W1200×D280×H400 | 양개여닫이 도어. 방진·정리 우수. 책상 상부 설치용'
  },

  kids_desk_upper: {
    name: '자녀방 책상+상부장',
    furniture_type: 'kids_desk_upper',
    width: 1200, max_depth: 600, base_height: 0,
    has_kickboard: false,
    material: 'LPM',
    run_mode: false,
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 총 높이: 750(책상) + 500(개방 이격) + 400(상부장) = 1650mm
    // 보고서 기준: 책상고 750mm, 상부장 D280 H400mm, 책상면~상부장 이격 500mm
    modules: [
      { kind: 'desk_module', width: 1200, depth: 600, height: 750,
        top_thickness: 25, leg_type: 'box',
        leg_w: 30, leg_d: 30, leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false, pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'v_gap', height: 500, label: '책상 위 개방 (모니터/작업 공간)' },
      { kind: 'shelf_module', width: 1200, depth: 280, height: 400,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        // 1170 스팬 15T 처짐 → 중앙 분할 + 셀 선반 (실무 보정)
        shelves: [],
        accessories: [],
        vertical_dividers: [{ x: 577.5, thickness: 15 }],
        cell_shelves: [
          { cell: 0, height_from_bottom: 200, thickness: 15, depth_inset: 20 },
          { cell: 1, height_from_bottom: 200, thickness: 15, depth_inset: 20 }
        ],
        cell_drawers: []
      }
    ],
    _info: '자녀방 책상+상부장 W1200 | 책상750 + 개방500 + 도어상부장400mm. 총 H1650mm. 초등~중학생 권장'
  },

  kids_bed_single: {
    name: '자녀방 싱글 침대장',
    furniture_type: 'kids_bed_single',
    width: 2000, max_depth: 580, base_height: 80,
    has_kickboard: true,
    material: 'LPM',
    run_mode: true,
    run_height: 2020,   // 80(받침) + 2020(타워) = 2100mm
    ep: { left: false, right: false, thickness: 20 },
    top_panel: null,
    // 좌선반 500 + 싱글침대 1000 + 우서랍 500 = 2000mm
    modules: [
      { kind: 'shelf_module', width: 500, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 400, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 900, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1400, thickness: 18, depth_inset: 20 }
        ],
        accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      },
      { kind: 'bed_gap', width: 1000, label: '싱글 침대 공간 (1000mm)',
        storage: true, platform_height: 350, bed_depth: 2000,
        drawer_count: 2, drawer_side: 'foot', lift_up_storage: false,
        material: 'LPM', door_material: 'LPM' },
      { kind: 'drawer_module', width: 500, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 4, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', handle_hole_mm: 128,
        material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '자녀방 싱글침대장 W2000 (수납500 + 싱글1000 + 서랍4단500) | 전고 H2100mm'
  },

  // ── 신규 프리셋 ──────────────────────────────────────────────────────────

  open_shelf: {
    name: '오픈 선반장',
    furniture_type: 'open_shelf',
    width: 900, max_depth: 300, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1182 + 18 = 1200mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 300, height: 1182,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_side_gap_mm: 2,
        suppress_left_side: false, suppress_right_side: false,
        material: 'LPM', edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 250, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 500, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 750, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 1000, thickness: 18, depth_inset: 0 }
        ],
        accessories: [], vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '오픈 선반장 W900×D300×H1200 | 도어 없음, 선반 4개 (250mm 피치). 책·소품 진열용'
  },

  corner_unit: {
    name: '코너 수납장',
    furniture_type: 'corner_unit',
    width: 600, max_depth: 600, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 782 + 18 = 800mm — 정사각형 오픈 선반, 코너 배치용
    modules: [
      { kind: 'shelf_module', width: 600, depth: 600, height: 782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_side_gap_mm: 2,
        suppress_left_side: false, suppress_right_side: false,
        material: 'LPM', edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 250, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 500, thickness: 18, depth_inset: 0 }
        ],
        accessories: [], vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '코너 수납장 W600×D600×H800 | 정사각형 오픈선반 2단. EP 없음. 코너에 수동 배치'
  },

  desk_with_side_cabinet: {
    name: '책상 + 사이드 수납장',
    furniture_type: 'desk_with_side_cabinet',
    width: 1800, max_depth: 700, base_height: 0,
    material: 'LPM',
    run_mode: true, run_height: 725,  // 상판 포함 총 750mm
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 25 },
    // 런 모드: 책상(1200) + 사이드 수납장(600)
    modules: [
      { kind: 'desk_module', width: 1200, depth: 700, height: 725,
        top_thickness: 25, leg_type: 'box',
        leg_w: 30, leg_d: 30, leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false, pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 600, depth: 400, height: 725,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_side_gap_mm: 2,
        suppress_left_side: false, suppress_right_side: false,
        material: 'LPM', edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 350, thickness: 18, depth_inset: 20 }],
        accessories: [], vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '책상+사이드장 W1800 | 런모드: 책상1200 + 사이드수납장600. 총높이 750mm'
  },

  living_run: {
    name: '거실 수납 런',
    furniture_type: 'living_run',
    width: 2400, max_depth: 450, base_height: 80,
    material: 'LPM',
    run_mode: true,
    run_height: 420,   // 80(받침) + 420 + 25(상판) = 525mm — 거실 로우보드
    ep: { left: false, right: false, thickness: 20 },
    top_panel: { thickness: 25 },
    // 수평 배열: 600(서랍2단) + 1200(도어수납) + 600(도어수납)
    modules: [
      { kind: 'drawer_module', width: 600, depth: 450, height: 420,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 20,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 1200, depth: 450, height: 420,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_side_gap_mm: 2,
        suppress_left_side: false, suppress_right_side: false,
        material: 'LPM', edge_banding_mm: 1.0,
        // 1164 스팬 18T 처짐 → 25T (실무 보정)
        shelves: [{ height_from_bottom: 200, thickness: 25, depth_inset: 0 }],
        accessories: [], vertical_dividers: [], cell_shelves: [], cell_drawers: []
      },
      { kind: 'shelf_module', width: 600, depth: 450, height: 420,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 20,
        door_material: 'LPM', handle_type: 'none', handle_hole_mm: 128,
        door_side_gap_mm: 2,
        suppress_left_side: false, suppress_right_side: false,
        material: 'LPM', edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 200, thickness: 18, depth_inset: 0 }],
        accessories: [], vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '거실 수납 런 W2400×D450×H525 | 서랍(600)+도어수납(1200+600). 핸들리스 채널. 로우보드'
  },

  /* ── 도면 가구 (오톤도 30X33_2550 도면 기준) ─────────────────────────────
     판재 두께는 모두 18T (뒷판만 9T). 도면 치수를 읽어 프리셋 형태에 맞게 옮김. */
  otondo_tall: {
    name: '도면 붙박이장 W1082 (서랍 2단 + 양개 도어)',
    furniture_type: 'wardrobe',
    width: 1082, max_depth: 600, base_height: 50,
    wardrobe_layout: 'drawer_hang',
    wardrobe_opts: { drawer_h: 700, drawer_count: 2 },
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18, cover_fronts: false },
    top_panel: null,
    // 총 높이: 50(받침) + 700(서랍 2단) + 1800(도어·행거) = 2550mm
    modules: [
      { kind: 'drawer_module', width: 1082, depth: 600, height: 700,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 1082, depth: 600, height: 1800,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 1452, thickness: 18, depth_inset: 20 }],
        accessories: [{ kind: 'hanging_rod', height_from_bottom: 1382, depth_inset: 75, diameter: 32 }]
      }
    ],
    _info: '도면 붙박이장 W1082×D600×H2550 | 받침50 + 서랍 2단(700) + 푸시 양개도어(537×2). 도면의 380 단은 도어 안쪽 구성으로 단순화'
  },

  otondo_upper_pair: {
    name: '도면 상부장 W1120 (양개 = 560×2)',
    furniture_type: 'kitchen_upper',
    width: 1120, max_depth: 350, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,
    modules: [
      { kind: 'shelf_module', width: 1120, depth: 350, height: 971,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 480, thickness: 18, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '도면 상부장 W1120×D350×H971 | 푸시 양개(560×2). 도면은 3칸(560×3): 이 프리셋 + 단문 W560 을 나란히 배치. 깊이는 도면에 없어 350 가정'
  },

  otondo_upper_single: {
    name: '도면 상부장 W560 (단문)',
    furniture_type: 'kitchen_upper',
    width: 560, max_depth: 350, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,
    modules: [
      { kind: 'shelf_module', width: 560, depth: 350, height: 971,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'single', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 480, thickness: 18, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '도면 상부장 W560×D350×H971 | 푸시 단문. 깊이 350 가정'
  },

  otondo_desk: {
    name: '도면 책상 W1768 (R100 모서리)',
    furniture_type: 'desk_basic',
    width: 1768, max_depth: 600, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,
    modules: [
      { kind: 'desk_module', width: 1768, depth: 600, height: 720,
        top_thickness: 18, top_radius: 100, top_round_corners: 'fl',
        leg_type: 'box', leg_w: 30, leg_d: 30, leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false, pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0 }
    ],
    _info: '도면 책상 W1768×D600×H720 | 상판 18T, 앞 왼쪽 모서리 R100 (모서리 위치·R값은 모듈 카드에서 변경). 깊이 600 가정'
  },

  otondo_low_open: {
    name: '도면 낮은 오픈장 W1182 (위 1칸 + 아래 2칸)',
    furniture_type: 'open_shelf',
    width: 1182, max_depth: 400, base_height: 50,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,
    // 총 높이: 50(받침) + 650 = 700mm
    modules: [
      { kind: 'shelf_module', width: 1182, depth: 400, height: 650,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 18,
        door_material: 'LPM', handle_type: 'none', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 321, thickness: 18, depth_inset: 0 }],
        accessories: [],
        vertical_dividers: [{ x: 582, thickness: 18, top: 321 }],
        cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '도면 낮은 오픈장 W1182×D400×H700 | 받침50 + 위 1칸(전폭) + 아래 2칸(각 약 570). 깊이 400 가정'
  },

  otondo_low_drawer: {
    name: '도면 낮은 서랍장 W750 (H270)',
    furniture_type: 'drawer_low',
    width: 750, max_depth: 400, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,
    modules: [
      { kind: 'drawer_module', width: 750, depth: 400, height: 270,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 1, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '도면 낮은 서랍장 W750×D400×H270 | 1단 서랍. 도면의 730/750 폭 중 750 사용. 깊이 400 가정'
  },

};

/* ====================================================================== */
const kabinet = (() => {
  // ── Initial state (mirrors Schema JSON) ─────────────────────────────
  const DEFAULT_STATE = {
    version: 1,
    name: '내 가구',
    furniture_type: '',
    width: 900,
    max_depth: 580,
    base_height: 0,
    base_type: 'wood',
    has_kickboard: true,
    material: 'LPM',
    edge_banding_mm: 1.0,
    run_mode: false,
    run_height: 740,
    ep: { left: false, right: false, top: false, thickness: 20 },
    ep_top_flush: false,
    top_panel: { thickness: 20 },
    modules: []
  };

  let state = deepClone(DEFAULT_STATE);
  let currentEntityID = null;
  let userPresets = {};   // 저장 프리셋 캐시 (통합 드롭다운용)

  // ── Tab management (v1.0: 단일 페이지 — 하위 호환 스텁) ──────────────
  function switchTab(name, btn) {
    const panel = document.getElementById('tab-' + name);
    if (!panel) return;   // 단일 페이지 레이아웃에서는 탭 없음
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.tab-buttons button').forEach(b => b.classList.remove('active'));
    panel.classList.add('active');
    if (btn) btn.classList.add('active');
  }

  // ── 통합 프리셋 드롭다운 (기본 + 내 프리셋) ──────────────────────────
  function onPresetChange(value) {
    if (!value) return;
    activePresetKey = value;
    if (value.indexOf('user:') === 0) {
      const name = value.slice(5);
      if (userPresets[name]) applyPreset(JSON.stringify(userPresets[name]));
      renderPresetSidebar();
    } else {
      loadFurniturePreset(value);
    }
  }

  // ── 좌측 사이드바: 도구 · 출력 · 프리셋 · 내 프리셋을 폴더로 한 곳에서 ──
  // 기본 프리셋 목록은 숨김 select(optgroup)를 원본으로 쓴다.
  let activePresetKey = '';
  let combineList = [];   // 합치기 대기열: [{ key, label }]
  const FOLDER_STORE = 'kabinet.folders.collapsed';

  function _loadCollapsed() {
    try { return JSON.parse(localStorage.getItem(FOLDER_STORE) || '{}') || {}; } catch (e) { return {}; }
  }
  function toggleFolder(id) {
    const c = _loadCollapsed();
    const cur = c[id] === undefined ? id === 'more' : c[id];   // 더보기 폴더는 기본 접힘
    c[id] = !cur;
    try { localStorage.setItem(FOLDER_STORE, JSON.stringify(c)); } catch (e) {}
    renderPresetSidebar();
  }

  // 사이드바 구성 (중복 없이): 공통사항 → 프리셋 → 내 프리셋 → 보관함 → 도구 → 도면·출력 → 더보기
  const SIDEBAR_TOOLS = [
    { id: 'slab_thickness', label: '선택 판재 두께 → T 일괄 변경', hint: '판재나 가구 그룹을 선택하고 누르면 안의 판재가 모두 아래 두께로' },
    { id: 'face_panel',   label: '면 클릭 → 판재 만들기', hint: '면을 클릭해 판재 생성 / 그룹 안 판재 두께 변경' },
    { id: 'space_divide', label: '공간 균등 분할', hint: '캐비닛 안쪽 클릭 → 칸 수 입력 → 칸막이·도어 균등 분할' },
    { id: 'countertop',   label: '주방 상판 설치', hint: '하부장들을 선택 → 규격·재질·높이 입력 → 상판 한 장' }
  ];
  const SIDEBAR_OUTPUTS = [
    { id: 'furniture_drawing', label: '가구 도면 (LayOut)', hint: '선택한 가구 → A3 평면·정면·측면·컬러 입체도 + PDF' },
    { id: 'drawing_import', label: '도면 치수표 → 3D 가구', hint: '도면의 가구별 치수를 표로 입력 → 프리셋 구조로 한 번에 생성·배치' },
  ];
  const SIDEBAR_MORE = [
    { id: 'update',         label: 'GitHub에서 업데이트', hint: '최신 kabinet.rbz를 내려받아 설치' },
    { id: 'reload',         label: '플러그인 다시 로드', hint: '설치된 파일을 다시 불러오기 (개발용)' }
  ];

  function runSidebarAction(id) {
    switch (id) {
      case 'slab_thickness': {
        const t = parseFloat((document.getElementById('tool-thickness') || {}).value) || 18;
        setStatus('선택한 판재 두께를 ' + t + 'T로 바꾸는 중…', '');
        callSketchup('kabinet:tool', JSON.stringify({ name: 'slab_thickness', thickness: t }));
        break;
      }
      case 'face_panel': {
        const t = parseFloat((document.getElementById('tool-thickness') || {}).value) || 18;
        callSketchup('kabinet:tool', JSON.stringify({ name: 'face_panel', thickness: t }));
        break;
      }
      case 'space_divide': callSketchup('kabinet:tool', JSON.stringify({ name: 'space_divide' })); break;
      case 'common':       showView('common'); renderCommonForm(); break;
      case 'ep_board':     showView('ep'); break;
      case 'countertop':   showView('countertop'); loadCountertopForm(); break;
      case 'furniture_drawing': showView('drawing'); window.kabinetDrawing && kabinetDrawing.setSpaceMode(false); break;
      case 'space_drawing':     showView('drawing'); window.kabinetDrawing && kabinetDrawing.setSpaceMode(true); break;
      case 'drawing_import':    showView('dimport'); window.kabinetDrawingImport && kabinetDrawingImport.open(); break;
      case 'library_manage':    showView('library'); break;
      case 'cutlist':      exportCutList(); break;
      case 'group_cut':
        setStatus('선택 그룹 재단 목록 생성 중…', '');
        callSketchup('kabinet:export_group_cutlist', '');
        break;
      case 'update':       setStatus('업데이트 확인 중…', ''); callSketchup('kabinet:admin', 'update'); break;
      case 'reload':       callSketchup('kabinet:admin', 'reload'); break;
    }
  }

  function callSketchup(name, arg) {
    if (typeof sketchup === 'undefined' || !sketchup[name]) {
      setStatus('SketchUp 안에서만 실행할 수 있습니다.', 'error');
      return;
    }
    sketchup[name](arg);
  }

  // 사용자 프리셋 이름 "폴더/이름" → 폴더별 묶음
  function _userPresetFolders() {
    const folders = {};
    Object.keys(userPresets).sort((a, b) => a.localeCompare(b, 'ko')).forEach(full => {
      const i = full.indexOf('/');
      const folder = i > 0 ? full.slice(0, i).trim() : '';
      const label  = i > 0 ? full.slice(i + 1).trim() : full;
      (folders[folder] = folders[folder] || []).push({ value: 'user:' + full, label, full });
    });
    return folders;
  }

  function renderPresetSidebar() {
    const list = document.getElementById('preset-sidebar-list');
    const sel  = document.getElementById('f-furniture-type');
    if (!list || !sel) return;
    const searchEl = document.getElementById('preset-search');
    const q = (searchEl && searchEl.value || '').trim().toLowerCase();
    const match = t => !q || t.toLowerCase().indexOf(q) >= 0;
    const collapsed = _loadCollapsed();
    let html = '';

    const folder = (id, title, inner, count, extraCls) => {
      const shut = !q && collapsed[id];
      return `<div class="sb-folder${extraCls || ''}">` +
        `<button type="button" class="sb-folder-head" data-folder="${escAttr(id)}">` +
        `<span class="sb-caret">${shut ? '▸' : '▾'}</span><span class="sb-folder-name">${esc(title)}</span>` +
        (count != null ? `<span class="sb-count">${count}</span>` : '') + '</button>' +
        (shut ? '' : `<div class="sb-folder-body">${inner}</div>`) + '</div>';
    };
    const actionBtn = it =>
      `<button type="button" class="preset-entry sb-action" title="${escAttr(it.hint)}" data-action="${escAttr(it.id)}">${esc(it.label)}</button>`;
    const presetBtn = (value, label, opts) => {
      const o = opts || {};
      return `<div class="preset-row">` +
        `<button type="button" class="preset-entry${value === activePresetKey ? ' active' : ''}" ` +
        `title="${escAttr(o.title || label)}" data-value="${escAttr(value)}">${esc(label)}</button>` +
        (o.del ? `<button type="button" class="preset-mini del" title="삭제" data-del="${escAttr(o.del)}">✕</button>` : '') +
        '</div>';
    };

    // 가구 공통사항 (맨 위 — 모든 가구에 함께 적용)
    if (match('가구 공통사항 두께 소재 손잡이')) {
      html += '<button type="button" class="sb-common" data-action="common" title="몸통·도어·선반 두께, 소재, 손잡이, EP — 모든 가구에 함께 적용">' +
              '가구 공통사항<span>' + esc(commonSummary()) + '</span></button>';
    }

    // 기본 프리셋 (카테고리별 폴더)
    Array.from(sel.querySelectorAll('optgroup')).forEach((grp, gi) => {
      if (grp.id === 'user-preset-group') return;
      // 런 모드 프리셋은 완성될 때까지 숨김 (RUN_MODE_ENABLED = true 로 복구)
      const opts = Array.from(grp.querySelectorAll('option')).filter(o =>
        match(o.textContent) && !BUNDLED_PRESETS.includes(o.value) &&
        (RUN_MODE_ENABLED || !(FURNITURE_PRESETS[o.value] || {}).run_mode));
      if (!opts.length) return;
      const title = grp.label.replace(/^[─\s]+/, '');
      html += folder('g' + gi + ':' + title, title,
        opts.map(o => presetBtn(o.value, o.textContent)).join(''), opts.length);
    });

    // 내 프리셋 (사용자 폴더)
    const uf = _userPresetFolders();
    const names = Object.keys(uf).sort((a, b) => (a === '' ? 1 : b === '' ? -1 : a.localeCompare(b, 'ko')));
    let userInner = '';
    let userCount = 0;
    names.forEach(fname => {
      const items = uf[fname].filter(it => match(it.full));
      if (!items.length) return;
      userCount += items.length;
      const rows = items.map(it => presetBtn(it.value, it.label, { title: it.full, del: it.full })).join('');
      userInner += fname ? folder('u:' + fname, fname, rows, items.length, ' sb-sub') : rows;
    });
    if (userCount || !q) {
      html += folder('user', '내 프리셋', userInner ||
        '<div class="preset-empty">저장된 프리셋 없음<br>아래 "내 프리셋 저장"에서 "폴더/이름"으로 저장하면 폴더가 생깁니다.</div>',
        userCount);
    }

    // 내 가구 보관함 (SketchUp 모델로 저장한 가구 — 폴더별)
    {
      const byFolder = {};
      furnitureLibrary.filter(it => match(it.name + ' ' + (it.folder || ''))).forEach(it => {
        (byFolder[it.folder || '미분류'] = byFolder[it.folder || '미분류'] || []).push(it);
      });
      const fnames = Object.keys(byFolder).sort((a, b) => a.localeCompare(b, 'ko'));
      let inner = actionBtn({ id: 'library_manage', label: '＋ 선택한 가구 넣기 · 관리', hint: '선택한 가구를 보관함에 넣고, 이름·폴더·삭제 관리' });
      let count = 0;
      fnames.forEach(f => {
        count += byFolder[f].length;
        // 가구 목록은 오른쪽 보관함 화면에만 (사이드바와 중복 표시하지 않음) — 폴더 클릭 → 그 폴더 열기
        inner += folder('lib:' + f, f, '', byFolder[f].length, ' sb-sub');
      });
      if (count || !q) html += folder('library', '내 가구 보관함', inner, count);
    }

    // 도구
    const tools = SIDEBAR_TOOLS.filter(t => match(t.label));
    if (tools.length) {
      let inner = '';
      tools.forEach(t => {
        inner += actionBtn(t);
        if (t.id === 'slab_thickness') {
          inner += '<label class="sb-inline">패널 두께 <input type="number" id="tool-thickness" min="3" max="100" step="1" ' +
                   `value="${escAttr(_toolThickness())}"> T</label>`;
        }
      });
      html += folder('tools', '도구', inner, null, ' sb-tools');
    }
    // 도면 · 출력
    const outs = SIDEBAR_OUTPUTS.filter(t => match(t.label));
    if (outs.length) html += folder('outputs', '도면', outs.map(actionBtn).join(''), null, ' sb-tools');
    // 더보기 (기본 접힘)
    const more = SIDEBAR_MORE.filter(t => match(t.label));
    if (more.length) {
      const shut = !q && (collapsed.more === undefined ? true : collapsed.more);
      html += `<div class="sb-folder sb-tools"><button type="button" class="sb-folder-head" data-folder="more">` +
        `<span class="sb-caret">${shut ? '▸' : '▾'}</span><span class="sb-folder-name">더보기</span></button>` +
        (shut ? '' : `<div class="sb-folder-body">${more.map(actionBtn).join('')}</div>`) + '</div>';
    }

    list.innerHTML = html || '<div class="preset-empty">검색 결과 없음</div>';
    // 클릭은 목록 컨테이너 한 곳에서 처리 (pointerdown) — 목록이 누르는 사이에 다시 그려져도
    // 클릭이 사라지지 않게 (예: "가구 공통사항"이 두세 번 눌러야 열리던 문제)
    if (!list._delegated) {
      list._delegated = true;
      list.addEventListener('pointerdown', ev => {
        if (ev.button !== 0) return;
        const t = ev.target.closest('[data-folder],[data-action],[data-lib],[data-value],[data-del]');
        if (!t || !list.contains(t)) return;
        ev.preventDefault();
        if (t.dataset.folder !== undefined) {
          const id = t.dataset.folder;
          if (id.indexOf('lib:') === 0) openLibraryFolder(id.slice(4)); else toggleFolder(id);
        } else if (t.dataset.action !== undefined) {
          runSidebarAction(t.dataset.action);
        } else if (t.dataset.lib !== undefined) {
          if (window.kabinetDrawing) kabinetDrawing.place(t.dataset.lib);
        } else if (t.dataset.del !== undefined) {
          if (confirm(`"${t.dataset.del}" 프리셋을 삭제할까요?`)) deletePreset(t.dataset.del);
        } else if (t.dataset.value !== undefined) {
          showView('design');
          const v = t.dataset.value;
          if (v.indexOf('user:') !== 0) sel.value = v;
          onPresetChange(v);
        }
      });
    }
    const tt = document.getElementById('tool-thickness');
    if (tt) tt.addEventListener('change', () => {
      try { localStorage.setItem('kabinet.toolThickness', tt.value); } catch (e) {}
    });
  }

  // ── 가구 공통사항 (모델에 저장 · 모든 가구에 함께 적용) ──────────────────
  // Ruby Kabinet::Core::Common.apply 와 같은 규칙 — 두 곳을 함께 고칠 것.
  let commonSettings = {};
  const COMMON_NUM = ['body_thickness', 'back_thickness', 'door_thickness', 'shelf_thickness', 'ep_thickness'];
  const COMMON_GAP = { gap_top: 'top', gap_bottom: 'bottom', gap_outside: 'outside', gap_between: 'between', gap_front: 'front_offset' };
  const COMMON_TXT = ['material', 'door_material', 'handle_type', 'handle_pos'];
  function _cleanCommon(c) {
    const out = {};
    COMMON_NUM.forEach(k => { const v = parseFloat(c && c[k]); if (v > 0 && v <= 100) out[k] = v; });
    Object.keys(COMMON_GAP).forEach(k => {
      const raw = c && c[k] != null ? String(c[k]).trim() : '';
      const v = parseFloat(raw);
      if (raw !== '' && v >= 0 && v <= 50) out[k] = v;
    });
    COMMON_TXT.forEach(k => { const v = c && c[k] != null ? String(c[k]).trim() : ''; if (v) out[k] = v; });
    return out;
  }
  function applyCommon(spec, common) {
    const c = _cleanCommon(common || commonSettings);
    const s = deepClone(spec);
    if (!Object.keys(c).length) return s;
    if (c.material) s.material = c.material;
    if (c.ep_thickness) s.ep = Object.assign({}, s.ep || {}, { thickness: c.ep_thickness });
    const gaps = {};
    Object.keys(COMMON_GAP).forEach(k => { if (k in c) gaps[COMMON_GAP[k]] = c[k]; });
    if (Object.keys(gaps).length) s.door_gaps = Object.assign({}, s.door_gaps || {}, gaps);
    (s.modules || []).forEach(m => {
      const kind = m.kind;
      if (c.material && kind !== 'bed_gap' && kind !== 'v_gap') m.material = c.material;
      if (kind !== 'shelf_module' && kind !== 'drawer_module') return;
      if (c.door_material) m.door_material = c.door_material;
      if (c.body_thickness) m.body_thickness = c.body_thickness;
      if (c.back_thickness) m.back_thickness = c.back_thickness;
      if (c.handle_type && !(kind === 'drawer_module' && c.handle_type === 'push_open')) m.handle_type = c.handle_type;   // 서랍은 푸시형 불가
      if (c.handle_pos) m.handle_pos = c.handle_pos;
      if ('gap_outside' in c && kind === 'shelf_module') m.door_side_gap_mm = c.gap_outside;
      if (c.door_thickness) {
        if (kind === 'shelf_module') m.door_thickness = c.door_thickness;
        if (kind === 'drawer_module' || 'drawer_thickness' in m) m.drawer_thickness = c.door_thickness;
      }
      if (c.shelf_thickness) {
        ['shelves', 'cell_shelves', 'vertical_dividers'].forEach(k =>
          (m[k] || []).forEach(p => { if (p && typeof p === 'object') p.thickness = c.shelf_thickness; }));
      }
    });
    return s;
  }
  function setCommon(c) {
    commonSettings = _cleanCommon(c || {});
    renderCommonForm();
    renderPresetSidebar();
  }
  const MATERIAL_LABELS = { LPM: 'LPM', PET: 'PET', UV_gloss: 'UV', acrylic: '아크릴', high_gloss: '하이그로시',
    phenix: '페닉스', HPL: 'HPL', MDF_paint: 'MDF도장', plywood: '합판', solid_wood: '원목' };
  function commonSummary() {
    const c = commonSettings, parts = [];
    if (c.body_thickness) parts.push('몸통 ' + c.body_thickness + 'T');
    if (c.door_thickness) parts.push('도어 ' + c.door_thickness + 'T');
    if (c.material) parts.push(MATERIAL_LABELS[c.material] || c.material);
    return parts.length ? parts.join(' · ') : '미설정 — 눌러서 지정';
  }
  function renderCommonForm() {
    const c = commonSettings;
    COMMON_NUM.concat(COMMON_TXT, Object.keys(COMMON_GAP)).forEach(k => {
      const el = document.getElementById('cm-' + k);
      if (el) el.value = c[k] != null ? c[k] : '';
    });
  }
  function applyCommonAll() {
    const read = {};
    COMMON_NUM.concat(COMMON_TXT, Object.keys(COMMON_GAP)).forEach(k => { const el = document.getElementById('cm-' + k); if (el) read[k] = el.value; });
    commonSettings = _cleanCommon(read);
    // 지금 폼의 가구에도 바로 반영
    state = applyCommon(state);
    syncFormFromState();
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
    renderPresetSidebar();
    setStatus('공통사항을 모든 가구에 적용하는 중…', '');
    callSketchup('kabinet:common_apply', JSON.stringify(commonSettings));
  }

  // ── 화면 전환: 가구 설계 / 도면 / 보관함 / EP 판재 ─────────────────────
  let furnitureLibrary = [];
  const VIEW_TITLES = { drawing: '도면 출력 (LayOut + PDF)', library: '내 가구 보관함', ep: 'EP 판재 한 장', countertop: '주방 상판 설치', common: '가구 공통사항', dimport: '도면 치수표 → 3D 가구' };

  // ── 주방 상판 ────────────────────────────────────────────────────────
  const CT_FIELDS = ['thickness', 'front', 'side', 'back', 'material', 'height-mode', 'top-height'];
  function loadCountertopForm() {
    try {
      const saved = JSON.parse(localStorage.getItem('kabinet.countertop') || '{}');
      CT_FIELDS.forEach(k => { const el = document.getElementById('ct-' + k); if (el && saved[k] != null) el.value = saved[k]; });
    } catch (e) {}
    const mode = document.getElementById('ct-height-mode');
    const top = document.getElementById('ct-top-height');
    if (mode && top) {
      top.disabled = mode.value !== 'fixed';
      mode.onchange = () => { top.disabled = mode.value !== 'fixed'; };
    }
    try { if (typeof sketchup !== 'undefined') sketchup['kabinet:countertop_materials'](''); } catch (e) {}
  }
  function setCountertopMaterials(names) {
    const dl = document.getElementById('ct-material-list');
    if (dl) dl.innerHTML = (names || []).map(n => `<option value="${escAttr(n)}">`).join('');
  }
  function installCountertop() {
    const v = k => (document.getElementById('ct-' + k) || {}).value;
    const saved = {};
    CT_FIELDS.forEach(k => { saved[k] = v(k); });
    try { localStorage.setItem('kabinet.countertop', JSON.stringify(saved)); } catch (e) {}
    const opts = {
      thickness: +v('thickness'), front_overhang: +v('front'), side_overhang: +v('side'), back_gap: +v('back'),
      material: v('material') || '', height_mode: v('height-mode'), top_height: +v('top-height')
    };
    if (!(opts.thickness >= 3 && opts.thickness <= 100)) { setStatus('상판 두께를 3~100mm로 입력하세요.', 'error'); return; }
    setStatus('선택한 하부장을 인식해 상판을 설치하는 중…', '');
    callSketchup('kabinet:countertop', JSON.stringify(opts));
  }
  function showView(name) {
    const target = document.getElementById('view-' + name) ? name : 'design';
    document.querySelectorAll('.view').forEach(v => { v.hidden = v.id !== 'view-' + target; });
    const bar = document.getElementById('view-bar');
    if (bar) bar.hidden = target === 'design';
    const t = document.getElementById('view-title');
    if (t) t.textContent = VIEW_TITLES[target] || '';
    const acts = document.getElementById('design-actions');
    if (acts) acts.hidden = target !== 'design';
  }
  // 보관함 폴더(예: 미분류) 클릭 → 폴더를 펼치고 오른쪽에 그 폴더 가구 목록
  function openLibraryFolder(name) {
    const c = _loadCollapsed();
    if (c['lib:' + name]) { c['lib:' + name] = false; try { localStorage.setItem(FOLDER_STORE, JSON.stringify(c)); } catch (e) {} }
    showView('library');
    const f = document.getElementById('ep-library-filter');
    if (f) { f.value = name; f.dispatchEvent(new Event('change')); }
    const t = document.getElementById('view-title');
    if (t) t.textContent = '내 가구 보관함 — ' + name;
    renderPresetSidebar();
  }

  function setLibrary(items) {
    furnitureLibrary = Array.isArray(items) ? items : [];
    renderPresetSidebar();
  }

  function _toolThickness() {
    try { return localStorage.getItem('kabinet.toolThickness') || '18'; } catch (e) { return '18'; }
  }

  // ── 프리셋 합치기: 여러 프리셋을 가로(런)로 이어붙여 하나의 가구로 ─────
  function _presetSpec(key) {
    if (key.indexOf('user:') === 0) {
      const p = userPresets[key.slice(5)];
      return p ? deepClone(p) : null;
    }
    return FURNITURE_PRESETS[key] ? deepClone(FURNITURE_PRESETS[key]) : null;
  }

  function addToCombine(key, label) {
    combineList.push({ key, label });
    renderCombine();
    setStatus(`합치기에 추가: ${label} (총 ${combineList.length}개)`, 'ok');
  }
  function removeFromCombine(i) { combineList.splice(i, 1); renderCombine(); }
  function moveCombine(i, d) {
    const j = i + d;
    if (j < 0 || j >= combineList.length) return;
    [combineList[i], combineList[j]] = [combineList[j], combineList[i]];
    renderCombine();
  }
  function clearCombine() { combineList = []; renderCombine(); }

  function renderCombine() {
    const card = document.getElementById('combine-card');
    const body = document.getElementById('combine-list');
    if (!card || !body) return;
    card.style.display = combineList.length ? '' : 'none';
    body.innerHTML = combineList.map((it, i) =>
      `<div class="combine-row"><span class="combine-idx">${i + 1}</span>` +
      `<span class="combine-name">${esc(it.label)}</span>` +
      `<button class="btn-inline" onclick="kabinet.moveCombine(${i},-1)" title="왼쪽으로">◀</button>` +
      `<button class="btn-inline" onclick="kabinet.moveCombine(${i},1)" title="오른쪽으로">▶</button>` +
      `<button class="btn-inline del-btn" onclick="kabinet.removeFromCombine(${i})">✕</button></div>`).join('');
    const h = document.getElementById('combine-height');
    const r = combinePresets(combineList.map(it => it.key), h && h._userEdited ? +h.value : null);
    const info = document.getElementById('combine-info');
    if (info) {
      info.className = 'dim-note' + (r.error ? ' combine-error' : '');
      info.textContent = r.error ? r.error :
        `합친 폭 ${Math.round(r.spec.modules.reduce((a, m) => a + (+m.width || 0), 0))}mm · 공통 높이 ${r.spec.run_height}mm` +
        (r.warnings.length ? ' · ' + r.warnings.join(' / ') : '');
    }
    if (h && !h._userEdited && !r.error) h.value = r.spec.run_height;
  }

  // keys: 프리셋 키 배열. runHeight: 공통 높이(null이면 최댓값). 반환 { spec, warnings, error }
  function combinePresets(keys, runHeight) {
    const warnings = [];
    if (keys.length < 2) return { error: '프리셋을 2개 이상 추가하세요 (사이드바 ＋ 버튼).', warnings };
    const parts = [];
    for (const key of keys) {
      const sp = _presetSpec(key);
      if (!sp) return { error: `프리셋을 찾을 수 없음: ${key}`, warnings };
      const label = sp.name || key;
      let mods, height;
      if (sp.run_mode) {
        mods = sp.modules;
        height = +sp.run_height || 740;
      } else {
        const solid = sp.modules.filter(m => m.kind !== 'v_gap');
        if (sp.modules.length !== 1 || solid.length !== 1) {
          return { error: `"${label}"은(는) 세로로 ${sp.modules.length}단 쌓인 구성이라 가로 합치기를 할 수 없습니다. ` +
                          '단일 모듈 프리셋이나 런(가로 배열) 프리셋을 쓰세요.', warnings };
        }
        const ep = sp.ep || {};
        const epT = (ep.left ? (ep.thickness || 20) : 0) + (ep.right ? (ep.thickness || 20) : 0);
        const m = sp.modules[0];
        m.width = Math.round((+sp.width || m.width) - epT);
        mods = [m];
        height = +m.height;
      }
      parts.push({ sp, label, mods: deepClone(mods), height });
    }
    const first = parts[0].sp, last = parts[parts.length - 1].sp;
    const maxH = Math.max(...parts.map(p => p.height));
    const rh = runHeight > 0 ? runHeight : maxH;
    if (parts.some(p => Math.abs(p.height - rh) > 1)) warnings.push(`높이가 달라 모두 ${rh}mm로 맞춰짐`);
    if (parts.some(p => (+p.sp.base_height || 0) !== (+first.base_height || 0))) {
      warnings.push(`받침 높이는 첫 프리셋(${+first.base_height || 0}mm) 기준`);
    }
    const modules = [].concat(...parts.map(p => p.mods));
    const depth = Math.max(...parts.map(p => +p.sp.max_depth || 0), ...modules.map(m => +m.depth || 0));
    const ept = (first.ep && first.ep.thickness) || 20;
    const topSrc = parts.find(p => p.sp.top_panel);
    const spec = {
      name: parts.map(p => p.label).join(' + '),
      furniture_type: 'combined',
      width: Math.round(modules.reduce((a, m) => a + (+m.width || 0), 0)),
      max_depth: depth,
      base_height: +first.base_height || 0,
      base_type: first.base_type || 'wood',
      has_kickboard: first.has_kickboard !== false,
      material: first.material || 'LPM',
      run_mode: true,
      run_height: rh,
      ep: { left: !!(first.ep && first.ep.left), right: !!(last.ep && last.ep.right), thickness: ept },
      top_panel: topSrc ? deepClone(topSrc.sp.top_panel) : null,
      modules
    };
    return { spec, warnings };
  }

  function applyCombine() {
    const h = document.getElementById('combine-height');
    const r = combinePresets(combineList.map(it => it.key), h ? +h.value : null);
    if (r.error) { setStatus(r.error, 'error'); return; }
    state = applyCommon(r.spec);
    currentEntityID = null;
    activePresetKey = '';
    syncFormFromState();
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
    renderPresetSidebar();
    setStatus('프리셋 합치기 완료: ' + r.spec.name + (r.warnings.length ? '\n' + r.warnings.join('\n') : ''), 'ok');
  }

  function escAttr(s) { return esc(s).replace(/"/g, '&quot;'); }

  // ── Furniture type preset loader ─────────────────────────────────────
  function loadFurniturePreset(type) {
    const preset = FURNITURE_PRESETS[type];
    if (!preset) return;
    state = applyCommon(preset);
    delete state._info;
    currentEntityID = null;
    // 스택 모드: 모듈 폭을 카케이스 내부 폭으로 동기화
    // (지오메트리가 어차피 강제하므로 UI 표시도 실제 값과 일치시킴)
    if (!state.run_mode) {
      const iw = _carcaseInnerWidth(state.width);
      state.modules.forEach(m => { if (m.kind !== 'bed_gap') m.width = iw; });
    }
    if (state.wardrobe_layout) applyWardrobeLayout(state.wardrobe_layout, true);
    syncFormFromState();
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();

    // Show info box
    const info = document.getElementById('preset-info');
    if (info && preset._info) {
      info.textContent = preset._info;
      info.style.display = '';
    }

    // Keep dropdown in sync
    const sel = document.getElementById('f-furniture-type');
    if (sel) sel.value = type;
    activePresetKey = type;
    renderPresetSidebar();

    setStatus('프리셋 로드: ' + (preset.name || type), 'ok');
  }

  // ── Field helpers ────────────────────────────────────────────────────
  function onField(key, value) {
    const previousDepth = state.max_depth > 0 ? state.max_depth : Math.max(...state.modules.map(m => m.depth || 0));
    state[key] = value;

    if (key === 'width') {
      // 전체 폭 → 모든 모듈에 자동 적용
      if (state.run_mode) {
        // 런 모드: 섹션 폭을 비율대로 재분배
        _distributeWidthProportional(value);
      } else {
        // 적층 모드: 카케이스 내부 폭 = 전체폭 − EP 두께
        const innerW = _carcaseInnerWidth(value);
        state.modules.forEach(m => { if (m.kind !== 'bed_gap') m.width = innerW; });
        if (state.wardrobe_layout) applyWardrobeLayout(state.wardrobe_layout, true);   // 1문↔2문 등 다시 계산
        renderModuleList();
      }
      updateTotalHeight();
    } else if (key === 'max_depth') {
      if (previousDepth > 0 && value > 0) {
        state.modules.forEach(m => {
          if (m.depth > 0) m.depth = Math.round(m.depth * value / previousDepth);
        });
        renderModuleList();
      }
      updateTotalHeight();
    } else if (key === 'base_height') {
      updateTotalHeight();
    } else if (key === 'run_height') {
      updateTotalHeight();
      updateHeightSummary();
    }
  }

  // ── 목표 높이 → 모듈 높이 비율 유지 자동 재분배 ────────────────────────
  function onTargetHeightLive(targetTotal) {
    if (state.run_mode) return;  // 런 모드는 run_height 단일값으로 제어
    if (!targetTotal || targetTotal < 50) return;
    if (state.modules.length === 0) return;

    const topT      = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base      = state.base_height || 0;
    const remaining = targetTotal - topT - base - _epTopT();
    if (remaining < 10) return;

    const currentTotal = state.modules.reduce((s, m) => s + (m.height || 0), 0);

    if (currentTotal <= 0) {
      // 높이 비율 없으면 균등 분배
      const per = Math.round(remaining / state.modules.length);
      state.modules.forEach(m => { m.height = per; });
    } else {
      // 현재 비율 유지하며 재분배
      let allocated = 0;
      state.modules.forEach((m, i) => {
        if (i === state.modules.length - 1) {
          // 마지막 모듈에 나머지 할당 (반올림 오차 보정)
          m.height = remaining - allocated;
        } else {
          const h = Math.round(remaining * (m.height || 0) / currentTotal);
          m.height = Math.max(h, 50);  // 최소 50mm
          allocated += m.height;
        }
      });
    }

    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
    // 목표 높이 필드 자체는 건드리지 않음 (사용자가 입력 중)
    if (state.wardrobe_layout) {      // 내부 구성 비율 대신 구성 규칙대로 다시 배치
      applyWardrobeLayout(state.wardrobe_layout, true);
      renderModuleList();
      updateHeightSummary();
    }
  }

  // ── 런 모드: 총 폭 → 섹션 폭 비율 유지 재분배 ─────────────────────────
  function _distributeWidthProportional(totalW) {
    if (!state.modules.length || !totalW || totalW < 10) return;
    const currentTotal = state.modules.reduce((s, m) => s + (m.width || 0), 0);

    if (currentTotal <= 0) {
      const per = Math.round(totalW / state.modules.length);
      state.modules.forEach(m => { m.width = per; });
    } else {
      let allocated = 0;
      state.modules.forEach((m, i) => {
        if (i === state.modules.length - 1) {
          m.width = totalW - allocated;
        } else {
          const w = Math.round(totalW * (m.width || 0) / currentTotal);
          m.width = Math.max(w, 100);
          allocated += m.width;
        }
      });
    }
    renderModuleList();
    updateHeightSummary();
  }

  function onTopPanelToggle(checked) {
    state.top_panel = checked ? { thickness: 20 } : null;
    document.getElementById('top-panel-fields').style.display = checked ? '' : 'none';
    updateTotalHeight();
  }

  function onTopPanelField(key, value) {
    if (!state.top_panel) state.top_panel = {};
    state.top_panel[key] = value;
    updateTotalHeight();
  }

  function onEP(key, value) {
    state.ep[key] = value;
    if (!state.run_mode) {
      state.modules.forEach(m => { if (m.kind !== 'bed_gap' && m.kind !== 'v_gap') m.width = _carcaseInnerWidth(state.width); });
      renderModuleList();
    }
    updateTotalHeight();   // 상부 EP는 총 높이에 반영됨
  }

  // 상부 EP 두께 (총 높이 가산분)
  function _epTopT() {
    const ep = state.ep || {};
    return ep.top ? (ep.thickness || 20) : 0;
  }

  function onEpTopFlush(checked) {
    state.ep_top_flush = checked;
  }

  // ── Run mode toggle ──────────────────────────────────────────────────
  function onRunMode(checked) {
    state.run_mode = checked;

    // 런 높이 행
    const rhRow = document.getElementById('run-height-row');
    if (rhRow) rhRow.style.display = checked ? '' : 'none';

    // 섹션 총 폭 표시 행
    const twRow = document.getElementById('total-width-row');
    if (twRow) twRow.style.display = checked ? '' : 'none';

    // 높이 분배 행 (런 모드에선 불필요)
    const distRow  = document.getElementById('distribute-row');
    const distHint = document.getElementById('distribute-hint');
    const hintH    = document.getElementById('height-hint');
    if (distRow)  distRow.style.display  = checked ? 'none' : '';
    if (distHint) distHint.style.display = checked ? 'none' : '';
    if (hintH)    hintH.style.display    = checked ? 'none' : '';

    // 폭 라벨 + 힌트 텍스트 변경
    const wLabel = document.getElementById('width-label');
    const wHint  = document.getElementById('width-hint');
    if (wLabel) wLabel.textContent = checked ? '총 런 폭' : '전체 폭';
    if (wHint)  wHint.textContent  = checked
      ? '폭을 바꾸면 각 섹션 폭이 비율대로 자동 재분배됩니다'
      : '폭을 바꾸면 내부 모듈 폭이 자동으로 따라옵니다';

    // 런 모드 진입 시 f-width 에 섹션 총합 표시
    if (checked && state.modules.length > 0) {
      const totalW = state.modules.reduce((s, m) => s + (m.width || 0), 0);
      if (totalW > 0) {
        state.width = totalW;
        setVal('f-width', totalW);
      }
    }

    updateTotalHeight();
    updateHeightSummary();
    renderModuleList();
  }

  // ── 붙박이장 내부 구성 (국내 붙박이장에서 흔히 쓰는 4가지) ─────────────
  // 높이는 모듈 바닥(하판 아래) 기준 mm. 숫자는 wardrobe_opts로 쉽게 고침.
  const WARDROBE_LAYOUTS = {
    long:        '긴옷장 — 상부 선반 + 행거 1단 (코트·원피스)',
    double:      '이단옷장 — 행거 2단 (셔츠·바지)',
    drawer_hang: '외부 서랍 + 행거 — 하부 서랍(도어 밖) + 상부 도어·행거',
    shelves:     '선반장 — 선반 여러 단 (개킨 옷·이불)',
    // 아래 3가지: 오톤도 붙박이장 구성표(도어 3~8개 기본 내부구성 그림)에서 가져온 몸통 구성
    long_drawer: '긴옷 + 하부 서랍 — 상부 선반·행거 + 바닥 내부서랍 3단',
    hang_shelf:  '행거 + 하부 선반칸 — 상부 행거, 중간 선반 아래는 선반 수납',
    hang_split:  '행거 + 하부 분할 — 상부 행거, 아래는 좌 칸 + 우 선반 4단'
  };
  const WARDROBE_DEFAULT_OPTS = { top_space: 330, drawer_h: 640, drawer_count: 3, shelf_count: 6, lower_rod: 940,
                                  inner: null };
  // 내부 서랍 예시 (도어 안쪽) — bottom: 모듈 바닥 기준 시작 높이, height: 전판 1장 높이
  const INNER_DRAWER_PRESETS = {
    none:     { label: '없음', v: null },
    floor2:   { label: '바닥 2단 (각 200)', v: { bottom: 60, count: 2, height: 200 } },
    floor3:   { label: '바닥 3단 (각 180)', v: { bottom: 60, count: 3, height: 180 } },
    waist2:   { label: '허리 높이 2단 (750~, 각 160)', v: { bottom: 750, count: 2, height: 160 } },
    custom:   { label: '직접 입력', v: null }
  };

  function _wardrobeBase() {
    const m = (state.modules || []).find(x => x.kind === 'shelf_module' || x.kind === 'drawer_module') || {};
    return {
      body_thickness: m.body_thickness || 18, back_thickness: m.back_thickness || 9, has_back: true,
      door_thickness: m.door_thickness || 20, door_material: m.door_material || state.material || 'LPM',
      material: m.material || state.material || 'LPM', handle_type: m.handle_type || 'none',
      edge_banding_mm: m.edge_banding_mm || 1.0, depth: state.max_depth || 580
    };
  }

  // 현재 폭·높이로 내부 구성 모듈을 다시 만든다
  function buildWardrobe(layout, totalModuleH) {
    const o = Object.assign({}, WARDROBE_DEFAULT_OPTS, state.wardrobe_opts || {});
    const b = _wardrobeBase();
    const w = _carcaseInnerWidth(state.width);
    const H = Math.round(totalModuleH);
    const t = b.body_thickness;
    const shelf = (h) => ({ height_from_bottom: Math.round(h), thickness: t, depth_inset: 20 });
    const rod = (h) => ({ kind: 'hanging_rod', height_from_bottom: Math.round(h), depth_inset: 75, diameter: 32 });
    const inner = o.inner && o.inner.count > 0 ? o.inner : null;
    const innerTop = inner ? inner.bottom + inner.count * inner.height + inner.count * 3 + t : 0;   // 덮개 선반 윗면
    const withInner = (extra) => inner ? Object.assign(extra, { inner_drawers: Object.assign({ cover: true }, inner) }) : extra;
    const doorCase = (h, extra) => Object.assign({ kind: 'shelf_module', width: w, depth: b.depth, height: h,
      body_thickness: t, back_thickness: b.back_thickness, has_back: true,
      door_config: w > 600 ? 'pair' : 'single', door_type: 'swing', door_thickness: b.door_thickness,
      door_material: b.door_material, handle_type: b.handle_type, material: b.material,
      edge_banding_mm: b.edge_banding_mm, shelves: [], accessories: [] }, extra);
    const topShelf = H - t - o.top_space;           // 상부 선반 (위 공간 top_space)
    if (layout === 'double') {
      const mid = Math.max(o.lower_rod + 60, Math.round(H * 0.47));
      return [doorCase(H, withInner({ shelves: [shelf(topShelf), shelf(mid)],
                            accessories: [rod(topShelf - 70), rod(mid - 60)] }))];
    }
    if (layout === 'shelves') {
      const n = Math.max(1, Math.min(12, o.shelf_count | 0));
      const start = inner ? innerTop : t;                 // 내부 서랍이 있으면 그 위부터 선반 배치
      const step = (H - t - start) / (n + 1);
      return [doorCase(H, withInner({ shelves: Array.from({ length: n }, (_, i) => shelf(start + step * (i + 1))) }))];
    }
    if (layout === 'drawer_hang') {
      const dh = Math.max(300, Math.min(H - 600, o.drawer_h));
      const upper = H - dh;
      return [
        { kind: 'drawer_module', width: w, depth: b.depth, height: dh, body_thickness: t,
          back_thickness: b.back_thickness, has_back: true, drawer_count: Math.max(1, o.drawer_count | 0),
          drawer_type: 'undermount', drawer_thickness: b.door_thickness, door_material: b.door_material,
          handle_type: b.handle_type, material: b.material, edge_banding_mm: b.edge_banding_mm },
        doorCase(upper, { shelves: [shelf(upper - t - o.top_space)], accessories: [rod(upper - t - o.top_space - 70)] })
      ];
    }
    if (layout === 'long_drawer') {     // 도어 3·4개 그림의 왼쪽 몸통: 긴옷 행거 + 바닥 서랍 3단 (도어 안)
      const idr = inner || INNER_DRAWER_PRESETS.floor3.v;
      return [doorCase(H, { shelves: [shelf(topShelf)], accessories: [rod(topShelf - 70)],
                            inner_drawers: Object.assign({ cover: true }, idr) })];
    }
    if (layout === 'hang_shelf' || layout === 'hang_split') {
      // 중간 선반으로 위(행거)·아래(수납)를 나눔 — 중간 선반 높이는 lower_rod 값을 같이 씀
      const mid = Math.max(o.lower_rod + 60, Math.round(H * 0.47));
      const extra = { shelves: [shelf(topShelf), shelf(mid)], accessories: [rod(topShelf - 70)] };
      if (layout === 'hang_shelf') {     // 도어 3·4개 오른쪽 몸통: 아래 칸에 선반 1
        extra.shelves.push(shelf(t + (mid - t) / 2));
        return [doorCase(H, withInner(extra))];
      }
      // 도어 5·6개 그림: 아래를 세로로 나눠 왼쪽은 통 칸, 오른쪽은 선반 4단 (좁은 1도어 폭이면 분할 없이 선반칸)
      const innerW = w - 2 * t;
      if (innerW < 700) { extra.shelves.push(shelf(t + (mid - t) / 2)); return [doorCase(H, extra)]; }
      const dx = Math.round(innerW / 2 - t / 2);
      extra.vertical_dividers = [{ x: dx, thickness: t, top: mid }];
      const step = (mid - t) / 4;
      extra.cell_shelves = [1, 2, 3].map(i => ({ cell: 1, height_from_bottom: Math.round(t + step * i), thickness: t, depth_inset: 20 }));
      extra.cell_drawers = [];
      return [doorCase(H, extra)];
    }
    return [doorCase(H, withInner({ shelves: [shelf(topShelf)], accessories: [rod(topShelf - 70)] }))];   // long
  }

  function _moduleTotalH() {
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const sum = (state.modules || []).reduce((a, m) => a + (m.kind === 'bed_gap' ? 0 : (m.height || 0)), 0);
    return sum > 0 ? sum : 2300 - (state.base_height || 0) - topT;
  }

  function applyWardrobeLayout(layout, keepRender) {
    if (!WARDROBE_LAYOUTS[layout]) { delete state.wardrobe_layout; renderWardrobeRow(); return; }
    state.wardrobe_layout = layout;
    // 긴옷 + 하부 서랍: 내부서랍이 비어 있으면 바닥 3단을 기본으로 넣는다 → 아래 '서랍 단수·1단 높이' 칸에서 수정
    if (layout === 'long_drawer' && !(state.wardrobe_opts && state.wardrobe_opts.inner)) {
      state.wardrobe_opts = Object.assign({}, state.wardrobe_opts, { inner: Object.assign({}, INNER_DRAWER_PRESETS.floor3.v) });
    }
    state.modules = buildWardrobe(layout, _moduleTotalH());
    if (keepRender) return;
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
    renderWardrobeRow();
    renderPreview();
  }

  function setWardrobeOpt(key, value) {
    state.wardrobe_opts = Object.assign({}, state.wardrobe_opts || {}, { [key]: +value });
    if (state.wardrobe_layout) applyWardrobeLayout(state.wardrobe_layout);
  }

  function setInnerDrawerPreset(key) {
    const p = INNER_DRAWER_PRESETS[key];
    let v = p ? p.v : null;
    if (key === 'custom') v = (state.wardrobe_opts && state.wardrobe_opts.inner) || { bottom: 60, count: 2, height: 200 };
    state.wardrobe_opts = Object.assign({}, state.wardrobe_opts || {}, { inner: v ? Object.assign({}, v) : null });
    if (state.wardrobe_layout) applyWardrobeLayout(state.wardrobe_layout);
  }
  function setInnerDrawer(k, value) {
    const cur = Object.assign({ bottom: 60, count: 2, height: 200 }, (state.wardrobe_opts || {}).inner || {});
    cur[k] = +value;
    state.wardrobe_opts = Object.assign({}, state.wardrobe_opts || {}, { inner: cur });
    if (state.wardrobe_layout) applyWardrobeLayout(state.wardrobe_layout);
  }

  // 기본 정보 카드의 "내부 구성" 줄 — 붙박이장(내부 구성 지정된 가구)에서만 보임
  function renderWardrobeRow() {
    const row = document.getElementById('wardrobe-layout-row');
    if (!row) return;
    const lay = state.wardrobe_layout;
    row.hidden = !lay;
    if (!lay) return;
    const sel = document.getElementById('f-wardrobe-layout');
    if (sel) sel.value = lay;
    const o = Object.assign({}, WARDROBE_DEFAULT_OPTS, state.wardrobe_opts || {});
    const opt = document.getElementById('wardrobe-opts');
    if (!opt) return;
    const num = (k, label, min, max) =>
      `<label class="ep-field">${label}<input type="number" min="${min}" max="${max}" value="${o[k]}" ` +
      `onchange="kabinet.setWardrobeOpt('${k}', this.value)"></label>`;
    let html = num('top_space', '상부 선반 위 공간', 150, 800);
    if (lay === 'double') html += num('lower_rod', '아래 행거 높이', 600, 1300);
    if (lay === 'hang_shelf' || lay === 'hang_split') html += num('lower_rod', '중간 선반 높이', 600, 1300);
    if (lay === 'shelves') html = num('shelf_count', '선반 수', 1, 12);
    if (lay === 'drawer_hang') html += num('drawer_h', '외부 서랍장 높이', 300, 1200) + num('drawer_count', '외부 서랍 단수', 1, 6);
    if (lay !== 'drawer_hang' && lay !== 'hang_split') {
      // 내부 서랍 (도어 안쪽): 예시 선택 + 직접 편집
      const cur = o.inner;
      let key = 'none';
      Object.keys(INNER_DRAWER_PRESETS).forEach(k => {
        const v = INNER_DRAWER_PRESETS[k].v;
        if (cur && v && v.bottom === cur.bottom && v.count === cur.count && v.height === cur.height) key = k;
      });
      if (cur && key === 'none') key = 'custom';
      html += '<label class="ep-field">내부 서랍<select onchange="kabinet.setInnerDrawerPreset(this.value)">' +
        Object.keys(INNER_DRAWER_PRESETS).map(k =>
          `<option value="${k}"${k === key ? ' selected' : ''}>${INNER_DRAWER_PRESETS[k].label}</option>`).join('') +
        '</select></label>';
      if (cur) {
        const inum = (k, label, min, max) =>
          `<label class="ep-field">${label}<input type="number" min="${min}" max="${max}" value="${cur[k]}" ` +
          `onchange="kabinet.setInnerDrawer('${k}', this.value)"></label>`;
        html += inum('bottom', '서랍 시작 높이', 20, 1800) + inum('count', '서랍 단수', 1, 6) + inum('height', '서랍 1단 높이', 80, 400);
      }
    }
    opt.innerHTML = html;
  }

  // EP 포함 전체 폭 → 카케이스 내부 폭 계산
  function _carcaseInnerWidth(totalW) {
    const ep = state.ep || {};
    const t  = ep.thickness || 20;
    const epTotal = (ep.left ? t : 0) + (ep.right ? t : 0);
    return Math.max(Math.round(totalW - epTotal), 50);
  }

  // ── Unified width: copy assembly width to all modules ────────────────
  function syncWidthToModules() {
    const innerW = _carcaseInnerWidth(state.width);
    state.modules.forEach(m => { if (m.kind !== 'bed_gap') m.width = innerW; });
    renderModuleList();
    setStatus('모든 모듈 폭을 ' + innerW + 'mm (카케이스 내부)로 적용했습니다.', 'ok');
  }

  // ── Height distribution ──────────────────────────────────────────────
  function distributeHeight() {
    if (state.modules.length === 0) {
      setStatus('모듈이 없습니다.', 'error'); return;
    }
    const targetEl = document.getElementById('f-target-height');
    const target = parseFloat(targetEl ? targetEl.value : 0);
    if (!target || target <= 0) { setStatus('목표 높이를 입력하세요.', 'error'); return; }
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base = state.base_height || 0;
    const remaining = target - topT - base - _epTopT();
    if (remaining <= 0) { setStatus('목표 높이가 너무 작습니다.', 'error'); return; }
    const perMod = Math.round(remaining / state.modules.length);
    state.modules.forEach(m => { m.height = perMod; });
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
    setStatus('높이를 균등 분배했습니다 (각 ' + perMod + 'mm).', 'ok');
  }

  // ── Total height/width display ───────────────────────────────────────
  function updateTotalHeight() {
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base = state.base_height || 0;

    if (state.run_mode) {
      // Height = base + run_height + top panel + 상부 EP
      const runH  = state.run_height || 740;
      const total = base + runH + topT + _epTopT();
      const el    = document.getElementById('total-height-display');
      if (el) el.textContent = total;

      // Also show total run width from section widths
      const totalW = state.modules.reduce((s, m) => s + (m.width || 0), 0);
      const twEl   = document.getElementById('total-run-width-display');
      if (twEl) twEl.textContent = totalW;
    } else {
      const modsH = state.modules.reduce((s, m) => s + (m.height || 0), 0);
      const total = base + modsH + topT + _epTopT();
      const el    = document.getElementById('total-height-display');
      if (el) el.textContent = total;

      // Sync target-height input with current total if user hasn't edited it
      const tgt = document.getElementById('f-target-height');
      if (tgt && !tgt._userEdited) tgt.value = total;
    }
    renderPreview();
  }

  // ── Generate / Regenerate ────────────────────────────────────────────
  function generate() {
    if (!validateState()) return;
    kabinetLivePreview.pauseForApply();
    setStatus('생성 중…', '');
    sketchup['kabinet:generate'](JSON.stringify(state));
  }

  function regenerate() {
    if (!validateState()) return;
    kabinetLivePreview.pauseForApply();
    setStatus('재생성 중…', '');
    const payload = JSON.stringify({ spec: state, entityID: currentEntityID });
    sketchup['kabinet:regenerate'](payload);
  }

  // 수정하던 가구가 모델에서 지워졌을 때: 연결을 끊고 '가구 생성'으로 되돌린다
  function clearEntity() {
    currentEntityID = null;
    const b = document.getElementById('btn-apply');
    if (b) b.textContent = '가구 생성';
  }
  function regenerateMissing() {
    clearEntity();
    setStatus('수정하던 가구가 모델에 없어 새로 생성합니다.', '');
    generate();
  }

  function loadSelection() {
    sketchup['kabinet:load_selection']('');
  }

  // Called from Ruby after load_selection
  function loadSpec(payload) {
    try {
      const { spec, entityID } = typeof payload === 'string' ? JSON.parse(payload) : payload;
      state = deepClone(spec);
      currentEntityID = entityID || null;
      activePresetKey = '';
      kabinetLivePreview.reset();
      syncFormFromState();
      renderModuleList();
      updateTotalHeight();
      updateHeightSummary();
      setStatus('어셈블리 로드 완료.', 'ok');
    } catch (e) {
      setStatus('스펙 파싱 오류: ' + e.message, 'error');
    }
  }

  function onApplied(payload) {
    state = deepClone(payload.spec);
    currentEntityID = payload.entityID;
    syncFormFromState();
    renderModuleList();
    document.getElementById('btn-apply').textContent = '수정 적용';
    kabinetLivePreview.finishApply(true);
  }

  // ── Export ───────────────────────────────────────────────────────────
  function loadSelectionForExport() {
    sketchup['kabinet:load_selection']('');
  }

  function exportDrawings() {
    const checks = document.querySelectorAll('.view-check input:checked');
    let views  = Array.from(checks).map(c => c.value);
    if (views.length === 0) views = ['front', 'right', 'top', 'section'];
    // entityID 없으면 Ruby 쪽에서 현재 선택으로 폴백하도록 null 전송
    const payload = JSON.stringify({ views, entityID: currentEntityID || null });
    sketchup['kabinet:export_drawings'](payload);
    setStatus('씬 도면 출력 요청 중…', '');
  }

  function exportCutList() {
    if (!validateState()) return;
    setStatus('커트리스트 생성 중…', '');
    sketchup['kabinet:export_cutlist'](JSON.stringify(state));
  }

  // ── 발주도면 DXF (현재 폼 스펙 기준 — 모델 선택 불필요) ───────────────
  function exportDXF() {
    if (!validateState()) return;
    setStatus('발주도면 DXF 생성 중…', '');
    sketchup['kabinet:export_dxf'](JSON.stringify(state));
  }

  // 선택 그룹/컴포넌트 → 3면도 DXF (직접 모델링한 가구)
  function exportGroupDXF() {
    const chk = id => { const el = document.getElementById(id); return el ? el.checked : true; };
    const views = [];
    if (chk('g-view-front')) views.push('front');
    if (chk('g-view-side'))  views.push('side');
    if (chk('g-view-top'))   views.push('top');
    if (views.length === 0) { setStatus('출력할 뷰를 하나 이상 선택하세요.', 'error'); return; }
    const roundSel = document.getElementById('g-round');
    const opts = {
      views: views,
      dim_overall:  chk('g-dim-overall'),
      dim_units:    chk('g-dim-units'),
      eq:           chk('g-eq'),
      simplify_dims: chk('g-simplify'),
      hlr:          chk('g-hlr'),
      mesh_box:     chk('g-mesh-box'),
      round_mm:     roundSel ? parseFloat(roundSel.value) : 1,
      include_soft: document.getElementById('g-include-soft') ?
                    document.getElementById('g-include-soft').checked : false
    };
    setStatus('선택 모델 DXF 생성 중… (은선 제거 켜면 수 초 걸릴 수 있음)', '');
    sketchup['kabinet:export_group_dxf'](JSON.stringify(opts));
  }

  // ── 스마트 반영: 불러온 어셈블리가 있으면 재생성, 없으면 신규 생성 ────
  function smartApply() {
    if (currentEntityID) regenerate();
    else generate();
  }

  // ── Presets ──────────────────────────────────────────────────────────
  function savePreset() {
    const base = document.getElementById('f-preset-name').value.trim().replace(/\//g, '-');
    if (!base) { setStatus('프리셋 이름을 입력하세요.', 'error'); return; }
    const fEl = document.getElementById('f-preset-folder');
    const folder = fEl ? fEl.value.trim().replace(/\//g, '-') : '';
    const name = folder ? folder + '/' + base : base;
    sketchup['kabinet:save_preset'](JSON.stringify({ name, spec: state }));
    setTimeout(listPresets, 300);   // 통합 드롭다운 갱신
  }

  function listPresets() {
    sketchup['kabinet:list_presets']('');
  }

  function loadPresets(presets) {
    userPresets = presets || {};
    const keys = Object.keys(userPresets);

    // 통합 드롭다운의 '내 프리셋' 그룹 갱신
    const grp = document.getElementById('user-preset-group');
    if (grp) {
      grp.innerHTML = keys.map(name =>
        `<option value="user:${esc(name)}">${esc(name)}</option>`).join('');
    }
    renderPresetSidebar();
    const dl = document.getElementById('preset-folder-list');
    if (dl) dl.innerHTML = Object.keys(_userPresetFolders()).filter(Boolean)
      .map(f => `<option value="${escAttr(f)}">`).join('');

    const el = document.getElementById('preset-list');
    if (!el) return;
    if (keys.length === 0) {
      el.innerHTML = '<span style="color:var(--text-dim);font-size:12px">저장된 프리셋이 없습니다.</span>';
      return;
    }
    el.innerHTML = keys.map(name => `
      <div class="preset-item">
        <span class="preset-name">${esc(name)}</span>
        <button onclick="kabinet.applyPreset(${JSON.stringify(JSON.stringify(userPresets[name]))})">불러오기</button>
        <button class="del-btn" onclick="kabinet.deletePreset(${JSON.stringify(name)})">✕</button>
      </div>`).join('');
  }

  function applyPreset(specJson) {
    try {
      state = applyCommon(JSON.parse(specJson));
      currentEntityID = null;
      syncFormFromState();
      renderModuleList();
      updateTotalHeight();
      updateHeightSummary();
      setStatus('프리셋 적용됨.', 'ok');
    } catch (e) { setStatus('프리셋 오류: ' + e.message, 'error'); }
  }

  function deletePreset(name) {
    sketchup['kabinet:delete_preset'](name);
  }

  // ── Module list (delegates to modules.js) ────────────────────────────
  function addModule(kind) {
    // bed_gap은 런 모드(가로 배열) 전용 — 적층 모드에서 쓰면 3D 생성이
    // 실패한다 (모듈에 height/depth가 없어 Assembly#do_stack이 크래시).
    if (kind === 'bed_gap' && !state.run_mode) {
      setStatus('침대 공간은 "수평 런 모드"를 켠 뒤에 추가할 수 있습니다.', 'error');
      return;
    }
    if (kind === 'v_gap' && state.run_mode) {
      setStatus('개방 공간은 적층 모드(런 모드 꺼짐)에서만 추가할 수 있습니다.', 'error');
      return;
    }
    const w   = state.width   || 900;
    const d   = state.max_depth || 400;
    const mat = state.material || 'LPM';
    let mod;
    if (kind === 'drawer_module') {
      mod = { kind, width: w, depth: d, height: 200,
              body_thickness: 18, back_thickness: 9, has_back: true,
              drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 20,
              door_material: mat, handle_type: 'channel', handle_hole_mm: 128,
              material: mat, edge_banding_mm: 1.0 };
    } else if (kind === 'desk_module') {
      mod = { kind, width: w, depth: d || 700, height: 750,
              top_thickness: 25, leg_type: 'box',
              leg_w: 30, leg_d: 30, leg_inset_x: 30, leg_inset_y: 30,
              has_modesty_panel: false, pedestal: null, under_unit: null,
              material: mat, edge_banding_mm: 1.0 };
    } else if (kind === 'bed_gap') {
      mod = { kind, width: 1600, label: '침대 공간', storage: true,
              platform_height: 350, bed_depth: 2000, drawer_count: 2,
              drawer_side: 'foot', lift_up_storage: false,
              material: mat, door_material: mat };
    } else if (kind === 'v_gap') {
      mod = { kind, height: 500, label: '개방 공간' };
    } else {
      mod = { kind, width: w, depth: d, height: 400,
              body_thickness: 18, back_thickness: 9, has_back: true,
              door_config: 'none', door_type: 'swing', door_thickness: 20,
              door_material: mat, handle_type: 'none', handle_hole_mm: 128,
              door_side_gap_mm: 2,
              suppress_left_side: false, suppress_right_side: false,
              material: mat, edge_banding_mm: 1.0,
              shelves: [], accessories: [],
              vertical_dividers: [], cell_shelves: [], cell_drawers: [] };
    }
    state.modules.push(mod);
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
  }

  function removeModule(idx) {
    state.modules.splice(idx, 1);
    renderModuleList();
    updateTotalHeight();
    updateHeightSummary();
  }

  function moveModule(idx, dir) {
    const to = idx + dir;
    if (to < 0 || to >= state.modules.length) return;
    [state.modules[idx], state.modules[to]] = [state.modules[to], state.modules[idx]];
    renderModuleList();
    updateHeightSummary();
  }

  // ── Height summary bar in modules tab ───────────────────────────────
  function updateHeightSummary() {
    renderPreview();
    const el = document.getElementById('module-height-summary');
    if (!el) return;
    if (state.modules.length === 0) { el.innerHTML = ''; return; }
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base = state.base_height || 0;
    const parts = [];

    if (state.run_mode) {
      // Run mode: show section widths + shared height
      const runH   = state.run_height || 740;
      const totalW = state.modules.reduce((s, m) => s + (m.width || 0), 0);
      const totalH = base + runH + topT + _epTopT();
      if (base > 0)  parts.push('받침 ' + base);
      state.modules.forEach((m, i) => {
        const tag = m.kind === 'drawer_module' ? '서랍'
                  : m.kind === 'bed_gap'       ? '침대'
                  : m.kind === 'desk_module'   ? '책상' : '선반';
        parts.push('S' + (i+1) + '(' + tag + ') W' + m.width);
      });
      if (topT > 0) parts.push('상판 ' + topT);
      if (_epTopT() > 0) parts.push('상부EP ' + _epTopT());
      el.innerHTML =
        '<span class="hs-label">런 높이 ' + totalH + 'mm / 섹션 총 폭 ' + totalW + 'mm</span>' +
        '<span class="hs-parts">' + parts.join(' + ') + '</span>';
    } else {
      const modsH = state.modules.reduce((s, m) => s + (m.height || 0), 0);
      const total = base + modsH + topT + _epTopT();
      if (base > 0) parts.push('받침 ' + base);
      state.modules.forEach((m, i) => {
        const tag = m.kind === 'drawer_module' ? '서랍'
                  : m.kind === 'desk_module'   ? '책상'
                  : m.kind === 'bed_gap'       ? '침대' : '선반';
        parts.push('M' + (i+1) + '(' + tag + ') ' + (m.height || '?'));
      });
      if (topT > 0) parts.push('상판 ' + topT);
      if (_epTopT() > 0) parts.push('상부EP ' + _epTopT());
      el.innerHTML =
        '<span class="hs-label">총 높이 ' + total + 'mm</span>' +
        '<span class="hs-parts">' + parts.join(' + ') + '</span>';
    }
  }

  // ── Status ───────────────────────────────────────────────────────────
  function onSuccess(msg) { setStatus(msg || '완료.', 'ok'); }
  function onError(msg)   {
    setStatus('오류: ' + msg, 'error');
    if (typeof kabinetLivePreview !== 'undefined') kabinetLivePreview.finishApply(false);
  }

  function setStatus(msg, cls) {
    const bar = document.getElementById('status-bar');
    bar.textContent = msg;
    bar.className   = 'status-bar' + (cls ? ' ' + cls : '');
  }

  // ── Validation ───────────────────────────────────────────────────────
  function validateState() {
    if (!state.name)           { setStatus('이름을 입력하세요.', 'error'); return false; }
    if (state.width <= 0)      { setStatus('폭은 0보다 커야 합니다.', 'error'); return false; }
    if (state.max_depth <= 0)  { setStatus('깊이는 0보다 커야 합니다.', 'error'); return false; }
    if (state.modules.length === 0) { setStatus('모듈을 1개 이상 추가하세요.', 'error'); return false; }
    for (let i = 0; i < state.modules.length; i++) {
      const m = state.modules[i];
      if (m.kind === 'bed_gap') continue;   // bed_gap has no height/depth
      if (m.height <= 0) { setStatus('모듈 ' + (i+1) + ': 높이가 0보다 커야 합니다.', 'error'); return false; }
      if (m.depth  <= 0) { setStatus('모듈 ' + (i+1) + ': 깊이가 0보다 커야 합니다.', 'error'); return false; }
      if (m.kind === 'drawer_module' && (m.drawer_count < 1 || m.drawer_count > 6)) {
        setStatus('모듈 ' + (i+1) + ': 서랍 수는 1~6개 사이여야 합니다.', 'error'); return false;
      }
    }
    return true;
  }

  // ── Sync form ↔ state ────────────────────────────────────────────────
  function syncFormFromState() {
    document.getElementById('btn-apply').textContent = currentEntityID ? '수정 적용' : '가구 생성';
    setVal('f-name',   state.name);
    setVal('f-width',  state.width);
    setVal('f-depth',  state.max_depth);
    setVal('f-base',   state.base_height || 0);

    const kickChk = document.getElementById('f-kickboard');
    if (kickChk) kickChk.checked = state.has_kickboard !== false;

    const baseSel = document.getElementById('f-base-type');
    if (baseSel) baseSel.value = state.base_type || 'wood';

    const matSel = document.getElementById('f-material');
    if (matSel) matSel.value = state.material || 'LPM';

    const ftSel = document.getElementById('f-furniture-type');
    if (ftSel) ftSel.value = state.furniture_type || '';
    renderPresetSidebar();
    renderWardrobeRow();

    const hasTop = !!state.top_panel;
    document.getElementById('f-top-use').checked = hasTop;
    document.getElementById('top-panel-fields').style.display = hasTop ? '' : 'none';
    if (hasTop) setVal('f-top-t', state.top_panel.thickness);

    document.getElementById('f-ep-left').checked  = !!(state.ep && state.ep.left);
    document.getElementById('f-ep-right').checked = !!(state.ep && state.ep.right);
    const epTopChk = document.getElementById('f-ep-top');
    if (epTopChk) epTopChk.checked = !!(state.ep && state.ep.top);
    setVal('f-ep-t', state.ep ? state.ep.thickness : 20);
    const epFlushChk = document.getElementById('f-ep-top-flush');
    if (epFlushChk) epFlushChk.checked = !!state.ep_top_flush;

    // Run mode
    const runChk = document.getElementById('f-run-mode');
    if (runChk) {
      runChk.checked = !!state.run_mode;
      onRunMode(!!state.run_mode);   // update visibility of dependent rows
    }
    setVal('f-run-height', state.run_height || 740);

    if (currentEntityID) {
      const expEl = document.getElementById('f-export-id');
      if (expEl) expEl.value = currentEntityID;
    }

    // Reset preset info box
    const info = document.getElementById('preset-info');
    if (info) info.style.display = 'none';

    updateTotalHeight();
  }

  function setVal(id, val) {
    const el = document.getElementById(id);
    if (el) el.value = val;
  }

  // ── 실시간 정면도 미리보기 (canvas) ──────────────────────────────────
  // Ruby Drawing2D.front_view와 같은 배치 논리의 축약판.
  // ── 실제 모델 형상 기반 정면도 (SketchUp 안에서만) ─────────────────────
  // JS 그림은 즉시 대략 표시하고, 곧이어 Ruby가 실제 생성 코드로 만든 정면 투영으로 덮어 그린다.
  let preview2dRev = 0;
  let preview2dTimer = null;
  function requestPreview2d() {
    if (typeof sketchup === 'undefined' || !sketchup['kabinet:preview2d']) return;
    clearTimeout(preview2dTimer);
    const rev = ++preview2dRev;
    preview2dTimer = setTimeout(() => {
      try { sketchup['kabinet:preview2d'](JSON.stringify({ rev, spec: state })); } catch (e) {}
    }, 200);
  }
  function onPreview2d(res) {
    if (!res || res.rev !== preview2dRev || res.error || !res.segs || !res.segs.length) return;
    const cv = document.getElementById('preview-canvas');
    if (!cv || !cv.getContext) return;
    const ctx = cv.getContext('2d');
    const CW = cv.width, CH = cv.height, pad = 16;
    const w = res.max[0] - res.min[0], h = res.max[1] - res.min[1];
    if (w <= 0 || h <= 0) return;
    const sc = Math.min((CW - 2 * pad) / w, (CH - 2 * pad) / h);
    const ox = (CW - w * sc) / 2, oy = (CH + h * sc) / 2;
    const X = x => ox + (x - res.min[0]) * sc, Y = z => oy - (z - res.min[1]) * sc;
    ctx.clearRect(0, 0, CW, CH);
    ctx.lineWidth = 1;
    const hide = !!(document.getElementById('live-preview-internal') || {}).checked;
    [0, 2, 1].forEach(layer => {     // 내부(점선) → 바깥 부재(걸레받이·EP·상판 실선) → 앞판(실선)
      if (layer === 1 && hide) return;
      ctx.strokeStyle = layer === 1 ? '#5b9bd5' : layer === 2 ? '#c9c9c9' : '#7a7a7a';
      ctx.setLineDash(layer === 0 ? [3, 3] : []);
      ctx.beginPath();
      res.segs.forEach(s => { if (s[4] === layer) { ctx.moveTo(X(s[0]), Y(s[1])); ctx.lineTo(X(s[2]), Y(s[3])); } });
      ctx.stroke();
    });
    ctx.setLineDash([]);
    const meta = document.getElementById('preview-size');
    if (meta) meta.textContent = Math.round(w) + ' × ' + (state.max_depth || 0) + ' × ' + Math.round(h) + ' mm (실제 형상)';
  }

  function renderPreview() {
    if (typeof kabinetLivePreview !== 'undefined') kabinetLivePreview.schedule();
    requestPreview2d();
    const cv = document.getElementById('preview-canvas');
    if (!cv || !cv.getContext) return;
    const ctx = cv.getContext('2d');
    const CW = cv.width, CH = cv.height;
    ctx.clearRect(0, 0, CW, CH);

    const ep   = state.ep || {};
    const epT  = ep.thickness || 20;
    const epL  = ep.left ? epT : 0;
    const epR  = ep.right ? epT : 0;
    const topT = state.top_panel ? (state.top_panel.thickness || 0) : 0;
    const base = state.base_height || 0;
    const mods = state.modules || [];

    let carW, contH;
    if (state.run_mode) {
      carW  = mods.reduce((a, m) => a + (m.width || 0), 0);
      contH = state.run_height || 740;
    } else {
      carW  = Math.max((state.width || 0) - epL - epR, 10);
      contH = mods.filter(m => m.kind !== 'bed_gap')
                  .reduce((a, m) => a + (m.height || 0), 0);
    }
    const totW = epL + carW + epR;
    const totH = base + contH + topT + (ep.top ? epT : 0);

    const meta = document.getElementById('preview-size');
    if (meta) meta.textContent =
      totW > 0 && totH > 0 ? totW + ' × ' + (state.max_depth || 0) + ' × ' + totH + ' mm' : '—';

    if (totW <= 0 || totH <= 0 || mods.length === 0) {
      ctx.fillStyle = '#666';
      ctx.font = '12px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('모듈을 추가하면 미리보기가 표시됩니다', CW / 2, CH / 2);
      return;
    }

    const pad = 16;
    const sc  = Math.min((CW - 2 * pad) / totW, (CH - 2 * pad) / totH);
    const ox  = (CW - totW * sc) / 2;
    const oy  = (CH + totH * sc) / 2;
    const X = x => ox + x * sc;
    const Y = y => oy - y * sc;

    const OUT = '#c9c9c9', FRONT = '#5b9bd5', HID = '#5f5f5f', SYM = '#6fae6f';
    function sRect(x, y, w, h, color, fill) {
      if (fill) { ctx.fillStyle = fill; ctx.fillRect(X(x), Y(y + h), w * sc, h * sc); }
      ctx.strokeStyle = color; ctx.strokeRect(X(x), Y(y + h), w * sc, h * sc);
    }
    function sLine(x1, y1, x2, y2, color, dash) {
      ctx.strokeStyle = color;
      ctx.setLineDash(dash ? [4, 3] : []);
      ctx.beginPath(); ctx.moveTo(X(x1), Y(y1)); ctx.lineTo(X(x2), Y(y2)); ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.lineWidth = 1;

    // 외곽 + 받침 + EP + 상판
    // bed_gap 있는 런 모드는 침대 공간 제외 구간별 외곽 (실물과 동일)
    const hasGap = state.run_mode && mods.some(m => m.kind === 'bed_gap');
    if (hasGap) {
      let sx = 0, segStart = null, segW = 0;
      const segs = [];
      mods.forEach(m => {
        const w = m.width || 0;
        if (m.kind === 'bed_gap') {
          if (segStart !== null && segW > 0) segs.push([segStart, segW]);
          segStart = null; segW = 0;
        } else {
          if (segStart === null) segStart = sx;
          segW += w;
        }
        sx += w;
      });
      if (segStart !== null && segW > 0) segs.push([segStart, segW]);
      segs.forEach(([x0, w0]) => {
        sRect(epL + x0, base, w0, contH, OUT);
        if (topT > 0) sRect(epL + x0, base + contH, w0, topT, OUT);
      });
      const capG = totH - (ep.top ? epT : 0);
      if (epL) sRect(0, base, epL, capG - base, OUT);
      if (epR) sRect(totW - epR, base, epR, capG - base, OUT);
      if (ep.top) sRect(0, capG, totW, epT, OUT);
    } else {
      const cap = totH - (ep.top ? epT : 0);
      sRect(0, base, totW, cap - base, OUT);
      if (base > 0) sLine(0, base, totW, base, OUT);
      if (epL) sLine(epL, base, epL, cap, OUT);
      if (epR) sLine(totW - epR, base, totW - epR, cap, OUT);
      if (topT > 0) sLine(epL, cap - topT, epL + carW, cap - topT, OUT);
      if (ep.top) sRect(0, cap, totW, epT, OUT);
    }

    // 모듈 순회 (stack: 아래→위 / run: 좌→우)
    let cx = 0, cz = 0;
    mods.forEach(m => {
      let mx, mz, mw, mh;
      if (state.run_mode) {
        mw = m.width || 0; mh = contH; mx = cx; mz = 0; cx += mw;
        if (m.kind === 'bed_gap') {
          // 수납침대: 바닥부터 플랫폼 높이만큼 (받침 무시)
          if (m.storage) {
            const ph = m.platform_height || 350;
            sRect(epL + mx, 0, mw, ph, OUT);
            const n = Math.max(m.drawer_count || 2, 1);
            const fw = (mw - 4 - 3 * (n - 1)) / n;
            for (let k = 0; k < n; k++) {
              sRect(epL + mx + 2 + k * (fw + 3), 2, fw, ph - 4, FRONT, 'rgba(91,155,213,.10)');
            }
          }
          return;
        }
      } else {
        if (m.kind === 'bed_gap') return;
        if (m.kind === 'v_gap') { cz += m.height || 0; return; }  // 개방 공간 — 높이만 전진
        mw = carW; mh = m.height || 0; mx = 0; mz = cz; cz += mh;
      }
      drawModuleFront(m, epL + mx, base + mz, mw, mh);
    });

    function drawModuleFront(m, x, z, w, h) {
      if (m.kind === 'drawer_module') {
        const n = m.drawer_count || 1;
        const fh = (h - 4 - 3 * (n - 1)) / n;
        for (let i = 0; i < n; i++) {
          sRect(x + 2, z + 2 + i * (fh + 3), w - 4, fh, FRONT, 'rgba(91,155,213,.10)');
        }
      } else if (m.kind === 'desk_module') {
        const tt = m.top_thickness || 25;
        sRect(x, z + h - tt, w, tt, OUT);
        const lw = m.leg_w || 30, ix = m.leg_inset_x || 30;
        const ped = m.pedestal, pedOn = ped && ped.enabled !== false;
        const pos = pedOn ? (ped.position || 'right') : '';
        if (pos !== 'left')  sRect(x + ix, z, lw, h - tt, OUT);
        if (pos !== 'right') sRect(x + w - ix - lw, z, lw, h - tt, OUT);
        if (pedOn) {
          const pw = ped.width || 450;
          const px = pos === 'left' ? x : x + w - pw;
          sRect(px, z, pw, h - tt, OUT);
          const n = ped.drawer_count || 3;
          const fh = (h - tt - 4 - 3 * (n - 1)) / n;
          for (let i = 0; i < n; i++) sRect(px + 2, z + 2 + i * (fh + 3), pw - 4, fh, FRONT);
        }
      } else if (m.kind === 'shelf_module') {
        const bt = m.body_thickness || 18;
        // 내부 구조 (은선)
        (m.vertical_dividers || []).forEach(d => {
          const dx = x + bt + (d.x || 0);
          sLine(dx, z + bt, dx, z + h - bt, HID, true);
        });
        (m.shelves || []).forEach(s => {
          const sy = z + (s.height_from_bottom || 0);
          sLine(x + bt, sy, x + w - bt, sy, HID, true);
        });
        const cells = cellEdges(m, w - 2 * bt);
        // 셀 선반 (모듈 바닥 기준 높이 — 3D와 동일)
        (m.cell_shelves || []).forEach(cs => {
          const rng = cells[cs.cell || 0];
          if (!rng) return;
          const sy = z + (cs.height_from_bottom || 0);
          sLine(x + bt + rng[0], sy, x + bt + rng[1], sy, HID, true);
        });
        // 셀 서랍 (근사 표시)
        (m.cell_drawers || []).forEach(cd => {
          const rng = cells[cd.cell || 0];
          if (!rng) return;
          const n = cd.count || 2, ih = h - 2 * bt;
          const fh = (ih - 4 - 3 * (n - 1)) / n;
          for (let i = 0; i < n; i++) {
            sRect(x + bt + rng[0] + 2, z + bt + 2 + i * (fh + 3),
                  rng[1] - rng[0] - 4, fh, FRONT, 'rgba(91,155,213,.10)');
          }
        });
        // 도어
        const dc = m.door_config || 'none';
        if (dc !== 'none') {
          const g  = m.door_side_gap_mm != null ? m.door_side_gap_mm : 2;
          const dh = h - 4;
          if (m.door_type === 'sliding') {
            const dw = (w + 60) / 2;
            sRect(x, z + 5, dw, h - 20, FRONT, 'rgba(91,155,213,.08)');
            sRect(x + w - dw, z + 5, dw, h - 20, FRONT, 'rgba(91,155,213,.08)');
          } else if (dc === 'pair') {
            const dw = (w - 2 * g - 3) / 2;
            sRect(x + g, z + 2, dw, dh, FRONT, 'rgba(91,155,213,.08)');
            sRect(x + g + dw + 3, z + 2, dw, dh, FRONT, 'rgba(91,155,213,.08)');
            swingV(x + g, z + 2, dw, dh, true);
            swingV(x + g + dw + 3, z + 2, dw, dh, false);
          } else {
            sRect(x + g, z + 2, w - 2 * g, dh, FRONT, 'rgba(91,155,213,.08)');
            swingV(x + g, z + 2, w - 2 * g, dh, true);
          }
        }
      }
    }

    function swingV(x, z, w, h, hingeLeft) {
      if (hingeLeft) {
        sLine(x, z, x + w, z + h / 2, SYM);
        sLine(x, z + h, x + w, z + h / 2, SYM);
      } else {
        sLine(x + w, z, x, z + h / 2, SYM);
        sLine(x + w, z + h, x, z + h / 2, SYM);
      }
    }

    function cellEdges(m, innerW) {
      const divs = (m.vertical_dividers || []).slice()
        .sort((a, b) => (a.x || 0) - (b.x || 0));
      const edges = [];
      let prev = 0;
      divs.forEach(d => {
        edges.push([prev, d.x || 0]);
        prev = (d.x || 0) + (d.thickness || 18);
      });
      edges.push([prev, innerW]);
      return edges;
    }
  }

  // ── Utilities ────────────────────────────────────────────────────────
  // ── 도면 치수표 한 줄 → 가구 spec (기존 프리셋 구조 유지, 값만 변경) ───────────
  // row: { preset, name, width, height, depth, thickness, doors, drawers }  (mm, 빈 값=프리셋 값)
  // 현재 폼의 state 는 건드리지 않는다(임시로 바꿨다가 복원).
  function buildDrawingSpec(row) {
    const preset = FURNITURE_PRESETS[row.preset];
    if (!preset) return { error: '프리셋을 선택하세요.' };
    const saved = { state, key: activePresetKey, id: currentEntityID };
    const pos = (v) => { const n = parseFloat(v); return n > 0 ? n : 0; };
    try {
      state = applyCommon(preset);
      delete state._info;
      if (!state.run_mode) {
        const iw = _carcaseInnerWidth(state.width);
        state.modules.forEach(m => { if (m.kind !== 'bed_gap') m.width = iw; });
      }
      // 1) 판재 두께 (뒷판 제외) — 높이·내부 구성 계산 전에 적용
      const t = pos(row.thickness);
      if (t) {
        (state.modules || []).forEach(m => {
          ['body_thickness', 'door_thickness', 'drawer_thickness', 'top_thickness'].forEach(k => { if (m[k]) m[k] = t; });
          ['shelves', 'vertical_dividers', 'cell_shelves'].forEach(k => (m[k] || []).forEach(x => { x.thickness = t; }));
        });
        if (state.top_panel) state.top_panel.thickness = t;
        if (state.ep) state.ep.thickness = t;
      }
      if (state.wardrobe_layout) applyWardrobeLayout(state.wardrobe_layout, true);
      // 2) 깊이 → 3) 폭 → 4) 총 높이 (모두 기존 프리셋 보정 로직 그대로)
      if (pos(row.depth)) onField('max_depth', pos(row.depth));
      if (pos(row.width)) onField('width', pos(row.width));
      if (pos(row.height)) onTargetHeightLive(pos(row.height));
      // 5) 도어·서랍
      if (row.doors) {
        state.modules.forEach(m => {
          if (m.kind !== 'shelf_module') return;
          m.door_config = row.doors;
          m.door_type = row.doors === 'none' ? 'none' : 'swing';
        });
      }
      if (pos(row.drawers)) {
        state.modules.forEach(m => { if (m.kind === 'drawer_module') m.drawer_count = Math.round(pos(row.drawers)); });
      }
      const spec = deepClone(state);
      if (row.name) spec.name = row.name;
      return { spec };
    } catch (e) {
      return { error: e.message };
    } finally {
      state = saved.state; activePresetKey = saved.key; currentEntityID = saved.id;
      renderModuleList(); updateTotalHeight(); updateHeightSummary();
    }
  }

  function deepClone(o) { return JSON.parse(JSON.stringify(o)); }
  function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }

  function getState() { return state; }

  // ── Wire up target height user-edit flag ─────────────────────────────
  document.addEventListener('DOMContentLoaded', () => {
    const tgt = document.getElementById('f-target-height');
    if (tgt) tgt.addEventListener('input', () => { tgt._userEdited = true; });
    updateTotalHeight();
    renderPreview();
    renderPresetSidebar();
    showView('common'); renderCommonForm();   // 시작 화면 = 가구 공통사항
    // 저장 프리셋 → 통합 드롭다운 채우기 (SketchUp 콜백 가능할 때만)
    try { if (typeof sketchup !== 'undefined') sketchup['kabinet:list_presets'](''); } catch (e) {}
  });

  // ── Public API ───────────────────────────────────────────────────────
  return {
    switchTab, onField, onTopPanelToggle, onTopPanelField, onEP, onEpTopFlush,
    generate, regenerate, smartApply, loadSelection, loadSpec, clearEntity, regenerateMissing,
    exportDrawings, exportCutList, exportDXF, exportGroupDXF, loadSelectionForExport,
    savePreset, listPresets, loadPresets, applyPreset, deletePreset,
    addModule, removeModule, moveModule,
    loadFurniturePreset, onPresetChange, renderPresetSidebar,
    addToCombine, removeFromCombine, renderCombine, runSidebarAction,
    showView, setLibrary, setStatus, onPreview2d, installCountertop, setCountertopMaterials,
    setCommon, applyCommonAll, applyCommon, applyWardrobeLayout, setWardrobeOpt, setInnerDrawerPreset, setInnerDrawer, moveCombine, clearCombine, applyCombine, combinePresets,
    syncWidthToModules, distributeHeight,
    onTargetHeightLive,
    updateTotalHeight, updateHeightSummary, renderPreview,
    onRunMode,
    onSuccess, onError, onApplied, buildDrawingSpec, callSketchup,
    getState, getEntityID: () => currentEntityID
  };
})();
