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
        shelves: [
          { height_from_bottom: 280, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 560, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 840, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 1120, thickness: 18, depth_inset: 0 },
          { height_from_bottom: 1450, thickness: 18, depth_inset: 0 }
        ],
        accessories: []
      }
    ],
    _info: '오픈 책장 W900×D300×H1800 | 선반 5개 (32mm 가변 가능)'
  },

  tv_unit: {
    name: 'TV장',
    furniture_type: 'tv_unit',
    width: 1800, max_depth: 450, base_height: 80,
    material: 'LPM',
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 25 },
    // 총 높이: 80 + 200 + 495 + 25 = 800mm (입식 표준 TV장)
    modules: [
      { kind: 'drawer_module', width: 1800, depth: 450, height: 200,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 3, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 1800, depth: 450, height: 495,
        body_thickness: 18, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 18,
        door_material: 'LPM', handle_type: 'channel', material: 'LPM',
        edge_banding_mm: 1.0,
        shelves: [{ height_from_bottom: 220, thickness: 18, depth_inset: 0 }],
        accessories: []
      }
    ],
    _info: 'TV장 W1800×D450×H800 | 받침80+서랍200+수납495+상판25. 입식형'
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
      { kind: 'shelf_module', width: 1200, depth: 400, height: 1032,
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
    _info: '수납장 W1200×D400×H1050 | 양개문·선반3개. 거실/서재 범용 수납'
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
        shelves: [
          { height_from_bottom: 500, thickness: 18, depth_inset: 20 }
        ],
        accessories: [
          { kind: 'hanging_rod', height_from_bottom: 1000, depth_inset: 75, diameter: 32 },
          { kind: 'hanging_rod', height_from_bottom: 500,  depth_inset: 75, diameter: 32 }
        ]
      }
    ],
    _info: '슬라이딩 붙박이장 W1600×D600×H2100 | 미닫이 2짝·상하 행거. 드레스룸'
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
      { kind: 'bed_gap', width: 1600, label: '침대 공간 (퀸 1600mm)' },
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
      { kind: 'bed_gap', width: 1600, label: '침대 공간 (퀸 1600mm)' },
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
        shelves: [
          { height_from_bottom: 220, thickness: 18, depth_inset: 20 }
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
        shelves: [
          { height_from_bottom: 260, thickness: 18, depth_inset: 20 }
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
        shelves: [
          { height_from_bottom: 200, thickness: 15, depth_inset: 20 }
        ],
        accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
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
        shelves: [
          { height_from_bottom: 200, thickness: 15, depth_inset: 20 }
        ],
        accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
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
    // 총 높이: 750(책상) + 400(상부장) = 1150mm
    // 보고서 기준: 책상고 750mm, 상부장 D280 H400mm
    modules: [
      { kind: 'desk_module', width: 1200, depth: 600, height: 750,
        top_thickness: 25, leg_type: 'box',
        leg_w: 60, leg_d: 60, leg_inset_x: 30, leg_inset_y: 30,
        has_modesty_panel: false, pedestal: null, under_unit: null,
        material: 'LPM', edge_banding_mm: 1.0
      },
      { kind: 'shelf_module', width: 1200, depth: 280, height: 400,
        body_thickness: 15, back_thickness: 9, has_back: true,
        door_config: 'pair', door_type: 'swing', door_thickness: 15,
        door_material: 'LPM', handle_type: 'knob', handle_hole_mm: 128,
        door_mount: 'overlay', material: 'LPM', edge_banding_mm: 1.0,
        shelves: [
          { height_from_bottom: 200, thickness: 15, depth_inset: 20 }
        ],
        accessories: [],
        vertical_dividers: [], cell_shelves: [], cell_drawers: []
      }
    ],
    _info: '자녀방 책상+상부장 W1200 | 책상750mm + 도어상부장400mm. 총 H1150mm. 초등~중학생 권장'
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
      { kind: 'bed_gap', width: 1000, label: '싱글 침대 공간 (1000mm)' },
      { kind: 'drawer_module', width: 500, depth: 580, height: 2020,
        body_thickness: 18, back_thickness: 9, has_back: true,
        drawer_count: 4, drawer_type: 'undermount', drawer_thickness: 18,
        door_material: 'LPM', handle_type: 'bar', handle_hole_mm: 128,
        material: 'LPM', edge_banding_mm: 1.0
      }
    ],
    _info: '자녀방 싱글침대장 W2000 (수납500 + 싱글1000 + 서랍4단500) | 전고 H2100mm'
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
    has_kickboard: true,
    material: 'LPM',
    edge_banding_mm: 1.0,
    run_mode: false,
    run_height: 740,
    ep: { left: true, right: true, thickness: 18 },
    top_panel: { thickness: 20 },
    modules: []
  };

  let state = deepClone(DEFAULT_STATE);
  let currentEntityID = null;

  // ── Tab management ───────────────────────────────────────────────────
  function switchTab(name, btn) {
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.tab-bar button').forEach(b => b.classList.remove('active'));
    document.getElementById('tab-' + name).classList.add('active');
    if (btn) btn.classList.add('active');
    if (name === 'modules')  { renderModuleList(); updateHeightSummary(); }
    if (name === 'presets')  listPresets();
    if (name === 'assembly') updateTotalHeight();
    // 도면 출력 탭 진입 시 현재 선택된 어셈블리를 자동으로 읽어 EntityID 채우기
    if (name === 'drawings') sketchup['kabinet:load_selection']('');
  }

  // ── Furniture type preset loader ─────────────────────────────────────
  function loadFurniturePreset(type) {
    const preset = FURNITURE_PRESETS[type];
    if (!preset) return;
    state = deepClone(preset);
    delete state._info;
    currentEntityID = null;
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
    if (wLabel) wLabel.textContent = checked ? '총 런 폭 (섹션 합계)' : '가구 전체 폭';
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
    const remaining = target - topT - base;
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
      // Height = base + run_height + top panel
      const runH  = state.run_height || 740;
      const total = base + runH + topT;
      const el    = document.getElementById('total-height-display');
      if (el) el.textContent = total;

      // Also show total run width from section widths
      const totalW = state.modules.reduce((s, m) => s + (m.width || 0), 0);
      const twEl   = document.getElementById('total-run-width-display');
      if (twEl) twEl.textContent = totalW;
    } else {
      const modsH = state.modules.reduce((s, m) => s + (m.height || 0), 0);
      const total = base + modsH + topT;
      const el    = document.getElementById('total-height-display');
      if (el) el.textContent = total;

      // Sync target-height input with current total if user hasn't edited it
      const tgt = document.getElementById('f-target-height');
      if (tgt && !tgt._userEdited) tgt.value = total;
    }
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
    const checks = document.querySelectorAll('#tab-drawings .view-check input:checked');
    const views  = Array.from(checks).map(c => c.value);
    if (views.length === 0) { setStatus('뷰를 하나 이상 선택하세요.', 'error'); return; }
    // entityID 없으면 Ruby 쪽에서 현재 선택으로 폴백하도록 null 전송
    const payload = JSON.stringify({ views, entityID: currentEntityID || null });
    sketchup['kabinet:export_drawings'](payload);
    setStatus('도면 출력 요청 중…', '');
  }

  function exportCutList() {
    if (!validateState()) return;
    setStatus('커트리스트 생성 중…', '');
    sketchup['kabinet:export_cutlist'](JSON.stringify(state));
  }

  // ── Presets ──────────────────────────────────────────────────────────
  function savePreset() {
    const name = document.getElementById('f-preset-name').value.trim();
    if (!name) { setStatus('프리셋 이름을 입력하세요.', 'error'); return; }
    sketchup['kabinet:save_preset'](JSON.stringify({ name, spec: state }));
  }

  function listPresets() {
    sketchup['kabinet:list_presets']('');
  }

  function loadPresets(presets) {
    const el   = document.getElementById('preset-list');
    const keys = Object.keys(presets || {});
    if (keys.length === 0) {
      el.innerHTML = '<span style="color:var(--text-dim);font-size:12px">저장된 프리셋이 없습니다.</span>';
      return;
    }
    el.innerHTML = keys.map(name => `
      <div class="preset-item">
        <span class="preset-name">${esc(name)}</span>
        <button onclick="kabinet.applyPreset(${JSON.stringify(JSON.stringify(presets[name]))})">불러오기</button>
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
    const w   = state.width;
    const mat = state.material || 'LPM';
    let mod;
    if (kind === 'drawer_module') {
      mod = { kind, width: w, depth: state.max_depth, height: 200,
              body_thickness: 18, back_thickness: 9, has_back: true,
              drawer_count: 2, drawer_type: 'undermount', drawer_thickness: 18,
              door_material: mat, handle_type: 'none', handle_hole_mm: 128,
              material: mat, edge_banding_mm: 1.0 };
    } else if (kind === 'desk_module') {
      mod = { kind, width: w, depth: state.max_depth || 700, height: 750,
              top_thickness: 25, leg_type: 'box',
              leg_w: 60, leg_d: 60, leg_inset_x: 30, leg_inset_y: 30,
              has_modesty_panel: false, pedestal: null, under_unit: null,
              material: mat, edge_banding_mm: 1.0 };
    } else if (kind === 'bed_gap') {
      mod = { kind, width: 1600, label: '침대 공간' };
    } else {
      mod = { kind, width: w, depth: state.max_depth, height: 400,
              body_thickness: 18, back_thickness: 9, has_back: true,
              door_config: 'none', door_type: 'swing', door_thickness: 18,
              door_material: mat, handle_type: 'none', handle_hole_mm: 128,
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
      const totalH = base + runH + topT;
      if (base > 0)  parts.push('받침 ' + base);
      state.modules.forEach((m, i) => {
        const tag = m.kind === 'drawer_module' ? '서랍'
                  : m.kind === 'bed_gap'       ? '침대'
                  : m.kind === 'desk_module'   ? '책상' : '선반';
        parts.push('S' + (i+1) + '(' + tag + ') W' + m.width);
      });
      if (topT > 0) parts.push('상판 ' + topT);
      el.innerHTML =
        '<span class="hs-label">런 높이 ' + totalH + 'mm / 섹션 총 폭 ' + totalW + 'mm</span>' +
        '<span class="hs-parts">' + parts.join(' + ') + '</span>';
    } else {
      const modsH = state.modules.reduce((s, m) => s + (m.height || 0), 0);
      const total = base + modsH + topT;
      if (base > 0) parts.push('받침 ' + base);
      state.modules.forEach((m, i) => {
        const tag = m.kind === 'drawer_module' ? '서랍' : '선반';
        parts.push('M' + (i+1) + '(' + tag + ') ' + m.height);
      });
      if (topT > 0) parts.push('상판 ' + topT);
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
    setVal('f-ep-t', state.ep ? state.ep.thickness : 18);

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
  });

  // ── Public API ───────────────────────────────────────────────────────
  return {
    switchTab, onField, onTopPanelToggle, onTopPanelField, onEP,
    generate, regenerate, loadSelection, loadSpec,
    exportDrawings, exportCutList, loadSelectionForExport,
    savePreset, listPresets, loadPresets, applyPreset, deletePreset,
    addModule, removeModule, moveModule,
    loadFurniturePreset,
    syncWidthToModules, distributeHeight,
    onTargetHeightLive,
    updateTotalHeight, updateHeightSummary,
    onRunMode,
    onSuccess, onError,
    getState
  };
})();
