# 선택 그룹 → 재단 목록: 중첩 그룹을 끝까지 내려가 판재별 두께/폭/길이·수량을 집계하는지 확인
# frozen_string_literal: false
require_relative 'support/geom'
module Geom
  class Point3d
    def distance(p); (self - p).length; end
  end
  class BoundingBox
    def initialize(min, max); @min, @max = min, max; end
    # SketchUp 순서: bit0=x, bit1=y, bit2=z
    def corner(k)
      Point3d.new(k & 1 == 0 ? @min.x : @max.x, k & 2 == 0 ? @min.y : @max.y, k & 4 == 0 ? @min.z : @max.z)
    end
  end
end
class Float; def to_mm; self * 25.4; end; end
module Sketchup
  class Face; end
  class Definition
    attr_reader :entities, :bounds, :name
    def initialize(entities, bounds = nil, name = ''); @entities, @bounds, @name = entities, bounds, name; end
  end
  class Group
    attr_reader :name, :definition, :transformation
    def initialize(name, definition, tr = Geom::Transformation.new); @name, @definition, @transformation = name, definition, tr; end
  end
  class ComponentInstance < Group; end
end
module UI; end
module Kabinet; module UI; module Dialog; module_function; end; end; end
src = File.read(File.join(__dir__, '../kabinet/ui/dialog.rb'), encoding: 'UTF-8')
body = src[/      def group_cut_rows.*?\n      end\n/m]
Kabinet::UI::Dialog.module_eval(body)
Kabinet::UI::Dialog.send(:module_function, :group_cut_rows)

def panel(name, w, d, h, origin = [0, 0, 0])
  bb = Geom::BoundingBox.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(w.mm, d.mm, h.mm))
  Sketchup::Group.new(name, Sketchup::Definition.new([Sketchup::Face.new], bb), Geom::Transformation.new(origin))
end
side  = panel('측판', 18, 580, 2000)
side2 = panel('측판', 18, 580, 2000, [1000, 0, 0])
top   = panel('상판', 964, 580, 18)
loose = panel('', 400, 300, 9)
cab   = Sketchup::Group.new('붙박이장', Sketchup::Definition.new([side, side2, top]))
rows  = Kabinet::UI::Dialog.group_cut_rows([cab, loose])

def assert(v, m); raise m unless v; end
assert rows.size == 3, "rows #{rows.inspect}"
s = rows.find { |r| r[:name] == '측판' }
assert s && s[:qty] == 2 && s[:t] == '18' && s[:w] == '580' && s[:l] == '2000', "side #{s.inspect}"
t = rows.find { |r| r[:name] == '상판' }
assert t && t[:t] == '18' && t[:w] == '580' && t[:l] == '964', "top #{t.inspect}"
assert rows.any? { |r| r[:name] == '판재' && r[:t] == '9' }, 'unnamed panel labelled 판재'
puts 'group_cutlist_test: OK'
