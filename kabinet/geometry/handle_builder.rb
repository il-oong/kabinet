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
    #   'channel'    — 목찬넬 (패널 상단 홈, 패널 바디 자체를 바꿈)
    #   'knob'       — 원형 손잡이
    #   'cup_pull'   — 컵 풀 (오목 손잡이)
    #   'push_open'  — 푸시 오픈 (핸들 없음)
    #   'none'       — 없음
    module HandleBuilder
      module_function

      STANDOFF_MM = 15   # 패널 면에서 핸들까지 공간 (mm)
      BAR_CROSS_MM = 11  # 바 핸들 봉 단면 크기 (mm)

      # ── 바 핸들 ────────────────────────────────────────────────────
      # panel_role: :door   → 세로 봉, 패널 우측 가장자리 근처
      # panel_role: :drawer → 가로 봉, 패널 상단 중앙
      def bar(entities, panel_w, panel_t, panel_h,
               hole_mm: 128, panel_role: :door)
        bar_len  = (hole_mm + 60).mm
        bar_c    = BAR_CROSS_MM.mm
        standoff = STANDOFF_MM.mm

        if panel_role == :drawer
          # 가로 방향: 상단에서 35mm 아래, 수평 중앙
          bx = (panel_w - bar_len) / 2.0
          bz = panel_h - 35.mm - bar_c
          # 박스: W=bar_len, D=standoff, H=bar_c  (y: -standoff → 0)
          local = ::Geom::Transformation.new(::Geom::Point3d.new(bx, -standoff, bz))
          Kabinet::Geometry::Builder.box(entities, bar_len, standoff, bar_c, local,
                                         role: 'handle_bar', label: '바핸들(가로)',
                                         material_name: 'handle')
        else
          # 세로 방향: 우측 가장자리에서 50mm 안쪽, 높이 중앙
          bx = panel_w - 50.mm - bar_c
          bz = (panel_h - bar_len) / 2.0
          # 박스: W=bar_c, D=standoff, H=bar_len
          local = ::Geom::Transformation.new(::Geom::Point3d.new(bx, -standoff, bz))
          Kabinet::Geometry::Builder.box(entities, bar_c, standoff, bar_len, local,
                                         role: 'handle_bar', label: '바핸들(세로)',
                                         material_name: 'handle')
        end
      rescue StandardError => e
        puts "Kabinet HandleBuilder.bar 오류: #{e.class}: #{e.message}"
        puts e.backtrace.first(3).join("\n")
        nil
      end

      # ── 목찬넬 — 패널 전체를 홈 포함한 형태로 직접 생성 ──────────
      # Builder.box 대신 이 메서드로 패널 바디를 생성해야 함.
      # 성공 시 true, 실패 시 false 반환.
      #
      # 단면 프로파일 (YZ 평면, x=0에서 +X 방향으로 push-pull):
      #
      #   Z=H ─────────────────── 상단 열린 홈(groove)
      #        |  홈  | 뒷판  |
      #   Z=H-groove_h
      #        | 전면(두께 전체) |
      #   Z=0 ─────────────────── 하단
      #        Y=0           Y=T
      def channel_panel(entities, panel_w, panel_t, panel_h,
                         groove_h: 22.mm, groove_d: 15.mm)
        gd = [groove_d, panel_t * 0.85].min  # 두께의 85% 이하
        gh = [groove_h, panel_h * 0.15].min  # 높이의 15% 이하 (너무 크면 이상)

        pts = [
          ::Geom::Point3d.new(0, 0,        0),           # 전면-하단
          ::Geom::Point3d.new(0, 0,        panel_h - gh), # 전면-홈아래
          ::Geom::Point3d.new(0, gd,       panel_h - gh), # 홈바닥-배면쪽
          ::Geom::Point3d.new(0, gd,       panel_h),      # 홈상단-배면쪽
          ::Geom::Point3d.new(0, panel_t,  panel_h),      # 배면-상단
          ::Geom::Point3d.new(0, panel_t,  0),            # 배면-하단
        ]

        face = entities.add_face(pts)
        return false unless face

        dir = face.normal.x > 0 ? panel_w : -panel_w
        face.pushpull(dir, true)
        true
      rescue StandardError
        false
      end

      # ── 원형 손잡이 (Knob) — 8면 원기둥 근사 ─────────────────────
      def knob(entities, panel_w, panel_t, panel_h, panel_role: :door)
        diameter = 28.mm
        depth    = 18.mm   # 돌출 길이
        radius   = diameter / 2.0

        if panel_role == :drawer
          cx = panel_w / 2.0
          cz = panel_h - 35.mm  # 상단에서 35mm
        else
          cx = panel_w - 50.mm  # 우측에서 50mm
          cz = panel_h / 2.0
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
      def cup_pull(entities, panel_w, panel_t, panel_h, panel_role: :door)
        cup_w  = 48.mm
        cup_h  = 22.mm
        cup_d  = 7.mm

        cx = (panel_w - cup_w) / 2.0
        cz = panel_role == :drawer ? (panel_h - 38.mm - cup_h) : ((panel_h - cup_h) / 2.0)

        local = ::Geom::Transformation.new(::Geom::Point3d.new(cx, -cup_d, cz))
        Kabinet::Geometry::Builder.box(entities, cup_w, cup_d, cup_h, local,
                                       role: 'handle_cup', label: '컵풀',
                                       material_name: 'handle')
      rescue StandardError => e
        puts "Kabinet HandleBuilder.cup_pull 오류: #{e.class}: #{e.message}"
        nil
      end

      # ── 공통 디스패치 ────────────────────────────────────────────
      # 'channel'은 panel 바디 자체를 수정하므로 place_door/drawer_front에서 별도 처리.
      def build(entities, panel_w, panel_t, panel_h,
                handle_type, hole_mm: 128, panel_role: :door)
        case handle_type.to_s
        when 'bar'
          bar(entities, panel_w, panel_t, panel_h,
              hole_mm: hole_mm, panel_role: panel_role)
        when 'knob'
          knob(entities, panel_w, panel_t, panel_h, panel_role: panel_role)
        when 'cup_pull'
          cup_pull(entities, panel_w, panel_t, panel_h, panel_role: panel_role)
        # 'channel', 'push_open', 'none': 별도 처리 또는 핸들 없음
        end
      end
    end
  end
end
