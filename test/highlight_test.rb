require_relative 'support/geom'
GL_TRIANGLES = 4 unless defined?(GL_TRIANGLES)
GL_QUADS = 7 unless defined?(GL_QUADS)
module Sketchup
  class Color
    attr_reader :rgba
    def initialize(*rgba); @rgba = rgba; end
  end
end
module Geom
  class Vector3d
    def reverse; Vector3d.new(-x, -y, -z); end
  end
end
module Kabinet; end
require_relative '../kabinet/ui/panel_tools'

def assert(value, message); raise message unless value; end

# 사각형 면에 구멍이 하나 있는 메쉬: 삼각형 8개(점 24개)
FakeMesh = Struct.new(:points, :polys) do
  def polygons; polys; end
  def point_at(i); points[i - 1]; end
end
FakeFace = Struct.new(:m) { def mesh(_flags); m; end }
FakeCamera = Struct.new(:direction)
class FakeView
  attr_accessor :drawing_color, :camera
  attr_reader :calls
  def initialize(dir); @camera = FakeCamera.new(dir); @calls = []; end
  def draw(mode, pts); @calls << [mode, pts, drawing_color]; end
end

pts = [[0,0,0],[10,0,0],[10,10,0],[0,10,0]].map { |a| Geom::Point3d.new(*a) }
quad = FakeFace.new(FakeMesh.new(pts, [[1, -2, 3, 4]]))   # 4각 폴리곤(숨은 모서리 음수 인덱스)
tris = Kabinet::UI::Highlight.face_triangles(quad, Geom::Transformation.new(Geom::Point3d.new(5, 0, 0)))
assert(tris.size == 6, "quad → 2 triangles, got #{tris.size} points")
assert(tris.first.x == 5 && tris[1].x == 15, 'triangles must be in world coords')

up = Geom::Vector3d.new(0, 0, 1)
view = FakeView.new(Geom::Vector3d.new(0, 0, -1))           # 위에서 내려다봄
Kabinet::UI::Highlight.fill_face(view, tris, up, Kabinet::UI::Highlight::HOVER)
mode, drawn, color = view.calls.last
assert(mode == GL_TRIANGLES && drawn.size == 6, 'fill_face draws triangles')
assert(drawn.all? { |p| p.z > 0 }, 'fill lifts toward camera')
assert(color.rgba == Kabinet::UI::Highlight::HOVER, 'hover colour')

view = FakeView.new(Geom::Vector3d.new(0, 0, 1))            # 아래에서 올려다봄
Kabinet::UI::Highlight.fill_face(view, tris, up, Kabinet::UI::Highlight::PRESSED)
assert(view.calls.last[1].all? { |p| p.z < 0 }, 'lift flips to camera side')

Kabinet::UI::Highlight.fill_face(view, [], up, Kabinet::UI::Highlight::HOVER)
assert(view.calls.size == 1, 'empty highlight draws nothing')

corners = (0..7).map { |k| Geom::Point3d.new(k[2], k[1], k[0]) }
Kabinet::UI::Highlight.fill_box(view, corners, Kabinet::UI::Highlight::PART)
assert(view.calls.last[0] == GL_QUADS && view.calls.last[1].size == 24, 'box → 6 quads')

puts 'highlight_test: ok'
