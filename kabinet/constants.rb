module Kabinet
  module Constants
    # ── 몸통판 두께 (mm) ──────────────────────────────────────────────────
    # 국내 맞춤가구 표준: PB/MDF 18T 기본, 상부장·소형은 15T 허용
    DEFAULT_BODY_THICKNESS_MM    = 18   # 표준 몸통판 (PB/MDF)
    BODY_THICKNESS_HEAVY_MM      = 25   # 대형/중량 가구용
    BODY_THICKNESS_LIGHT_MM      = 15   # 소형/주방상부장용

    DEFAULT_BACK_THICKNESS_MM    = 9    # 뒷판 (합판/MDF)
    BACK_THICKNESS_HEAVY_MM      = 12   # 하중 큰 경우
    BACK_RECESS_MM               = 10   # 뒷판 앞면으로부터 후퇴(mm)

    DEFAULT_DOOR_THICKNESS_MM    = 18   # 도어판 (도포 후 약 18mm)
    DOOR_THICKNESS_SLIM_MM       = 15   # 슬림 도어
    DOOR_THICKNESS_HEAVY_MM      = 22   # 마감재 두꺼운 도어 (HPL 등)

    DEFAULT_EP_THICKNESS_MM      = 18   # EP 측면 마감판
    DEFAULT_TOP_PANEL_MM         = 20   # 상판
    DEFAULT_SHELF_THICKNESS_MM   = 18   # 고정/가동 선반
    SHELF_THICKNESS_HEAVY_MM     = 25   # 스팬 >600mm 처짐 방지

    DRAWER_BOX_WALL_MM           = 15   # 서랍통 옆판/뒷판
    DRAWER_BOX_BOTTOM_MM         = 12   # 서랍통 바닥

    # ── 도어 갭 기준 (mm) ────────────────────────────────────────────────
    # 여닫이 기준: 상하 2mm, 좌우 2mm, 양개 중앙 3mm
    DOOR_GAP_TOP_MM              = 2
    DOOR_GAP_BOTTOM_MM           = 2
    DOOR_GAP_OUTSIDE_MM          = 2
    DOOR_REVEAL_BETWEEN_MM       = 3    # 양개문 중앙 갭
    DOOR_FRONT_OFFSET_MM         = 2    # 도어 앞면 돌출

    # 도어 오버레이 (overlay): 측판 덮는 양 — Blum 기준 9~10mm
    DOOR_OVERLAY_MM              = 9

    # ── 힌지 규격 (Blum 기준) ────────────────────────────────────────────
    HINGE_CUP_DIAMETER_MM        = 35   # 컵 직경 35mm
    HINGE_CUP_DEPTH_MM           = 13   # 컵 깊이
    HINGE_CUP_FROM_EDGE_MM       = 22   # 컵 중심~도어 가장자리
    HINGE_FROM_END_MM            = 100  # 최상/하단 힌지~도어 단부 (100~120mm)

    # 도어 높이별 힌지 수 기준표 [[최대높이mm, 힌지수], ...]
    HINGE_COUNT_THRESHOLDS = [
      [600,            2],
      [1200,           3],
      [1800,           4],
      [Float::INFINITY, 5]
    ].freeze

    # 힌지 수 계산 편의 함수
    def self.hinge_count_for_height(door_h_mm)
      HINGE_COUNT_THRESHOLDS.each { |max_h, n| return n if door_h_mm <= max_h }
      5
    end

    # ── 손잡이 홀 간격 (mm) ─────────────────────────────────────────────
    HANDLE_HOLE_SPACINGS_MM = [96, 128, 160, 192, 256, 320].freeze
    DEFAULT_HANDLE_HOLE_MM  = 128   # 표준 128mm 홀

    # ── 서랍 슬라이드 기준 ───────────────────────────────────────────────
    # 언더마운트(Blum Tandem 등): 서랍통 외폭 = 개구폭 − 약 10mm (편측 5mm)
    # 사이드마운트(볼레일 12.7mm): 서랍통 외폭 = 개구폭 − 약 26mm (편측 13mm)
    UNDERMOUNT_SIDE_CLEARANCE_MM = 5    # 언더마운트 편측 클리어런스
    UNDERMOUNT_HEIGHT_OFFSET_MM  = 15   # 언더레일 위 서랍통 바닥 높이
    SIDEMOUNT_SIDE_CLEARANCE_MM  = 13   # 사이드마운트 편측 (12.7mm 볼레일)
    SIDEMOUNT_HEIGHT_OFFSET_MM   = 25   # 사이드마운트 하단
    DRAWER_BOX_TOP_CLEAR_MM      = 20   # 서랍통 상단 여유 (인출 간섭 방지)

    DRAWER_FRONT_GAP_MM          = 2    # 전판 상하/좌우 갭
    DRAWER_REVEAL_BETWEEN_MM     = 3    # 전판 사이 갭

    # ── 가동선반 / 뒷판 시공 여유 ───────────────────────────────────────
    SHELF_SIDE_PLAY_MM           = 2    # 가동선반 좌우 총 여유 (끼임 방지, 편측 1mm)

    # ── 실무 한계/검증 기준 ─────────────────────────────────────────────
    SHEET_LENGTH_MM              = 2440 # 원장 길이 (PB/MDF 표준)
    SHEET_WIDTH_MM               = 1220 # 원장 폭
    SWING_DOOR_MAX_W_MM          = 600  # 여닫이 도어 권장 최대 폭
    SWING_DOOR_MAX_H_MM          = 2400 # 여닫이 도어 권장 최대 높이
    SHELF_SPAN_WARN_MM           = 800  # 18T 선반 처짐 경고 스팬

    # ── 32mm 시스템 (선반 핀 구멍) ──────────────────────────────────────
    SHELF_SYSTEM_PITCH_MM        = 32   # 구멍 피치 32mm
    SHELF_SYSTEM_START_MM        = 64   # 첫 구멍 위치 (바닥에서 64mm)
    SHELF_PIN_DIAMETER_MM        = 5    # 핀 구멍 직경 5mm

    # ── 옷걸이봉 ────────────────────────────────────────────────────────
    HANGING_ROD_DIAMETER_MM      = 32   # Ø32 기준
    HANGING_ROD_INSET_MM         = 75   # 뒷판에서 봉 중심까지
    HANGER_UPPER_CLOTHES_MM      = 1000 # 상의 행거 내부 높이 (재킷/셔츠)
    HANGER_LOWER_CLOTHES_MM      = 500  # 바지 반접기 행거 높이
    HANGER_LONG_CLOTHES_MM       = 1600 # 원피스/코트 행거 높이

    # ── 엣지 마감재 두께 (mm) ───────────────────────────────────────────
    EDGE_THICKNESS_THIN_MM       = 0.5  # 얇은 PVC 엣지
    EDGE_THICKNESS_STD_MM        = 1.0  # 표준 PVC/ABS 엣지
    EDGE_THICKNESS_THICK_MM      = 2.0  # 두꺼운 ABS/PUR/레이저 엣지
    DEFAULT_EDGE_THICKNESS_MM    = 1.0

    # ── 가구 유형별 표준 치수 참고표 ────────────────────────────────────
    # UI에서 프리셋 선택 시 참조용 (JS의 FURNITURE_PRESETS와 대응)
    FURNITURE_TYPE_LABELS = {
      'wardrobe'      => '붙박이장/옷장',
      'kitchen_base'  => '주방 하부장',
      'kitchen_upper' => '주방 상부장',
      'vanity'        => '화장대',
      'shoe_cabinet'  => '신발장',
      'bookshelf'     => '책장',
      'tv_unit'       => 'TV장',
      'custom'        => '직접 입력'
    }.freeze

    # ── 미닫이(슬라이딩) 도어 레일 규격 ────────────────────────────────────
    # 한국 붙박이장 표준 현수식(상부 행잉) 슬라이딩 도어
    SLIDING_DOOR_TRACK_SPACING_MM = 65   # 전후 레일 간격 (전면~후면 레일 깊이 차)
    SLIDING_DOOR_OVERLAP_MM       = 60   # 인접 도어 겹침 너비 (중앙 교차부)
    SLIDING_DOOR_TOP_GAP_MM       = 15   # 상부 레일 클리어런스 (행잉 롤러 공간)
    SLIDING_DOOR_BOTTOM_GAP_MM    = 5    # 하부 가이드 핀 클리어런스

    # ── 리프트업 도어 ────────────────────────────────────────────────────
    LIFT_UP_DOOR_GAP_MM           = 3    # 리프트업 도어 주변 클리어런스

    # ── 인셋 도어 (Inset Door) ───────────────────────────────────────────
    INSET_DOOR_GAP_MM             = 2    # 인셋 도어 주변 갭 (사방)
    INSET_DOOR_DEPTH_MM           = 0    # 인셋 깊이 (0 = 카케이스 전면과 면일치)

    # ── 걸레받이 (Toe Kick) ──────────────────────────────────────────────
    TOE_KICK_SETBACK_MM      = 50   # 도어 전면에서 걸레받이 판 전면까지 후퇴량
    TOE_KICK_BOARD_THICK_MM  = 18   # 걸레받이 판재 두께

    # ── AttributeDictionary 키 ───────────────────────────────────────────
    DIMENSION_TAG_NAME           = 'Kabinet_Dimensions'.freeze
    ATTR_DICT                    = 'kabinet'.freeze
    ATTR_DICT_ASSEMBLY           = 'kabinet_assembly'.freeze
  end
end
