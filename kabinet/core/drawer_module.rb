module Kabinet
  module Core
    # Carcase + N stacked drawers (front + 5-sided box).
    # All inputs in SU Length.
    class DrawerModule
      attr_reader :width, :depth, :height, :body_thickness, :back_thickness,
                  :drawer_count, :drawer_type, :drawer_thickness

      def initialize(width:, depth:, height:,
                     body_thickness: Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness: Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     drawer_count: 1, drawer_type: 'undermount',
                     drawer_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.mm)
        @width = width
        @depth = depth
        @height = height
        @body_thickness = body_thickness
        @back_thickness = back_thickness
        @drawer_count = drawer_count
        @drawer_type  = drawer_type.to_s
        @drawer_thickness = drawer_thickness
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

      def build(parent_entities, parent_transform, role: 'drawer_module')
        group = parent_entities.add_group
        group.transformation = parent_transform
        Kabinet::Persistence::Attributes.set_role(group, role,
                                                  width: @width.to_f, depth: @depth.to_f, height: @height.to_f,
                                                  drawer_count: @drawer_count, drawer_type: @drawer_type)

        # Carcase
        carcase.build(group.entities, Kabinet::Geometry::Transforms::IDENTITY, wrap_group: false)

        # Drawer fronts: stacked with reveals between them, gaps at outer perimeter
        gap_o = Kabinet::Constants::DOOR_GAP_OUTSIDE_MM.mm
        gap_t = Kabinet::Constants::DOOR_GAP_TOP_MM.mm
        gap_b = Kabinet::Constants::DOOR_GAP_BOTTOM_MM.mm
        reveal = Kabinet::Constants::DRAWER_REVEAL_BETWEEN_MM.mm
        front_offset = Kabinet::Constants::DOOR_FRONT_OFFSET_MM.mm

        front_w = @width - 2 * gap_o
        avail_h = @height - gap_t - gap_b - (reveal * (@drawer_count - 1))
        front_h = avail_h / @drawer_count.to_f

        side_clear = (@drawer_type == 'undermount' ?
                      Kabinet::Constants::UNDERMOUNT_SIDE_CLEARANCE_MM :
                      Kabinet::Constants::SIDEMOUNT_SIDE_CLEARANCE_MM).mm
        height_offset = (@drawer_type == 'undermount' ?
                         Kabinet::Constants::UNDERMOUNT_HEIGHT_OFFSET_MM :
                         Kabinet::Constants::SIDEMOUNT_HEIGHT_OFFSET_MM).mm

        wall_t = Kabinet::Constants::DRAWER_BOX_WALL_MM.mm
        bot_t  = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.mm

        @drawer_count.times do |i|
          z_front = gap_b + i * (front_h + reveal)
          # Front
          local_front = ::Geom::Transformation.new(::Geom::Point3d.new(gap_o, -(@drawer_thickness + front_offset), z_front))
          Kabinet::Geometry::Builder.box(group.entities, front_w, @drawer_thickness, front_h,
                                         local_front,
                                         role: "drawer_front_#{i}", label: "drawer_front_#{i}",
                                         material_name: 'drawer_front')

          # Drawer box: sits inside the carcase, aligned with the front from the rear.
          # Compartment height (interior) corresponds roughly to opening_height/count,
          # box height = compartment − height_offset (slide allowance).
          compartment_h = (opening_height - reveal * (@drawer_count - 1)) / @drawer_count.to_f
          z_box = @body_thickness + i * (compartment_h + reveal) + height_offset / 2.0
          box_h = compartment_h - height_offset
          box_w = opening_width - 2 * side_clear
          # Box depth: leave 30mm clearance from back panel face
          box_d = @depth - @back_thickness - Kabinet::Constants::BACK_RECESS_MM.mm - 30.mm
          x_box = @body_thickness + side_clear

          build_drawer_box(group.entities,
                           x: x_box, y: 0, z: z_box,
                           w: box_w, d: box_d, h: box_h, wall_t: wall_t, bot_t: bot_t,
                           index: i)
        end

        group
      end

      def self.from_hash(h)
        new(width: h['width'].mm, depth: h['depth'].mm, height: h['height'].mm,
            body_thickness: h['body_thickness'].mm, back_thickness: h['back_thickness'].mm,
            drawer_count: h['drawer_count'], drawer_type: h['drawer_type'],
            drawer_thickness: h['drawer_thickness'].mm)
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
