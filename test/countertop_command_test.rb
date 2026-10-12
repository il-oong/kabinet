# frozen_string_literal: false
# 주방 상판 명령: 선택한 하부장(손잡이 포함 그룹)의 외곽·정면·높이 인식 → 계산 결과 확인 (형상 생성은 대체)
require_relative 'support/geom'
Z_AXIS = Geom::Vector3d.new(0, 0, 1) unless defined?(Z_AXIS)
class Numeric; def mm; to_f / 25.4; end; end
module Geom
  class Point3d
    def -(p); Vector3d.new(x - p.x, y - p.y, z - p.z); end
  end
  class Transformation
    def origin; Point3d.new(*apply([0, 0, 0], 1)); end
  end
  class BoundingBox
    def empty?; @points.empty?; end
    def corner(k)
      a = min; b = max
      Point3d.new(k & 1 == 0 ? a.x : b.x, k & 2 == 0 ? a.y : b.y, k & 4 == 0 ? a.z : b.z)
    end
  end
  class Vector3d
    def cross(v); Vector3d.new(y * v.z - z * v.y, z * v.x - x * v.z, x * v.y - y * v.x); end
  end
end
module Sketchup
  Vertex = Struct.new(:position)
  class Edge
    attr_reader :vertices
    def initialize(a, b); @vertices = [Vertex.new(a), Vertex.new(b)]; end
    def hidden?; false; end
  end
  Definition = Struct.new(:entities, :name) do
    def get_attribute(*); nil; end
  end
  class Group
    attr_reader :definition, :transformation, :name
    def initialize(name, ents, tr, role = nil); @name, @definition, @transformation, @role = name, Definition.new(ents, name), tr, role; end
    def hidden?; false; end
    def get_attribute(dict, key, default = nil); key == 'role' ? (@role || default) : default; end
  end
  class ComponentInstance < Group; end
end
module Kabinet
  module Persistence; module Attributes; def self.role(e); e.get_attribute('kabinet', 'role'); end; end; end
end
require_relative '../kabinet/core/countertop'
require_relative '../kabinet/commands/countertop'
def assert(v, m); raise m unless v; end

def box(x0, y0, z0, x1, y1, z1)
  p = ->(x, y, z) { Geom::Point3d.new(x.mm, y.mm, z.mm) }
  [Sketchup::Edge.new(p.(x0, y0, z0), p.(x1, y1, z1))]
end
# 하부장: 몸통 600×(도어 포함 깊이 600: y 0..600)×860, 손잡이가 앞으로 40 돌출 (y -40..0)
def cabinet(x)
  body = Sketchup::Group.new('body', box(0, 0, 0, 600, 600, 860), Geom::Transformation.new)
  handle = Sketchup::Group.new('h', box(250, -40, 600, 350, 0, 620), Geom::Transformation.new, 'handle_bar')
  Sketchup::Group.new('하부장', [body, handle], Geom::Transformation.new(Geom::Point3d.new(x.mm, 0, 0)))
end
Model = Struct.new(:selection, :edit_transform)
model = Model.new([cabinet(0), cabinet(600)], Geom::Transformation.new)

captured = nil
Kabinet::Commands::Countertop.define_singleton_method(:build) { |_m, plan, t, bottom, *_| captured = [plan, t, bottom]; 'ok' }
Kabinet::Commands::Countertop.run({ 'thickness' => 12, 'front_overhang' => 20, 'side_overhang' => 0 }, model: model)
plan, t, bottom = captured
xs = plan[:cells].flat_map { |c| [c[0], c[2]] }.minmax.map(&:round)
ys = plan[:cells].flat_map { |c| [c[1], c[3]] }.minmax.map(&:round)
assert xs == [0, 1200], "x #{xs}"
assert ys == [-20, 600], "y #{ys} (손잡이 무시, 도어 앞면 0에서 20 돌출)"
assert t == 12 && bottom.round == 860, "height #{bottom}"

Kabinet::Commands::Countertop.run({ 'thickness' => 20, 'height_mode' => 'fixed', 'top_height' => 900 }, model: model)
assert captured[2].round == 880, 'fixed top height'
begin
  Kabinet::Commands::Countertop.run({ 'thickness' => 12 }, model: Model.new([], Geom::Transformation.new))
  raise 'expected'
rescue RuntimeError => e
  raise if e.message == 'expected'
end
puts 'countertop_command_test: OK'
