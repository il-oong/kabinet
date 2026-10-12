# frozen_string_literal: false
# 가구 배치 도구: 바닥 클릭 → 앞-왼쪽-아래가 클릭점, 벽 클릭 → 등판이 벽에 붙고 정면이 방 쪽
require_relative 'support/geom'
ORIGIN = Geom::Point3d.new(0, 0, 0) unless defined?(ORIGIN)
Z_AXIS = Geom::Vector3d.new(0, 0, 1) unless defined?(Z_AXIS)
module Geom
  class Vector3d
    def normalize!; n = normalize; @x, @y, @z = n.x, n.y, n.z; self; end
    def reverse!; @x, @y, @z = -x, -y, -z; self; end
  end
  class Point3d
    def -(p); Vector3d.new(x - p.x, y - p.y, z - p.z); end
  end
end
module Sketchup; class InputPoint; end; end
module Kabinet; module UI; end; end
require_relative '../kabinet/ui/place_tool'

def assert(v, m); raise m unless v; end
def near(a, b); (a - b).abs < 1e-6; end
def pt_near(p, q); p.to_a.zip(q).all? { |a, b| near(a, b) }; end

Face = Struct.new(:normal)
IP = Struct.new(:position, :face, :transformation)
Cam = Struct.new(:direction)
View = Struct.new(:camera)

tool = Kabinet::UI::PlaceTool.allocate
local = Geom::BoundingBox.new
local.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1000, 600, 2000))   # W1000 D600(+Y=뒤) H2000
tool.instance_variable_set(:@local, local)
tool.instance_variable_set(:@turn, 0)
view = View.new(Cam.new(Geom::Vector3d.new(0, 1, -0.3)))   # 카메라가 +Y(벽 쪽)를 봄
id = Geom::Transformation.new

# 1) 바닥(윗면) 클릭: 회전 없음, 원점이 클릭점
tool.instance_variable_set(:@ip, IP.new(Geom::Point3d.new(500, 300, 0), Face.new(Geom::Vector3d.new(0, 0, 1)), id))
t = tool.send(:placement, view)
assert pt_near(Geom::Point3d.new(0, 0, 0).transform(t), [500, 300, 0]), 'floor anchor'
assert !tool.instance_variable_get(:@wall), 'floor is not wall'

# 2) 뒷벽(y=3000, 방 쪽 법선 -Y) 클릭: 등판(local y=600)이 벽(y=3000)에, 정면(local y=0)은 y=2400
tool.instance_variable_set(:@ip, IP.new(Geom::Point3d.new(200, 3000, 0), Face.new(Geom::Vector3d.new(0, 1, 0)), id))
t = tool.send(:placement, view)
assert tool.instance_variable_get(:@wall), 'wall detected'
assert pt_near(Geom::Point3d.new(0, 600, 0).transform(t), [200, 3000, 0]), "back-left on wall #{Geom::Point3d.new(0, 600, 0).transform(t).to_a}"
assert near(Geom::Point3d.new(0, 0, 0).transform(t).y, 2400), 'front faces room'
assert near(Geom::Point3d.new(1000, 600, 0).transform(t).y, 3000), 'whole back on wall'

# 3) 왼쪽 벽(x=0, 방 쪽 법선 +X): 등판이 x=0 벽에, 가구는 +X 쪽(방 안)으로
tool.instance_variable_set(:@ip, IP.new(Geom::Point3d.new(0, 1500, 0), Face.new(Geom::Vector3d.new(1, 0, 0)), id))
view2 = View.new(Cam.new(Geom::Vector3d.new(-1, 0, -0.3)))
t = tool.send(:placement, view2)
assert near(Geom::Point3d.new(500, 600, 0).transform(t).x, 0), 'back on left wall'
assert near(Geom::Point3d.new(500, 0, 0).transform(t).x, 600), 'front toward room'

# 4) Tab 회전 1회: 바닥에서 90° 돌아감 (폭 방향 X → Y)
tool.instance_variable_set(:@turn, 1)
tool.instance_variable_set(:@ip, IP.new(Geom::Point3d.new(0, 0, 0), Face.new(Geom::Vector3d.new(0, 0, 1)), id))
t = tool.send(:placement, view)
assert pt_near(Geom::Point3d.new(1000, 0, 0).transform(t), [0, 1000, 0]), 'rotated 90'
puts 'place_tool_test: OK'
