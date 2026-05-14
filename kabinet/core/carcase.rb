module Kabinet
  module Core
    # The fundamental box: 4 walls + back. No doors, no contents.
    # All numeric inputs in SU Length (call .mm on the Numeric beforehand).
    class Carcase
      attr_reader :width, :depth, :height, :body_thickness, :back_thickness,
                  :has_back, :joinery_style, :suppress_bottom,
                  :suppress_left_side, :suppress_right_side

      def initialize(width:, depth:, height:,
                     body_thickness: Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness: Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     has_back: true, joinery_style: :sides_full,
                     suppress_bottom: false,
                     suppress_left_side: false, suppress_right_side: false)
        @width = width
        @depth = depth
        @height = height
        @body_thickness = body_thickness
        @back_thickness = back_thickness
        @has_back = has_back
        @joinery_style = joinery_style
        @suppress_bottom = suppress_bottom
        @suppress_left_side  = suppress_left_side
        @suppress_right_side = suppress_right_side
      end

      def panel_specs
        Kabinet::Geometry::Joinery.carcase_panels(
          width: @width, depth: @depth, height: @height,
          body_t: @body_thickness, back_t: @back_thickness,
          has_back: @has_back, style: @joinery_style,
          suppress_bottom: @suppress_bottom,
          suppress_left_side: @suppress_left_side,
          suppress_right_side: @suppress_right_side
        )
      end

      def panels
        panel_specs.map { |spec| Panel.from_joinery(spec) }
      end

      # Build into a parent_entities container at the given transform.
      # Wraps the carcase panels in a Group so it can be addressed as one unit.
      def build(parent_entities, parent_transform = Kabinet::Geometry::Transforms::IDENTITY,
                wrap_group: true, role: 'carcase')
        if wrap_group
          group = parent_entities.add_group
          group.transformation = parent_transform
          panels.each { |p| p.build(group.entities, Kabinet::Geometry::Transforms::IDENTITY) }
          Kabinet::Persistence::Attributes.set_role(group, role)
          group
        else
          panels.each { |p| p.build(parent_entities, parent_transform) }
        end
      end
    end
  end
end
