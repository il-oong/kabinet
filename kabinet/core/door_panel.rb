module Kabinet
  module Core
    # Door(s) that mount in front of a carcase opening.
    # opening_width / opening_height are the inside opening dimensions of the carcase
    # (i.e. width − 2*body_thickness, height − ...).
    # Door is placed in front of the carcase (negative-Y in carcase-local frame here means
    # we draw at y = -door_thickness so the door's outer face sits at y=0 of the carcase).
    class DoorPanel
      attr_reader :opening_width, :opening_height, :thickness, :config,
                  :gap_top, :gap_bottom, :gap_outside, :reveal_between, :front_offset

      def initialize(opening_width:, opening_height:, thickness:, config: 'pair',
                     gap_top: Kabinet::Constants::DOOR_GAP_TOP_MM.mm,
                     gap_bottom: Kabinet::Constants::DOOR_GAP_BOTTOM_MM.mm,
                     gap_outside: Kabinet::Constants::DOOR_GAP_OUTSIDE_MM.mm,
                     reveal_between: Kabinet::Constants::DOOR_REVEAL_BETWEEN_MM.mm,
                     front_offset: Kabinet::Constants::DOOR_FRONT_OFFSET_MM.mm)
        @opening_width  = opening_width
        @opening_height = opening_height
        @thickness      = thickness
        @config         = config.to_s
        @gap_top        = gap_top
        @gap_bottom     = gap_bottom
        @gap_outside    = gap_outside
        @reveal_between = reveal_between
        @front_offset   = front_offset
      end

      def door_height
        @opening_height - @gap_top - @gap_bottom
      end

      # In CARCASE-local frame (origin at carcase front-left-bottom).
      def build(parent_entities, carcase_origin_transform)
        return if @config == 'none'
        z0 = @gap_bottom
        # Door sits in front of the carcase: y starts at (-thickness - front_offset)
        y0 = -(@thickness + @front_offset)

        case @config
        when 'single'
          door_w = @opening_width - 2 * @gap_outside
          place_door(parent_entities, carcase_origin_transform,
                     x: @gap_outside, y: y0, z: z0,
                     w: door_w, h: door_height, role: 'door_single')
        when 'pair'
          # Two doors, reveal in middle
          half_w = (@opening_width - 2 * @gap_outside - @reveal_between) / 2.0
          place_door(parent_entities, carcase_origin_transform,
                     x: @gap_outside, y: y0, z: z0,
                     w: half_w, h: door_height, role: 'door_pair_left')
          place_door(parent_entities, carcase_origin_transform,
                     x: @gap_outside + half_w + @reveal_between, y: y0, z: z0,
                     w: half_w, h: door_height, role: 'door_pair_right')
        else
          raise ArgumentError, "unknown door config: #{@config}"
        end
      end

      private

      def place_door(parent_entities, parent_transform, x:, y:, z:, w:, h:, role:)
        local = ::Geom::Transformation.new(::Geom::Point3d.new(x, y, z))
        # Door panel: w along X, thickness along Y, h along Z.
        # We use Builder.box with (W=w, D=thickness, T=h).
        Kabinet::Geometry::Builder.box(parent_entities, w, @thickness, h,
                                       parent_transform * local,
                                       role: role, label: role, material_name: 'door')
      end
    end
  end
end
