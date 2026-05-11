module Kabinet
  module Core
    # Polymorphic accessory inside a shelf module.
    # kind: :hanging_rod | :system_hanger | :shelf_accessory
    class Accessory
      attr_reader :kind, :params

      def initialize(kind:, **params)
        @kind = kind.to_sym
        @params = params
      end

      # parent_entities = the carcase group's entities (so origin is carcase-local front-left-bottom)
      # carcase: the Carcase instance — used to know width/depth/body_t for placement
      def build(parent_entities, carcase_origin_transform, carcase:)
        case @kind
        when :hanging_rod   then build_hanging_rod(parent_entities, carcase_origin_transform, carcase)
        when :system_hanger then build_system_hanger(parent_entities, carcase_origin_transform, carcase)
        when :shelf_accessory then build_shelf(parent_entities, carcase_origin_transform, carcase)
        else
          raise ArgumentError, "unknown accessory kind: #{@kind}"
        end
      end

      private

      def build_hanging_rod(parent_entities, parent_transform, carcase)
        diameter = (@params[:diameter] || Kabinet::Constants::HANGING_ROD_DIAMETER_MM).mm
        z_height = (@params[:height_from_bottom]).mm
        depth_inset = (@params[:depth_inset] || 75).mm

        rod_length = carcase.width - 2 * carcase.body_thickness
        # Rod runs along X, mounted between sides at z=z_height, depth-inset from rear by depth_inset.
        x0 = carcase.body_thickness
        y0 = carcase.depth - depth_inset
        z0 = z_height
        local = ::Geom::Transformation.new(::Geom::Point3d.new(x0, y0, z0))
        # rod axis along +X — Builder.rod draws circle in YZ then pushpulls along X
        Kabinet::Geometry::Builder.rod(parent_entities, rod_length, diameter,
                                       parent_transform * local,
                                       axis: :x, role: 'hanging_rod', label: 'hanging_rod')
      end

      def build_system_hanger(parent_entities, parent_transform, carcase)
        z0 = (@params[:height_from_bottom]).mm
        rail_h = (@params[:rail_height] || 30).mm
        rail_t = (@params[:rail_thickness] || 5).mm

        # Mounted on the back panel face. Inner width across.
        inner_w = carcase.width - 2 * carcase.body_thickness
        x0 = carcase.body_thickness
        y0 = carcase.depth - Kabinet::Constants::BACK_RECESS_MM.mm - carcase.back_thickness - rail_t
        local = ::Geom::Transformation.new(::Geom::Point3d.new(x0, y0, z0))
        Kabinet::Geometry::Builder.box(parent_entities, inner_w, rail_t, rail_h,
                                       parent_transform * local,
                                       role: 'system_hanger', label: 'system_hanger')
      end

      def build_shelf(parent_entities, parent_transform, carcase)
        z0 = (@params[:height_from_bottom]).mm
        thickness = (@params[:thickness] || 18).mm
        depth_inset = (@params[:depth_inset] || 20).mm

        inner_w = carcase.width - 2 * carcase.body_thickness
        shelf_d = carcase.depth - depth_inset - carcase.back_thickness - Kabinet::Constants::BACK_RECESS_MM.mm
        x0 = carcase.body_thickness
        y0 = 0
        local = ::Geom::Transformation.new(::Geom::Point3d.new(x0, y0, z0))
        Kabinet::Geometry::Builder.box(parent_entities, inner_w, shelf_d, thickness,
                                       parent_transform * local,
                                       role: 'shelf_accessory', label: 'shelf', material_name: 'shelf')
      end
    end
  end
end
