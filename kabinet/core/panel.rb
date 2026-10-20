module Kabinet
  module Core
    # Lightweight value object describing a single panel.
    # Domain-level fields are in SU Length (already converted via .mm).
    class Panel
      attr_reader :role, :width, :depth, :thickness, :x, :y, :z, :material, :notch_d, :notches

      def initialize(role:, width:, depth:, thickness:, x: 0, y: 0, z: 0, material: nil, notch_d: nil, notches: nil)
        @role = role
        @width = width
        @depth = depth
        @thickness = thickness
        @x = x
        @y = y
        @z = z
        @material = material
        @notch_d  = notch_d    # 측판 앞 따냄 깊이 (찬넬)
        @notches  = notches    # [[z0, z1], ...]
      end

      def build(parent_entities, parent_transform = Kabinet::Geometry::Transforms::IDENTITY)
        local = ::Geom::Transformation.new(::Geom::Point3d.new(@x, @y, @z))
        if @notches && !@notches.empty?
          return Kabinet::Geometry::Builder.notched_side(parent_entities, @width, @depth, @thickness, @notch_d, @notches,
                                                         parent_transform * local,
                                                         role: @role, label: @role, material_name: @material)
        end
        Kabinet::Geometry::Builder.box(parent_entities, @width, @depth, @thickness,
                                       parent_transform * local,
                                       role: @role, label: @role, material_name: @material)
      end

      def self.from_joinery(hash)
        new(role: hash[:role], width: hash[:w], depth: hash[:d], thickness: hash[:t],
            x: hash[:x], y: hash[:y], z: hash[:z], material: hash[:material],
            notch_d: hash[:notch_d], notches: hash[:notches])
      end
    end
  end
end
