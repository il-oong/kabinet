# frozen_string_literal: false
# 도면 정면 표시: 정면 면 위치, 화살표 방향, 정면에서 본 좌/우
require_relative 'support/geom'
module Geom
  class Point3d; def -(p); Vector3d.new(x - p.x, y - p.y, z - p.z); end; end
  class Vector3d; def reverse; Vector3d.new(-x, -y, -z); end; end
  class BoundingBox
    def corner(k); a = min; b = max; Point3d.new(k & 1 == 0 ? a.x : b.x, k & 2 == 0 ? a.y : b.y, k & 4 == 0 ? a.z : b.z); end
  end
end
module Sketchup; class Group; attr_accessor :bounds; end; class ComponentInstance; end; end
module Kabinet
  module Output
    module FurnitureSheet
      FRONT_AXES = { '-Y' => [0.0, -1.0], '+Y' => [0.0, 1.0], '-X' => [-1.0, 0.0], '+X' => [1.0, 0.0] }.freeze
      def self.front_axis(_t); $axis; end
    end
  end
end
require_relative '../kabinet/ui/front_view_tool'
def assert(v, m); raise m unless v; end
g = Sketchup::Group.new
g.bounds = Geom::BoundingBox.new.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1000.mm, 600.mm, 2000.mm))

$axis = '-Y'   # 정면이 -Y: 사람은 -Y 쪽에 서서 +Y를 봄 → 오른쪽은 +X
it = Kabinet::UI::FrontViewTool.new([g]).instance_variable_get(:@items).first
assert it[:front_quad].all? { |p| p.y.abs < 1e-9 }, 'front face at y=0'
assert it[:arrow_tip].y < 0, 'arrow points to -Y'
assert it[:right].x > 1000.mm && it[:left].x < 0, "right=+X left=-X (#{it[:right].x}, #{it[:left].x})"
assert it[:back].y > 600.mm, 'back label behind'

$axis = '+X'   # 정면 +X: 사람은 +X 쪽에서 -X를 봄 → 오른쪽은 +Y
it = Kabinet::UI::FrontViewTool.new([g]).instance_variable_get(:@items).first
assert it[:front_quad].all? { |p| (p.x - 1000.mm).abs < 1e-9 }, 'front face at x=max'
assert it[:arrow_tip].x > 1000.mm, 'arrow +X'
assert it[:right].y > 600.mm && it[:left].y < 0, 'right=+Y'
begin; Kabinet::UI::FrontViewTool.new([]); raise 'x'; rescue RuntimeError => e; raise if e.message == 'x'; end
puts 'front_view_tool_test: OK'
