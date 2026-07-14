module Kabinet
  module Core
    # Side finish panel (EP 마감) glued to the outside of the assembly.
    # Spans the full assembly height (including base + modules + top panel).
    # Side := :left or :right; mounted on the outside face of the leftmost / rightmost
    # carcase side panel of the assembly.
    class EpFinishPanel
      attr_reader :side, :thickness, :height, :depth

      def initialize(side:, thickness:, height:, depth:)
        @side      = side
        @thickness = thickness
        @height    = height
        @depth     = depth
      end

      # Builds in ASSEMBLY-local frame.
      # assembly_inner_width is the carcase width before EP (so left EP is at x=0,
      # right EP is at x = ep_left_offset + inner_width).
      # y_origin < 0 → 도어 전면 커버를 위해 카케이스 앞으로 연장.
      def build(parent_entities, assembly_origin_transform, x_origin:, y_origin: 0)
        local = ::Geom::Transformation.new(::Geom::Point3d.new(x_origin, y_origin, 0))
        Kabinet::Geometry::Builder.box(parent_entities, @thickness, @depth, @height,
                                       assembly_origin_transform * local,
                                       role: "ep_#{@side}", label: "ep_#{@side}",
                                       material_name: 'ep')
      end
    end
  end
end
