module Kabinet
  module Core
    # Carcase + N stacked drawers (front + 5-sided box).
    # All inputs in SU Length.
    #
    # handle_type: 'none' | 'bar' | 'knob' | 'cup_pull' | 'channel' | 'push_open'
    #   각 서랍 전판에 손잡이 geometry 추가.
    #   'bar' 선택 시 handle_hole_mm(홀간거리)로 봉 길이 결정.
    #
    # 그룹 구조:
    #   module_group
    #   ├── body_grp     ← 카케이스 패널 (독립 선택 가능)
    #   └── drawers_grp  ← 서랍 전판 + 박스 (독립 선택 가능)
    #       ├── front_grp_0  (전판 + 손잡이)
    #       ├── drawer_box_0
    #       └── ...
    class DrawerModule
      attr_reader :width, :depth, :height, :body_thickness, :back_thickness,
                  :drawer_count, :drawer_type, :drawer_thickness,
                  :handle_type, :handle_hole_mm, :has_back

      def initialize(width:, depth:, height:,
                     body_thickness:  Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness:  Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     drawer_count:    1,
                     drawer_type:     'undermount',
                     drawer_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.mm,
                     handle_type:     'none',
                     handle_hole_mm:  128,
                     has_back:        true)
        @width            = width
        @depth            = depth
        @height           = height
        @body_thickness   = body_thickness
        @back_thickness   = back_thickness
        @drawer_count     = drawer_count
        @drawer_type      = drawer_type.to_s
        @drawer_thickness = drawer_thickness
        @handle_type      = handle_type.to_s
        @handle_hole_mm   = handle_hole_mm.to_i
        @has_back         = has_back ? true : false
      end

      def carcase
        @carcase ||= Carcase.new(width: @width, depth: @depth, height: @height,
                                 body_thickness: @body_thickness, back_thickness: @back_thickness,
                                 has_back: @has_back)
      end

      def opening_width
        @width - 2 * @body_thickness
      end

      def opening_height
        @height - 2 * @body_thickness
      end

      def build(parent_entities, parent_transform, role: 'drawer_module', suppress_bottom: false)
        group = parent_entities.add_group
        group.transformation = parent_transform
        Kabinet::Persistence::Attributes.set_role(group, role,
                                                  width: @width.to_f, depth: @depth.to_f, height: @height.to_f,
                                                  drawer_count: @drawer_count, drawer_type: @drawer_type)

        # ── 몸통 그룹 (카케이스 패널 — 몸통과 서랍을 분리)
        body_grp = group.entities.add_group
        Kabinet::Persistence::Attributes.set_role(body_grp, 'body_group', label: '몸통')

        c = Carcase.new(width: @width, depth: @depth, height: @height,
                        body_thickness: @body_thickness, back_thickness: @back_thickness,
                        has_back: @has_back, suppress_bottom: suppress_bottom)
        c.build(body_grp.entities, Kabinet::Geometry::Transforms::IDENTITY, wrap_group: false)

        # ── 서랍 그룹 (전판 + 박스)
        drawers_grp = group.entities.add_group
        Kabinet::Persistence::Attributes.set_role(drawers_grp, 'drawers_group', label: '서랍')

        reveal       = Kabinet::Constants::DRAWER_REVEAL_BETWEEN_MM.mm
        front_offset = Kabinet::Constants::DOOR_FRONT_OFFSET_MM.mm
        wall_t       = Kabinet::Constants::DRAWER_BOX_WALL_MM.mm
        bot_t        = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.mm

        # ── 전판 레이아웃: Fitting 공식 (커트리스트와 동일) ──────────────
        fronts = Kabinet::Core::Fitting.drawer_fronts(
          @width, @height, @drawer_count,
          side_gap:   Kabinet::Constants::DRAWER_FRONT_GAP_MM.mm,
          top_gap:    Kabinet::Constants::DOOR_GAP_TOP_MM.mm,
          bottom_gap: Kabinet::Constants::DOOR_GAP_BOTTOM_MM.mm,
          reveal:     reveal)

        # ── 서랍통 치수: 슬라이드 규격 스냅 (mm 계산 후 SU Length 변환) ──
        inner_depth_mm = Kabinet::Core::Fitting.len_mm(@depth - @back_thickness -
                                                       Kabinet::Constants::BACK_RECESS_MM.mm)
        compartment_h  = (opening_height - reveal * (@drawer_count - 1)) / @drawer_count.to_f
        box = Kabinet::Core::Fitting.drawer_box_mm(
          open_w_mm:      Kabinet::Core::Fitting.len_mm(opening_width),
          comp_h_mm:      Kabinet::Core::Fitting.len_mm(compartment_h),
          inner_depth_mm: inner_depth_mm,
          type:           @drawer_type)
        side_clear = (opening_width - box[:w].mm) / 2.0

        @drawer_count.times do |i|
          f = fronts[i]

          # ── 전판 서브그룹 (손잡이 포함, 개별 선택 가능)
          front_grp = drawers_grp.entities.add_group
          front_grp.transformation = ::Geom::Transformation.new(
            ::Geom::Point3d.new(f[:x], -(@drawer_thickness + front_offset), f[:z]))
          Kabinet::Persistence::Attributes.set_role(front_grp,
                                                    "drawer_front_#{i}", label: "서랍전판_#{i + 1}")

          Kabinet::Geometry::Builder.box(
            front_grp.entities, f[:w], @drawer_thickness, f[:h],
            Kabinet::Geometry::Transforms::IDENTITY,
            role: "drawer_front_#{i}", label: "drawer_front_#{i}",
            material_name: 'drawer_front')

          # 손잡이 geometry (전판 로컬 좌표: Y=0 전면, panel_role: :drawer)
          unless @handle_type == 'none' || @handle_type == 'push_open' || @handle_type == 'channel'
            Kabinet::Geometry::HandleBuilder.build(
              front_grp.entities, f[:w], @drawer_thickness, f[:h],
              @handle_type, hole_mm: @handle_hole_mm, panel_role: :drawer)
          end

          # ── 서랍 박스 (5-sided box)
          z_box = @body_thickness + i * (compartment_h + reveal) + box[:z_off].mm
          build_drawer_box(drawers_grp.entities,
                           x: @body_thickness + side_clear, y: 0, z: z_box,
                           w: box[:w].mm, d: box[:d].mm, h: box[:h].mm,
                           wall_t: wall_t, bot_t: bot_t,
                           index: i)
        end

        group
      end

      def self.from_hash(h)
        new(width:            (h['width']  || 600).mm,
            depth:            (h['depth']  || 400).mm,
            height:           (h['height'] || 200).mm,
            body_thickness:   (h['body_thickness'] || Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM).mm,
            back_thickness:   (h['back_thickness'] || Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM).mm,
            drawer_count:     (h['drawer_count'] || 1).to_i,
            drawer_type:      h['drawer_type'] || 'undermount',
            drawer_thickness: (h['drawer_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM).mm,
            handle_type:      h['handle_type']     || 'none',
            handle_hole_mm:   (h['handle_hole_mm'] || 128).to_i,
            has_back:         h.fetch('has_back', true) ? true : false)
      end

      private

      def build_drawer_box(parent_entities, x:, y:, z:, w:, d:, h:, wall_t:, bot_t:, index:)
        wrap = parent_entities.add_group
        wrap.transformation = ::Geom::Transformation.new(::Geom::Point3d.new(x, y, z))
        Kabinet::Persistence::Attributes.set_role(wrap, "drawer_box_#{index}")

        # Bottom
        Kabinet::Geometry::Builder.box(wrap.entities, w, d, bot_t,
                                       Kabinet::Geometry::Transforms::IDENTITY,
                                       role: 'drawer_bottom', material_name: 'drawer_box')
        # Side L
        Kabinet::Geometry::Builder.box(wrap.entities, wall_t, d, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(0, 0, 0)),
                                       role: 'drawer_side_left', material_name: 'drawer_box')
        # Side R
        Kabinet::Geometry::Builder.box(wrap.entities, wall_t, d, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(w - wall_t, 0, 0)),
                                       role: 'drawer_side_right', material_name: 'drawer_box')
        # Front (inner front wall)
        Kabinet::Geometry::Builder.box(wrap.entities, w - 2 * wall_t, wall_t, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(wall_t, 0, 0)),
                                       role: 'drawer_inner_front', material_name: 'drawer_box')
        # Back
        Kabinet::Geometry::Builder.box(wrap.entities, w - 2 * wall_t, wall_t, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(wall_t, d - wall_t, 0)),
                                       role: 'drawer_back', material_name: 'drawer_box')
      end
    end
  end
end
