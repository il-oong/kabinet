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
                  :handle_type, :handle_hole_mm

      def initialize(width:, depth:, height:,
                     body_thickness:  Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness:  Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     drawer_count:    1,
                     drawer_type:     'undermount',
                     drawer_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.mm,
                     handle_type:     'none',
                     handle_hole_mm:  128)
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
      end

      def carcase
        @carcase ||= Carcase.new(width: @width, depth: @depth, height: @height,
                                 body_thickness: @body_thickness, back_thickness: @back_thickness)
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
                        suppress_bottom: suppress_bottom)
        c.build(body_grp.entities, Kabinet::Geometry::Transforms::IDENTITY, wrap_group: false)

        # ── 서랍 그룹 (전판 + 박스)
        drawers_grp = group.entities.add_group
        Kabinet::Persistence::Attributes.set_role(drawers_grp, 'drawers_group', label: '서랍')

        gap_o        = Kabinet::Constants::DOOR_GAP_OUTSIDE_MM.mm
        gap_t        = Kabinet::Constants::DOOR_GAP_TOP_MM.mm
        gap_b        = Kabinet::Constants::DOOR_GAP_BOTTOM_MM.mm
        reveal       = Kabinet::Constants::DRAWER_REVEAL_BETWEEN_MM.mm
        front_offset = Kabinet::Constants::DOOR_FRONT_OFFSET_MM.mm

        front_w = @width - 2 * gap_o
        avail_h = @height - gap_t - gap_b - (reveal * (@drawer_count - 1))
        front_h = avail_h / @drawer_count.to_f

        side_clear    = (@drawer_type == 'undermount' ?
                         Kabinet::Constants::UNDERMOUNT_SIDE_CLEARANCE_MM :
                         Kabinet::Constants::SIDEMOUNT_SIDE_CLEARANCE_MM).mm
        height_offset = (@drawer_type == 'undermount' ?
                         Kabinet::Constants::UNDERMOUNT_HEIGHT_OFFSET_MM :
                         Kabinet::Constants::SIDEMOUNT_HEIGHT_OFFSET_MM).mm

        wall_t = Kabinet::Constants::DRAWER_BOX_WALL_MM.mm
        bot_t  = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.mm

        @drawer_count.times do |i|
          z_front = gap_b + i * (front_h + reveal)

          # ── 전판 서브그룹 (손잡이 포함, 개별 선택 가능)
          front_grp = drawers_grp.entities.add_group
          front_grp.transformation = ::Geom::Transformation.new(
            ::Geom::Point3d.new(gap_o, -(@drawer_thickness + front_offset), z_front))
          Kabinet::Persistence::Attributes.set_role(front_grp,
                                                    "drawer_front_#{i}", label: "서랍전판_#{i + 1}")

          Kabinet::Geometry::Builder.box(
            front_grp.entities, front_w, @drawer_thickness, front_h,
            Kabinet::Geometry::Transforms::IDENTITY,
            role: "drawer_front_#{i}", label: "drawer_front_#{i}",
            material_name: 'drawer_front')

          # 손잡이 geometry (전판 로컬 좌표: Y=0 전면, panel_role: :drawer)
          unless @handle_type == 'none' || @handle_type == 'push_open' || @handle_type == 'channel'
            Kabinet::Geometry::HandleBuilder.build(
              front_grp.entities, front_w, @drawer_thickness, front_h,
              @handle_type, hole_mm: @handle_hole_mm, panel_role: :drawer)
          end

          # ── 서랍 박스 (5-sided box)
          compartment_h = (opening_height - reveal * (@drawer_count - 1)) / @drawer_count.to_f
          z_box = @body_thickness + i * (compartment_h + reveal) + height_offset / 2.0
          box_h = compartment_h - height_offset
          box_w = opening_width - 2 * side_clear
          box_d = @depth - @back_thickness - Kabinet::Constants::BACK_RECESS_MM.mm - 30.mm
          x_box = @body_thickness + side_clear

          build_drawer_box(drawers_grp.entities,
                           x: x_box, y: 0, z: z_box,
                           w: box_w, d: box_d, h: box_h, wall_t: wall_t, bot_t: bot_t,
                           index: i)
        end

        group
      end

      def self.from_hash(h)
        new(width:            h['width'].mm,
            depth:            h['depth'].mm,
            height:           h['height'].mm,
            body_thickness:   h['body_thickness'].mm,
            back_thickness:   h['back_thickness'].mm,
            drawer_count:     h['drawer_count'],
            drawer_type:      h['drawer_type'],
            drawer_thickness: h['drawer_thickness'].mm,
            handle_type:      h['handle_type']     || 'none',
            handle_hole_mm:   (h['handle_hole_mm'] || 128).to_i)
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
