module Kabinet
  module Core
    # A Carcase + optional doors + N interior shelves + accessories.
    # Lengths in SU Length.
    class ShelfModule
      attr_reader :width, :depth, :height, :body_thickness, :back_thickness,
                  :door_config, :door_thickness, :shelves, :accessories

      def initialize(width:, depth:, height:,
                     body_thickness: Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness: Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     door_config: 'none',
                     door_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.mm,
                     shelves: [], accessories: [])
        @width = width
        @depth = depth
        @height = height
        @body_thickness = body_thickness
        @back_thickness = back_thickness
        @door_config = door_config
        @door_thickness = door_thickness
        @shelves = shelves
        @accessories = accessories
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

      def build(parent_entities, parent_transform, role: 'shelf_module')
        group = parent_entities.add_group
        group.transformation = parent_transform
        Kabinet::Persistence::Attributes.set_role(group, role,
                                                  width: @width.to_f, depth: @depth.to_f, height: @height.to_f)

        # Carcase panels (no inner wrap group — flat into module group)
        carcase.build(group.entities, Kabinet::Geometry::Transforms::IDENTITY, wrap_group: false)

        # Interior shelves
        @shelves.each do |s|
          z = s['height_from_bottom'].mm
          t = s['thickness'].mm
          inset = s['depth_inset'].mm
          inner_w = opening_width
          shelf_d = @depth - inset - @back_thickness - Kabinet::Constants::BACK_RECESS_MM.mm
          local = ::Geom::Transformation.new(::Geom::Point3d.new(@body_thickness, 0, z))
          Kabinet::Geometry::Builder.box(group.entities, inner_w, shelf_d, t,
                                         local, role: 'shelf', label: 'shelf', material_name: 'shelf')
        end

        # Accessories
        @accessories.each do |acc_hash|
          acc = Accessory.new(kind: acc_hash['kind'], **symbolize(acc_hash.reject { |k, _| k == 'kind' }))
          acc.build(group.entities, Kabinet::Geometry::Transforms::IDENTITY, carcase: carcase)
        end

        # Doors
        unless @door_config == 'none'
          door = DoorPanel.new(opening_width: opening_width, opening_height: @height,
                               thickness: @door_thickness, config: @door_config,
                               gap_top: 0, gap_bottom: 0)
          door.build(group.entities, Kabinet::Geometry::Transforms::IDENTITY)
        end

        group
      end

      def self.from_hash(h)
        new(width: h['width'].mm, depth: h['depth'].mm, height: h['height'].mm,
            body_thickness: h['body_thickness'].mm, back_thickness: h['back_thickness'].mm,
            door_config: h['door_config'], door_thickness: h['door_thickness'].mm,
            shelves: h['shelves'] || [], accessories: h['accessories'] || [])
      end

      private

      def symbolize(hash)
        hash.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
      end
    end
  end
end
