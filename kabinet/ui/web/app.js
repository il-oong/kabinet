/* =====================================================================
   Kabinet — Main application state and bridge layer
   ===================================================================== */

/* ── 가구 유형 기본 프리셋 ──────────────────────────────────────────────
   width/max_depth/base_height 는 어셈블리 치수.
   모듈 width 는 어셈블리 width 와 동일하게 설정.
   총 높이 계산: base_height + Σ(module.height) + top_panel.thickness
================================================================== */
const FURNITURE_PRESETS = {
  wardrobe: {
    name: '붙박이장',
    furniture_type: 'wardrobe',
    width: 1200, max_depth: 580, base_height: 100,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 100(걸레받이) + 1982 + 18(상판) = 2100mm
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 580, height: 1982,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0, shelves: [],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1000, depth_inset: 75, diameter: 32 }
        ]
      }
    ],
    _info: '표준 붙박이장 W1200×D580×H2100 | 걸레받이100 + 양개여닫이 + 상의 행거'
  },

  kitchen_base: {
    name: '주방 하부장',
    furniture_type: 'kitchen_base',
    width: 900, max_depth: 580, base_height: 80,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: { thickness: 20 },
    // 총 높이: 80(걸레받이) + 740(단일 몸통) + 20(상판) = 840mm
    // 주방 하부장은 단일 카케이스 몸통으로 구성 (도어+선반 내부 배치)
    modules: [
      { kind: 'shelf_module', width: 900, depth: 580, height: 740,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 330, thickness: 18, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '주방 하부장 W900×D580×H840 | 걸레받이80+단일몸통740+상판20. 작업대 840mm'
  },

  kitchen_upper: {
    name: '주방 상부장',
    furniture_type: 'kitchen_upper',
    width: 900, max_depth: 320, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 15 },
    top_panel: null,
    // 총 높이: 0 + 700 = 700mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 320, height: 700,
        body_thickness: 15, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 15,
        door_material: 'LPM', handle_type: 'knob', material: 'LPM',
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 20 },
    // 총 높이: 0 + 480(서랍3단) + 200(오픈선반) + 20(상판) = 700mm
    // 하단 서랍: 주수납. 상단 오픈선반: 화장품·소품 진열.
    // 접합부(서랍→선반) suppress_bottom 으로 이중패널 방지.
    modules: [
      { kind: 'drawer_module', width: 900, depth: 350, height: 480,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'cup_pull', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 900, depth: 350, height: 200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 18,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1782 + 18 = 1800mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 350, height: 1782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1782 + 18 = 1800mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 300, height: 1782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 18,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 25 },
    // 총 높이: 80 + 200 + 495 + 25 = 800mm (입식 표준 TV장)
    // 실무 보정: 1764 폭 통짜 서랍은 레일 하중 불가 → 3칸 분할 서랍.
    //            상부는 878mm/짝 여닫이 대신 중앙 분할 오픈 선반.
    modules: [
      { kind: 'shelf_module', width: 1764, depth: 450, height: 200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM',
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
        door_config: 'none', door_type: 'swing', door_thickness: 18,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    modules: [
      { kind: 'shelf_module', width: 800, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    modules: [
      // 실무 보정: 1164 스팬 18T 선반 처짐 → 중앙 분할판 + 셀 선반
      { kind: 'shelf_module', width: 1200, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm (서랍 4단)
    modules: [
      { kind: 'drawer_module', width: 400, depth: 450, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 4, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '서랍장 타워 W400×D450×H1050 | 서랍 4단. 침실/드레스룸 범용'
  },

  wardrobe_sliding: {
    name: '슬라이딩 붙박이장',
    furniture_type: 'wardrobe_sliding',
    width: 1600, max_depth: 600, base_height: 100,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 100 + 1982 + 18 = 2100mm
    modules: [
      { kind: 'shelf_module', width: 1600, depth: 600, height: 1982,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'sliding', door_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM',
        edge_banding_mm: 1.0,
        // 실무 보정: 2단 행거 표준 높이 (상단 ~1850, 하단 ~930 — 상의 2단걸이)
        // 기존 500/1000은 옷이 바닥에 끌리는 높이였음. 1564 스팬 선반은 처짐 → 제거.
        shelves: [],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1850, depth_inset: 75, diameter: 32 },
          { kind: 'hanging_rod', height_from_bottom: 930,  depth_inset: 75, diameter: 32 }
        ]
      }
    ],
    _info: '슬라이딩 붙박이장 W1600×D600×H2100 | 미닫이 2짝·2단 행거(1850/930). 드레스룸'
  },

  // ── 책상 프리셋 ─────────────────────────────────────────────────────────

  desk_basic: {
    name: '기본 책상',
    furniture_type: 'desk_basic',
    width: 1400, max_depth: 700, base_height: 0,
    material: 'LPM',
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,  // 상판이 desk_module 자체에 포함됨
    // 총 높이 = 0 + 750 = 750mm (상판 높이 기준)
    modules: [
      { kind: 'desk_module', width: 1400, depth: 700, height: 750,
        top_thickness: 25, leg_type: 'box', leg_w: 60, leg_d: 60,
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
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,
    // 우측 페데스탈 W450으로 지지 → 우측 다리 생략
    modules: [
      { kind: 'desk_module', width: 1400, depth: 700, height: 750,
        top_thickness: 25, leg_type: 'box', leg_w: 60, leg_d: 60,
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
    ep: { left: false, right: false, thickness: 18 },
    top_panel: { thickness: 25 },     // 런 공통 상판
    // 런 모드: 책상(1400) + 코너 선반(700) 배치
    modules: [
      { kind: 'desk_module', width: 1400, depth: 700, height: 725,
        top_thickness: 25, leg_type: 'box', leg_w: 60, leg_d: 60,
        leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false,
        pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'desk_module', width: 700, depth: 700, height: 725,
        top_thickness: 25, leg_type: 'box', leg_w: 60, leg_d: 60,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1032 + 18 = 1050mm
    // 내부: 세로 3칸(분할 2개) → 좌칸 선반, 중칸 서랍, 우칸 선반
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 400, height: 1032,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 18,
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
    run_height: 660,          // 작업대 하부 내부 높이 (받침80+본체660+상판20=760mm, 작업대는 별도)
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 20 },
    // 수평 배열: 600(서랍) + 600(선반도어) + 600(선반도어)
    // 총 외부 폭: 18(EP좌) + 1800 + 18(EP우) = 1836mm
    // 총 외부 높이: 80 + 660 + 20 = 760mm (작업대 높이)
    modules: [
      { kind: 'drawer_module', width: 600, depth: 580, height: 660,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 600, depth: 580, height: 660,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 18, depth_inset: 20 }],
        accessories: []
      },
      { kind: 'shelf_module', width: 600, depth: 580, height: 660,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 300, thickness: 18, depth_inset: 20 }],
        accessories: []
      }
    ],
    _info: '주방 런 1800mm | 서랍(600)+수납(600)+수납(600). 런높이 660 → 작업대 760mm'
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: null,    // 전고 타워 — 상판 없음
    // 좌타워 600 + 침대 공간 1600(퀸사이즈) + 우타워 600 = 2800mm
    modules: [
      { kind: 'shelf_module', width: 600, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 500, thickness: 18, depth_inset: 20 },
          { height_from_bottom: 1000, thickness: 18, depth_inset: 20 }
        ],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1500, depth_inset: 75, diameter: 32 }
        ],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      },
      { kind: 'bed_gap', width: 1600, label: '침대 공간 (퀸 1600mm)',
        storage: true, platform_height: 350, bed_depth: 2000,
        drawer_count: 2, drawer_side: 'foot', lift_up_storage: false,
        material: 'LPM', door_material: 'LPM' },
      { kind: 'shelf_module', width: 600, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },  // 브릿지 상판 (타워 위를 잇는 가로 패널)
    modules: [
      { kind: 'shelf_module', width: 600, depth: 580, height: 1200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
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
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
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
    width: 1200, max_depth: 580, base_height: 80,
    has_kickboard: true,
    material: 'LPM',
    run_mode: false,
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 80(받침) + 1500(행거존) + 502(상부존) + 18(상판) = 2100mm
    modules: [
      // 하부: 긴 행거 + 하단 선반
      { kind: 'shelf_module', width: 1200, depth: 580, height: 1500,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        // 1164 스팬 18T 처짐 → 하단 선반 25T
        shelves: [
          { height_from_bottom: 220, thickness: 25, depth_inset: 20 }
        ],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1100, depth_inset: 75, diameter: 32 }
        ],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      },
      // 상부: 도어 수납존 (이불·계절용품)
      { kind: 'shelf_module', width: 1200, depth: 580, height: 502,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'knob', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        // 1164 스팬 18T 처짐 → 25T (이불 하중)
        shelves: [
          { height_from_bottom: 260, thickness: 25, depth_inset: 20 }
        ],
        accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '자녀방 붙박이장 W1200×D580×H2100 | 하부 행거존H1500 + 상부 수납존H502 | 초등~고등 공용'
  },

  kids_upper_open: {
    name: '오픈 상부장',
    furniture_type: 'kids_upper_open',
    width: 1200, max_depth: 280, base_height: 0,
    has_kickboard: false,
    material: 'LPM',
    run_mode: false,
    ep: { left: false, right: false, thickness: 15 },
    top_panel: null,
    // 총 높이: 400mm — 책상·수납장 상부 벽면 설치용
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 280, height: 400,
        body_thickness: 15, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'swing', door_thickness: 15,
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
    ep: { left: false, right: false, thickness: 15 },
    top_panel: null,
    // 총 높이: 400mm — 방진+정리 효과 도어형
    modules: [
      { kind: 'shelf_module', width: 1200, depth: 280, height: 400,
        body_thickness: 15, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 15,
        door_material: 'LPM', handle_type: 'knob', handle_hole_mm: 128,
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
    ep: { left: false, right: false, thickness: 18 },
    top_panel: null,
    // 총 높이: 750(책상) + 500(개방 이격) + 400(상부장) = 1650mm
    // 보고서 기준: 책상고 750mm, 상부장 D280 H400mm, 책상면~상부장 이격 500mm
    modules: [
      { kind: 'desk_module', width: 1200, depth: 600, height: 750,
        top_thickness: 25, leg_type: 'box',
        leg_w: 60, leg_d: 60, leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false, pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'v_gap', height: 500, label: '책상 위 개방 (모니터/작업 공간)' },
      { kind: 'shelf_module', width: 1200, depth: 280, height: 400,
        body_thickness: 15, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 15,
        door_material: 'LPM', handle_type: 'knob', handle_hole_mm: 128,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: null,
    // 좌선반 500 + 싱글침대 1000 + 우서랍 500 = 2000mm
    modules: [
      { kind: 'shelf_module', width: 500, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
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
        drawer_count: 4, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 1182 + 18 = 1200mm
    modules: [
      { kind: 'shelf_module', width: 900, depth: 300, height: 1182,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 18,
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
    ep: { left: false, right: false, thickness: 18 },
    top_panel: { thickness: 18 },
    // 총 높이: 0 + 782 + 18 = 800mm — 정사각형 오픈 선반, 코너 배치용
    modules: [
      { kind: 'shelf_module', width: 600, depth: 600, height: 782,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'none', door_type: 'none', door_thickness: 18,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 25 },
    // 런 모드: 책상(1200) + 사이드 수납장(600)
    modules: [
      { kind: 'desk_module', width: 1200, depth: 700, height: 725,
        top_thickness: 25, leg_type: 'box',
        leg_w: 60, leg_d: 60, leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false, pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 600, depth: 400, height: 725,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
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
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 25 },
    // 수평 배열: 600(서랍2단) + 1200(도어수납) + 600(도어수납)
    modules: [
      { kind: 'drawer_module', width: 600, depth: 450, height: 420,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 1200, depth: 450, height: 420,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', handle_hole_mm: 128,
        door_side_gap_mm: 2,
        suppress_left_side: false, suppress_right_side: false,
        material: 'LPM', edge_banding_mm: 1.0,
        // 1164 스팬 18T 처짐 → 25T (실무 보정)
        shelves: [{ height_from_bottom: 200, thickness: 25, depth_inset: 0 }],
        accessories: [], vertical_dividers: [], cell_shelves: [], cell_drawers: []
      },
      { kind: 'shelf_module', width: 600, depth: 450, height: 420,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', handle_hole_mm: 128,
        door_side_gap_mm: 2,
        suppress_left_side: false, suppress_right_side: false,
        material: 'LPM', edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 200, thickness: 18, depth_inset: 0 }],
        accessories: [], vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '거실 수납 런 W2400×D450×H525 | 서랍(600)+도어수납(1200+600). 핸들리스 채널. 로우보드'
  }
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
    ep: { left: true, right: true, top: false, thickness: 18 },
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
    if (value.indexOf('user:') === 0) {
      const name = value.slice(5);
      if (userPresets[name]) applyPreset(JSON.stringify(userPresets[name]));
    } else {
      loadFurniturePreset(value);
    }
  }

  // ── Furniture type preset loader ─────────────────────────────────────
  function loadFurniturePreset(type) {
    const preset = FURNITURE_PRESETS[type];
    if (!preset) return;
    state = deepClone(preset);
    delete state._info;
    currentEntityID = null;
    // 스택 모드: 모듈 폭을 카케이스 내부 폭으로 동기화
    // (지오메트리가 어차피 강제하므로 UI 표시도 실제 값과 일치시킴)
    if (!state.run_mode) {
      const iw = _carcaseInnerWidth(state.width);
      state.modules.forEach(m => { if (m.kind !== 'bed_gap') m.width = iw; });
    }
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

    setStatus('프리셋 로드: ' + (preset.name || type), 'ok');
  }

  // ── Field helpers ────────────────────────────────────────────────────
  function onField(key, value) {
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
        renderModuleList();
      }
      updateTotalHeight();
    } else if (key === 'max_depth') {
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
    const remaining = targetTotal - topT - base;
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
    updateTotalHeight();   // 상부 EP는 총 높이에 반영됨
  }

  // 상부 EP 두께 (총 높이 가산분)
  function _epTopT() {
    const ep = state.ep || {};
    return ep.top ? (ep.thickness || 18) : 0;
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

  // EP 포함 전체 폭 → 카케이스 내부 폭 계산
  function _carcaseInnerWidth(totalW) {
    const ep = state.ep || {};
    const t  = ep.thickness || 18;
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
    setStatus('생성 중…', '');
    sketchup['kabinet:generate'](JSON.stringify(state));
  }

  function regenerate() {
    if (!validateState()) return;
    setStatus('재생성 중…', '');
    const payload = JSON.stringify({ spec: state, entityID: currentEntityID });
    sketchup['kabinet:regenerate'](payload);
  }

  function loadSelection() {
    sketchup['kabinet:load_selection']('');
  }

  // Called from Ruby after load_selection
  function loadSpec(payload) {
    try {
      const { spec, entityID } = typeof payload === 'string' ? JSON.parse(payload) : payload;
      state = spec;
      currentEntityID = entityID || null;
      syncFormFromState();
      renderModuleList();
      updateTotalHeight();
      updateHeightSummary();
      setStatus('어셈블리 로드 완료.', 'ok');
    } catch (e) {
      setStatus('스펙 파싱 오류: ' + e.message, 'error');
    }
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
    setStatus('선택 모델 DXF 생성 중…', '');
    sketchup['kabinet:export_group_dxf']('');
  }

  // ── 스마트 반영: 불러온 어셈블리가 있으면 재생성, 없으면 신규 생성 ────
  function smartApply() {
    if (currentEntityID) regenerate();
    else generate();
  }

  // ── Presets ──────────────────────────────────────────────────────────
  function savePreset() {
    const name = document.getElementById('f-preset-name').value.trim();
    if (!name) { setStatus('프리셋 이름을 입력하세요.', 'error'); return; }
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
      state = JSON.parse(specJson);
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
              drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 18,
              door_material: mat, handle_type: 'none', handle_hole_mm: 128,
              material: mat, edge_banding_mm: 1.0 };
    } else if (kind === 'desk_module') {
      mod = { kind, width: w, depth: d || 700, height: 750,
              top_thickness: 25, leg_type: 'box',
              leg_w: 60, leg_d: 60, leg_inset_x: 30, leg_inset_y: 30,
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
              door_config: 'none', door_type: 'swing', door_thickness: 18,
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
  function onError(msg)   { setStatus('오류: ' + msg, 'error'); }

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

    const hasTop = !!state.top_panel;
    document.getElementById('f-top-use').checked = hasTop;
    document.getElementById('top-panel-fields').style.display = hasTop ? '' : 'none';
    if (hasTop) setVal('f-top-t', state.top_panel.thickness);

    document.getElementById('f-ep-left').checked  = !!(state.ep && state.ep.left);
    document.getElementById('f-ep-right').checked = !!(state.ep && state.ep.right);
    const epTopChk = document.getElementById('f-ep-top');
    if (epTopChk) epTopChk.checked = !!(state.ep && state.ep.top);
    setVal('f-ep-t', state.ep ? state.ep.thickness : 18);
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
  function renderPreview() {
    const cv = document.getElementById('preview-canvas');
    if (!cv || !cv.getContext) return;
    const ctx = cv.getContext('2d');
    const CW = cv.width, CH = cv.height;
    ctx.clearRect(0, 0, CW, CH);

    const ep   = state.ep || {};
    const epT  = ep.thickness || 18;
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
        const lw = m.leg_w || 60, ix = m.leg_inset_x || 30;
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
    // 저장 프리셋 → 통합 드롭다운 채우기 (SketchUp 콜백 가능할 때만)
    try { if (typeof sketchup !== 'undefined') sketchup['kabinet:list_presets'](''); } catch (e) {}
  });

  // ── Public API ───────────────────────────────────────────────────────
  return {
    switchTab, onField, onTopPanelToggle, onTopPanelField, onEP, onEpTopFlush,
    generate, regenerate, smartApply, loadSelection, loadSpec,
    exportDrawings, exportCutList, exportDXF, exportGroupDXF, loadSelectionForExport,
    savePreset, listPresets, loadPresets, applyPreset, deletePreset,
    addModule, removeModule, moveModule,
    loadFurniturePreset, onPresetChange,
    syncWidthToModules, distributeHeight,
    onTargetHeightLive,
    updateTotalHeight, updateHeightSummary, renderPreview,
    onRunMode,
    onSuccess, onError,
    getState
  };
})();
