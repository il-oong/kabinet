module Kabinet
  module Geometry
    # 손잡이 형태별 지오메트리 생성 모듈.
    #
    # 좌표계 약속 (패널 로컬 스페이스):
    #   패널은 (0,0,0) → (W, T, H) 박스.
    #   Y=0 : 패널 전면(관찰자 쪽)
    #   Y=T : 패널 배면(카케이스 쪽)
    #   핸들은 Y<0 방향으로 돌출 (관찰자 쪽으로).
    #
    # 지원 handle_type:
    #   'bar'        — 바 핸들 (직사각 봉)
    #   'knob'       — 원형 손잡이
    #   'cup_pull'   — 컵 풀 (오목 손잡이)
    #   'channel'    — 찬넬: 전판은 평판, 몸통 쪽 ㄴ자 포켓(Joinery.channel_rail)으로 처리 — 여기서는 아무것도 안 만든다
    #   'push_open'  — 푸시 오픈 (핸들 없음)
    #   'none'       — 없음
    #
    # 손잡이 위치 규칙 (근거: 송도마리나베이 E1/E2 DOOR 도면의 손잡이·푸시 표시점, 개폐 사선)
    #   도어   : 가로 위치는 항상 '열리는 쪽'(경첩 반대편). 양개는 가운데 맞닿는 쪽, 단문은 경첩 반대쪽.
    #            세로 위치 auto = 낮은 도어(< TALL_DOOR_MM, 하부장)는 상단, 키 큰 도어는 중앙.
    #   서랍   : 가로 중앙, 세로 auto = 상단.
    #   handle_pos: auto / top / bottom / center (세로) · left / right (도어 가로 강제)
    module HandleBuilder
      module_function

      STANDOFF_MM = 15   # 패널 면에서 핸들까지 공간 (mm)
      BAR_CROSS_MM = 11  # 바 핸들 봉 단면 크기 (mm)
      EDGE_MM = 35       # 위·아래 가장자리에서 핸들까지
      SIDE_MM = 50       # 열리는 쪽 가장자리에서 핸들까지
      TALL_DOOR_MM = 1000 # 이 높이 이상 도어는 손잡이를 중앙 높이에

      # 도어 한 장의 열리는 쪽: 'left' / 'right'. 여닫이가 아니면 nil.
      def open_edge(door_role, hinge_side = 'left')
        case door_role.to_s
        when 'door_pair_left'  then 'right'
        when 'door_pair_right' then 'left'
        when 'door_single'     then hinge_side.to_s == 'right' ? 'left' : 'right'
        end
      end

      # → [가로('left'/'right'/'center'), 세로('top'/'bottom'/'center')]
      def place(pos, panel_role, panel_h, edge)
        pos = pos.to_s
        v = %w[top bottom center].include?(pos) ? pos : nil
        if panel_role == :drawer
          ['center', v || 'top']
        else
          h = %w[left right].include?(pos) ? pos : (edge || 'right')
          [h, v || (panel_h < TALL_DOOR_MM.mm ? 'top' : 'center')]
        end
      end

      # ── 바 핸들 ────────────────────────────────────────────────────
      # 서랍: 가로 봉(중앙) · 도어: 세로 봉(열리는 쪽 가장자리)
      def bar(entities, panel_w, panel_t, panel_h,
               hole_mm: 128, panel_role: :door, pos: 'auto', edge: nil, rot: 'auto')
        h, v     = place(pos, panel_role, panel_h, edge)
        bar_c    = BAR_CROSS_MM.mm
        standoff = STANDOFF_MM.mm
        bar_len  = (hole_mm + 60).mm

        # 방향: auto = 서랍 가로 · 도어 세로. rot 'h'/'v' 로 뒤집을 수 있다.
        horizontal = rot.to_s == 'h' || (rot.to_s != 'v' && panel_role == :drawer)
        if horizontal
          len = [bar_len, panel_w - 20.mm].min
          bx  = case h
                when 'left'  then SIDE_MM.mm
                when 'right' then panel_w - SIDE_MM.mm - len
                else (panel_w - len) / 2.0
                end
          bx  = [[bx, 10.mm].max, panel_w - len - 10.mm].min
          bz  = case v
                when 'top'    then panel_h - EDGE_MM.mm - bar_c
                when 'bottom' then EDGE_MM.mm
                else (panel_h - bar_c) / 2.0
                end
          local = ::Geom::Transformation.new(::Geom::Point3d.new(bx, -standoff, bz))
          Kabinet::Geometry::Builder.box(entities, len, standoff, bar_c, local,
                                         role: 'handle_bar', label: '바핸들(가로)',
                                         material_name: 'handle')
        else
          len = [bar_len, panel_h - 20.mm].min
          bx  = case h
                when 'left'  then SIDE_MM.mm
                when 'right' then panel_w - SIDE_MM.mm - bar_c
                else (panel_w - bar_c) / 2.0
                end
          bz  = case v
                when 'top'    then panel_h - EDGE_MM.mm - len
                when 'bottom' then EDGE_MM.mm
                else (panel_h - len) / 2.0
                end
          bz = [bz, 10.mm].max
          local = ::Geom::Transformation.new(::Geom::Point3d.new(bx, -standoff, bz))
          Kabinet::Geometry::Builder.box(entities, bar_c, standoff, len, local,
                                         role: 'handle_bar', label: '바핸들(세로)',
                                         material_name: 'handle')
        end
      rescue StandardError => e
        puts "Kabinet HandleBuilder.bar 오류: #{e.class}: #{e.message}"
        puts e.backtrace.first(3).join("
")
        nil
      end

      # ── 원형 손잡이 (Knob) — 8면 원기둥 근사 ─────────────────────
      def knob(entities, panel_w, panel_t, panel_h, panel_role: :door, pos: 'auto', edge: nil)
        h, v     = place(pos, panel_role, panel_h, edge)
        diameter = 28.mm
        depth    = 18.mm   # 돌출 길이
        radius   = diameter / 2.0

        cx = case h
             when 'left'  then SIDE_MM.mm
             when 'right' then panel_w - SIDE_MM.mm
             else panel_w / 2.0
             end
        cz = case v
             when 'top'    then panel_h - EDGE_MM.mm
             when 'bottom' then EDGE_MM.mm
             else panel_h / 2.0
             end

        g = entities.add_group
        # 원기둥 중심을 패널 전면 기준으로 배치
        g.transformation = ::Geom::Transformation.new(
          ::Geom::Point3d.new(cx, -(depth), cz))
        Kabinet::Persistence::Attributes.set_role(g, 'handle_knob', label: '원형손잡이')

        segs = 8
        pts  = segs.times.map do |s|
          ang = s * 2.0 * Math::PI / segs
          ::Geom::Point3d.new(radius * Math.cos(ang), 0, radius * Math.sin(ang))
        end
        face = g.entities.add_face(pts)
        return unless face

        face.pushpull(face.normal.y > 0 ? depth : -depth, true)
      rescue StandardError => e
        puts "Kabinet HandleBuilder.knob 오류: #{e.class}: #{e.message}"
        nil
      end

      # ── 컵 풀 (Cup Pull) — 오목 손잡이 시각 표현 ─────────────────
      def cup_pull(entities, panel_w, panel_t, panel_h, panel_role: :door, pos: 'auto', edge: nil)
        h, v   = place(pos, panel_role, panel_h, edge)
        cup_w  = 48.mm
        cup_h  = 22.mm
        cup_d  = 7.mm

        cx = case h
             when 'left'  then 38.mm
             when 'right' then panel_w - 38.mm - cup_w
             else (panel_w - cup_w) / 2.0
             end
        cz = case v
             when 'top'    then panel_h - 38.mm - cup_h
             when 'bottom' then 38.mm
             else (panel_h - cup_h) / 2.0
             end

        local = ::Geom::Transformation.new(::Geom::Point3d.new(cx, -cup_d, cz))
        Kabinet::Geometry::Builder.box(entities, cup_w, cup_d, cup_h, local,
                                       role: 'handle_cup', label: '컵풀',
                                       material_name: 'handle')
      rescue StandardError => e
        puts "Kabinet HandleBuilder.cup_pull 오류: #{e.class}: #{e.message}"
        nil
      end

      # ── 공통 디스패치 ────────────────────────────────────────────
      # edge: 도어의 열리는 쪽('left'/'right') — open_edge 로 구한다.
      def build(entities, panel_w, panel_t, panel_h,
                handle_type, hole_mm: 128, panel_role: :door, pos: 'auto', edge: nil, rot: 'auto')
        case handle_type.to_s
        when 'bar'
          bar(entities, panel_w, panel_t, panel_h,
              hole_mm: hole_mm, panel_role: panel_role, pos: pos, edge: edge, rot: rot)
        when 'knob'
          knob(entities, panel_w, panel_t, panel_h, panel_role: panel_role, pos: pos, edge: edge)
        when 'cup_pull'
          cup_pull(entities, panel_w, panel_t, panel_h, panel_role: panel_role, pos: pos, edge: edge)
        # 'channel', 'push_open', 'none': 손잡이 지오메트리 없음
        end
      end
    end
  end
end
