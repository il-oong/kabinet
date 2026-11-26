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
require_relative '../kabinet/output/sheet_layout'
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

# 쪽 전용 캔버스: 선·글자·치수 도구를 공개로 재사용, 자기 쪽에만 그림
%i[line text horizontal_dimension vertical_dimension draw_page].each do |m|
  assert Kabinet::Output::PageCanvas.public_method_defined?(m), "PageCanvas.#{m}"
end
page = Object.new
sheet = Kabinet::Output::PageCanvas.new(page)
assert sheet.send(:page_of, nil).equal?(page), 'PageCanvas draws on its own page'

# 쪽 선택 옵션: 기본 3종, 잘못된 값은 걸러내고 비면 오류
assert FS.pages_option({}) == %w[iso front side], 'default pages'
assert FS.pages_option('pages' => %w[side iso bogus]) == %w[iso side], 'filter pages'
begin
  FS.pages_option('pages' => [])
  assert false, 'empty pages must raise'
rescue RuntimeError => e
  assert e.message.include?('쪽'), 'empty pages message'
end

# 글자 깨짐 방지: 소스의 LayOut 에 들어가는 문자열은 CP949 로 표현 가능해야 한다(em dash 등 금지)
%w[furniture_sheet.rb sheet_layout.rb space_sheet.rb].each do |f|
  File.read(File.join(__dir__, '..', 'kabinet', 'output', f), encoding: 'UTF-8').each_line.with_index(1) do |line, no|
    next if line.lstrip.start_with?('#') || line.include?('TEXT_MAP')
    line.each_char do |ch|
      next if ch.ord < 128
      begin
        ch.encode(Encoding::CP949)
      rescue Encoding::UndefinedConversionError
        assert false, "#{f}:#{no} CP949 에 없는 문자 U+#{ch.ord.to_s(16)} (LayOut 에서 ? 로 깨짐)"
      end
    end
  end
end
puts 'furniture_sheet_test: OK'
