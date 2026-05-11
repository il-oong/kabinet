module Kabinet
  module Geometry
    module Transforms
      IDENTITY = ::Geom::Transformation.new

      def self.translate(x, y, z)
        ::Geom::Transformation.new(::Geom::Point3d.new(x, y, z))
      end

      def self.translate_mm(x_mm, y_mm, z_mm)
        translate(x_mm.mm, y_mm.mm, z_mm.mm)
      end

      def self.compose(*transforms)
        transforms.reduce(IDENTITY) { |acc, t| acc * t }
      end
    end
  end
end
