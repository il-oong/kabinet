# frozen_string_literal: false
# LayOut 출력(furniture_sheet): SketchUp/LayOut 없이 확인 가능한 부분 — 파일 로드, 은선 스타일 상수,
# 옷걸이봉 윤곽선 추가, 상세 2장째 도우미 클래스 구성
module Kabinet; end
require_relative '../kabinet/constants'
module Kabinet; module Persistence; module Attributes; def self.role(e); e.role; end; end; end; end
module Sketchup; class Group; end; class ComponentInstance; end; class Edge; end; class Face; end; end
module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x, y, z); @x, @y, @z = x, y, z; end
    def transform(t); self.class.new(x + t[0], y + t[1], z + t[2]); end
    def to_a; [x, y, z]; end
  end
  class Transformation; end
end
class Numeric; def to_mm; self; end; end
require_relative '../kabinet/output/furniture_sheet'
def assert(v, m); raise m unless v; end
FS = Kabinet::Output::FurnitureSheet

# 은선은 진한 파랑 + 0.5 (예전 연회색 0.3 보다 굵고 진하게)
assert FS::HIDDEN_COLOR == '#1f5fa8' && FS::HIDDEN_WEIGHT >= 0.5, 'hidden line style'
assert FS::HIDDEN_COLOR != '#92968c', 'no pale gray'

# 옷걸이봉: 곡면 옆선이 수집에서 빠지므로 축 방향 윤곽선 4줄을 직접 추가
Bounds = Struct.new(:min, :max)
class FakeRod
  attr_reader :definition
  def initialize(role); @role = role; @definition = Struct.new(:bounds).new(Bounds.new(Geom::Point3d.new(0, -16.0, -16.0), Geom::Point3d.new(800.0, 16.0, 16.0))); end
  def role; @role; end
end
segs = []
FS.send(:rod_silhouette, FakeRod.new('hanging_rod'), [10.0, 0.0, 500.0], segs)
assert segs.size == 4, "rod silhouette lines #{segs.size}"
assert segs.all? { |a, b| (b[0] - a[0] - 800.0).abs < 1e-9 && a[1] == b[1] && a[2] == b[2] }, 'lines run along rod axis'
ys = segs.map { |a, _| a[1] }.uniq.sort
zs = segs.map { |a, _| a[2] }.uniq.sort
assert ys.first == -16.0 && ys.last == 16.0 && zs.first == 484.0 && zs.last == 516.0, "silhouette offsets #{ys} #{zs}"
none = []
FS.send(:rod_silhouette, FakeRod.new('door_pair_left'), [0, 0, 0], none)
assert none.empty?, 'non-rod groups unchanged'

# 상세 2장째 도우미: 모든 그리기 메서드를 공개로 재사용
assert Kabinet::Output::DetailSheet.public_method_defined?(:draw_view), 'DetailSheet.draw_view'
page = Object.new
sheet = Kabinet::Output::DetailSheet.new(page)
assert sheet.send(:page_of, nil).equal?(page), 'DetailSheet draws on its own page'
puts 'furniture_sheet_test: OK'
