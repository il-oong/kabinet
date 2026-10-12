module Kabinet
  module Core
    # Door(s) mounted in front of a carcase opening.
    #
    # door_type: 'swing'    여닫이 — 오버레이 힌지, 전후 동일 레벨
    #            'sliding'  미닫이 — 전후 2개 레일, 도어가 교대로 깊이 다름
    #            'folding'  접이식 — 바이폴드: 각 도어를 반폭 2장으로 분리
    #            'lift_up'  리프트업 — 단일 패널 상개형, 좁은 클리어런스
    #            'none'     도어 없음
    #
    # mount_style: 'overlay'  오버레이 — 도어가 카케이스 전면 패널을 덮음 (기본)
    #              'inset'    인셋 — 도어가 카케이스 내부에 들어가 전면과 면일치
    #
    # handle_type: 'none' | 'bar' | 'channel' | 'knob' | 'cup_pull' | 'push_open'
    #
    # 그룹 구조:
    #   parent_entities
    #   └── doors_grp          ← DoorPanel.build 이 생성 (몸통과 분리)
    #       ├── panel_grp      ← 도어 패널마다 (개별 선택 가능)
    #       │   ├── 패널 바디 box (또는 channel 프로파일)
    #       │   └── 손잡이 geometry
    #       └── ...
    #
    # 오버레이 좌표계:
    #   opening_width/height = 모듈 전체 폭/높이
    #   x_origin = 0, z_origin = 0 (모듈 외각 기준)
    #   Y<0: 도어가 카케이스 앞으로 돌출
    #
    # 인셋 좌표계:
    #   opening_width/height = 카케이스 내부 개구 폭/높이
    #   x_origin = body_thickness, z_origin = body_thickness (내부 기준)
    #   Y>0: 도어가 카케이스 내부에 위치 (inset_depth mm 만큼)
    class DoorPanel
      attr_reader :opening_width, :opening_height, :thickness, :config, :door_type,
                  :gap_top, :gap_bottom, :gap_outside, :reveal_between, :front_offset,
                  :handle_type, :handle_hole_mm, :handle_pos, :handle_rot, :hinge_side, :mount_style,
                  :x_origin, :z_origin, :inset_depth

      def initialize(opening_width:, opening_height:, thickness:,
                     config: 'pair', door_type: 'swing',
                     gap_top:        Kabinet::Core::Gaps.top.mm,
                     gap_bottom:     Kabinet::Core::Gaps.bottom.mm,
                     gap_outside:    Kabinet::Core::Gaps.outside.mm,
                     reveal_between: Kabinet::Core::Gaps.between.mm,
                     front_offset:   Kabinet::Core::Gaps.front_offset.mm,
                     handle_type:    'none',
                     handle_hole_mm: 128,
                     handle_pos:     'auto',
                     handle_rot:     'auto',
                     hinge_side:     'left',
                     mount_style:    'overlay',
                     x_origin:       0.mm,
                     z_origin:       0.mm,
                     inset_depth:    Kabinet::Constants::INSET_DOOR_DEPTH_MM.mm)
        @opening_width  = opening_width
        @opening_height = opening_height
        @thickness      = thickness
        @config         = config.to_s
        @door_type      = door_type.to_s
        @gap_top        = gap_top
        @gap_bottom     = gap_bottom
        @gap_outside    = gap_outside
        @reveal_between = reveal_between
        @front_offset   = front_offset
        @handle_type    = handle_type.to_s
        @handle_hole_mm = handle_hole_mm.to_i
        @handle_pos     = handle_pos.to_s
        @handle_rot     = handle_rot.to_s
        @hinge_side     = hinge_side.to_s   # 단문 경첩 쪽 (양개는 role 로 자동)
        @mount_style    = mount_style.to_s
        @x_origin       = x_origin
        @z_origin       = z_origin
        @inset_depth    = inset_depth
      end

      # 도어 높이 = 개구 높이 − 상하 갭
      def door_height
        @opening_height - @gap_top - @gap_bottom
      end

      # Y 기준 위치 계산
      #   overlay → 도어가 카케이스 앞으로 돌출 (음수)
      #   inset   → 도어가 카케이스 내부 (inset_depth, 양수)
      def y0_for_style
        @mount_style == 'inset' ? @inset_depth : -(@thickness + @front_offset)
      end

      # 카케이스 로컬 좌표계(원점 = 카케이스 전면-좌-하단)에서 도어를 배치.
      # 몸통과 분리를 위해 doors_grp 서브그룹을 생성.
      def build(parent_entities, carcase_origin_transform)
        return if @config == 'none' || @door_type == 'none'

        # ── 도어 그룹 (몸통과 별도 — SketchUp에서 독립 선택 가능)
        doors_grp = parent_entities.add_group
        doors_grp.transformation = carcase_origin_transform
        Kabinet::Persistence::Attributes.set_role(doors_grp, 'doors_group',
          label: @mount_style == 'inset' ? '도어 그룹 (인셋)' : '도어 그룹 (오버레이)')

        case @door_type
        when 'sliding' then build_sliding(doors_grp.entities, Kabinet::Geometry::Transforms::IDENTITY)
        when 'folding' then build_folding(doors_grp.entities, Kabinet::Geometry::Transforms::IDENTITY)
        when 'lift_up' then build_lift_up(doors_grp.entities, Kabinet::Geometry::Transforms::IDENTITY)
        else                build_swing(doors_grp.entities, Kabinet::Geometry::Transforms::IDENTITY)
        end
      end

      private

      # ── 여닫이 (Swing) — Fitting 공식 (커트리스트와 동일) ────────────────
      def build_swing(entities, tx)
        y0 = y0_for_style
        doors =
          if @mount_style == 'inset'
            Kabinet::Core::Fitting.inset_doors(
              @opening_width, @opening_height, @config,
              gap: @gap_outside, center_gap: @reveal_between)
          else
            Kabinet::Core::Fitting.swing_doors(
              @opening_width, @opening_height, @config,
              side_gap: @gap_outside, top_gap: @gap_top,
              bottom_gap: @gap_bottom, center_gap: @reveal_between)
          end
        doors.each do |d|
          place_door(entities, tx,
                     x: @x_origin + d[:x], y: y0, z: @z_origin + d[:z],
                     w: d[:w], h: d[:h], role: d[:role])
        end
      end

      # ── 미닫이 (Sliding) — Fitting 공식 ─────────────────────────────────
      def build_sliding(entities, tx)
        track_spacing = Kabinet::Constants::SLIDING_DOOR_TRACK_SPACING_MM.mm

        doors = Kabinet::Core::Fitting.sliding_doors(
          @opening_width, @opening_height, @config,
          overlap:    Kabinet::Constants::SLIDING_DOOR_OVERLAP_MM.mm,
          top_gap:    Kabinet::Constants::SLIDING_DOOR_TOP_GAP_MM.mm,
          bottom_gap: Kabinet::Constants::SLIDING_DOOR_BOTTOM_GAP_MM.mm)

        doors.each do |d|
          y = if @mount_style == 'inset'
                @inset_depth + d[:lane] * track_spacing
              else
                -(@thickness + @front_offset) - d[:lane] * track_spacing
              end
          place_door(entities, tx,
                     x: @x_origin + d[:x], y: y, z: @z_origin + d[:z],
                     w: d[:w], h: d[:h], role: d[:role])
        end
      end

      # ── 접이식 (Folding / Bi-fold) — Fitting 공식 ───────────────────────
      def build_folding(entities, tx)
        y0 = y0_for_style
        doors = Kabinet::Core::Fitting.folding_doors(
          @opening_width, @opening_height, @config,
          side_gap: @gap_outside, top_gap: @gap_top,
          bottom_gap: @gap_bottom, center_gap: @reveal_between)
        doors.each do |d|
          place_door(entities, tx,
                     x: @x_origin + d[:x], y: y0, z: @z_origin + d[:z],
                     w: d[:w], h: d[:h], role: d[:role])
        end
      end

      # ── 리프트업 (Lift-Up / 상개형) — Fitting 공식 ──────────────────────
      def build_lift_up(entities, tx)
        gap = Kabinet::Constants::LIFT_UP_DOOR_GAP_MM.mm
        y0  = y0_for_style
        Kabinet::Core::Fitting.lift_up_door(@opening_width, @opening_height, gap: gap).each do |d|
          place_door(entities, tx,
                     x: @x_origin + d[:x], y: y0, z: @z_origin + d[:z],
                     w: d[:w], h: d[:h], role: d[:role])
        end
      end

      # ── 공통 배치 헬퍼 ───────────────────────────────────────────────────
      # 각 도어 패널마다 서브그룹을 생성하고 손잡이 geometry를 추가.
      #
      # 패널 로컬 좌표 약속:
      #   (0,0,0) → (w, thickness, h)
      #   overlay: Y=0 = 패널 전면(관찰자 쪽), 손잡이는 Y<0
      #   inset  : Y=0 = 카케이스 전면, 패널은 Y=inset_depth 시작, 손잡이는 더 앞
      def place_door(parent_entities, parent_transform, x:, y:, z:, w:, h:, role:)
        local_tx  = parent_transform * ::Geom::Transformation.new(::Geom::Point3d.new(x, y, z))

        panel_grp = parent_entities.add_group
        panel_grp.transformation = local_tx
        Kabinet::Persistence::Attributes.set_role(panel_grp, role, label: role)

        # 패널 바디 — 찬넬도 전판은 평판 (포켓은 몸통 쪽, Joinery.channel_rail)
        Kabinet::Geometry::Builder.box(
          panel_grp.entities, w, @thickness, h,
          Kabinet::Geometry::Transforms::IDENTITY,
          role: role, label: role, material_name: 'door')

        # 손잡이: 열리는 쪽(경첩 반대편) 가장자리에 둔다
        Kabinet::Geometry::HandleBuilder.build(
          panel_grp.entities, w, @thickness, h,
          @handle_type, hole_mm: @handle_hole_mm, panel_role: :door, pos: @handle_pos, rot: @handle_rot,
          edge: Kabinet::Geometry::HandleBuilder.open_edge(role, @hinge_side))
      rescue StandardError => e
        # 도어 1장 실패가 전체 생성을 막지 않도록 하되, 원인은 콘솔에 남긴다.
        puts "Kabinet DoorPanel.place_door 오류(#{role}): #{e.class}: #{e.message}"
        nil
      end
    end
  end
end
