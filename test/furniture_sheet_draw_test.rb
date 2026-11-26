# frozen_string_literal: false
# LayOut 어댑터(PageCanvas) 실행 경로 검사 — 가짜 Layout/Geom 으로 draw_page 를 끝까지 돌려
# (1) 예외 없음 (2) 모든 선이 종이 안 (3) 쪽마다 SCALE 1/N 표기 (4) 한글 깨질 문자 없음 을 확인한다.
module Kabinet; end
require_relative '../kabinet/constants'
module Kabinet; module Persistence; module Attributes; def self.role(e); e.role; end; end; end; end
module Sketchup
  class Group; end; class ComponentInstance; end; class Edge; end; class Face; end
  class Color; attr_reader :v; def initialize(*v); @v = v; end; end
end
module Geom
  class Point2d; attr_reader :x, :y; def initialize(x, y); @x, @y = x, y; end; end
  class Bounds2d; attr_reader :a; def initialize(*a); @a = a; end; end
  class Point3d; def initialize(*a); end; end
  class Transformation; end
end
class Numeric; def to_mm; self; end; end
class Rec
  def self.const_missing(n); n; end
  attr_reader :args
  def initialize(*a); @args = a; @h = {}; end
  def method_missing(n, *x)
    s = n.to_s
    if s.end_with?('=') then @h[s.chomp('=')] = x[0]
    elsif @h.key?(s) then @h[s]
    else Rec.new
    end
  end
  def respond_to_missing?(*); true; end
end
module Layout
  def self.const_missing(n); n; end
  %w[Path FormattedText LinearDimension Group SketchUpModel Rectangle Image].each { |c| const_set(c, Class.new(Rec)) }
  const_set(:Style, Module.new { def self.const_missing(n); n; end })
  Document = Module.new { def self.const_missing(n); n; end }
end
require_relative '../kabinet/output/group_projection'
require_relative '../kabinet/output/sheet_layout'
require_relative '../kabinet/output/furniture_sheet'
def assert(v, m); raise m unless v; end
L = Kabinet::Output::SheetLayout
Page = Struct.new(:entities)
Doc = Struct.new(:pages) do
  def add_entity(e, _layer, page); page.entities << e; end
  def layers; [:layer]; end
end

def box_segments(w, h)
  [[[0, 0, 0], [w, 0, h]], [[0, 0, h], [w, 0, h]]].map { |p, q| [[p[0], 0, p[2]], [q[0], 0, q[2]]] }
end

[[600, 550, 720], [3600, 650, 900], [2740, 600, 2300], [20000, 600, 2400]].each do |size|
  w, d, h = size
  # 가구 외곽 + 가운데 선반선으로 구성한 단순 투영 선분(로컬 x 폭, y 깊이(뒤+), z 높이)
  edges = [[[0, 0, 0], [w, 0, 0]], [[w, 0, 0], [w, 0, h]], [[w, 0, h], [0, 0, h]], [[0, 0, h], [0, 0, 0]],
           [[0, d, 0], [w, d, 0]], [[0, 0, h / 2.0], [w, 0, h / 2.0]], [[0, 0, 0], [0, d, 0]], [[w, 0, 0], [w, d, 0]], [[w, d, 0], [w, d, h]]]
  vis = { visible: edges, hidden: [[[w / 3.0, d / 2, 0], [w / 3.0, d / 2, h]]] }
  data = {
    size: size.map(&:to_f), lo: [0.0, 0.0, 0.0], internal: true, materials: [], skp: 'x', snapshot_corners: [],
    views: { 'front' => vis, 'top' => vis, 'side' => vis, 'side_left' => vis },
    boxes: [[[0, 0, 0], [w, d, h]], [[w / 2.0, 0, 0], [w, d, h / 2.0]]],
    tiers: { doors: [[0.0, w / 2.0], [w / 2.0, w.to_f]], bodies: [[0.0, 18.0], [w - 18.0, w.to_f]] }
  }
  plan = L.plan(size, 'pages' => %w[front side])
  assert L.problems(plan).empty?, "#{size}: #{L.problems(plan)}"
  plan[:pages].each do |pg|
    page = Page.new([])
    doc = Doc.new([page])
    canvas = Kabinet::Output::PageCanvas.new(page, :layer)
    canvas.draw_page(doc, data, pg, plan, '가구 도면', 'site' => '', 'author' => '홍길동', 'surface_left' => 'open', 'surface_back' => 'wall')
    texts = page.entities.select { |e| e.is_a?(Layout::FormattedText) }.map { |e| e.args[0] }
    assert texts.any? { |t| t.include?("SCALE #{L.scale_label(pg[:scale])}") }, "#{size} 쪽#{pg[:number]}: SCALE 표기 없음"
    assert texts.any? { |t| t.include?('광교호수공원로 80') }, '현장정보 기본값'
    assert texts.any? { |t| t == "#{pg[:number]} / #{pg[:total]}" }, '쪽 번호'
    texts.each do |t|
      t.each_char { |ch| ch.encode(Encoding::CP949) rescue assert(false, "깨질 문자 U+#{ch.ord.to_s(16)} in #{t}") }
    end
    paths = page.entities.select { |e| e.is_a?(Layout::Path) }
    assert !paths.empty?, "#{size} 쪽#{pg[:number]}: 선 없음"
    paths.each do |e|
      e.args.each do |pt|
        next unless pt.respond_to?(:x) && pt.x.is_a?(Numeric)
        assert pt.x >= -1e-6 && pt.x <= 420.0 / 25.4 + 1e-6 && pt.y >= -1e-6 && pt.y <= 297.0 / 25.4 + 1e-6, "#{size}: 선이 용지 밖 #{pt.x * 25.4},#{pt.y * 25.4}"
      end
    end
    dims = page.entities.select { |e| e.is_a?(Layout::LinearDimension) }
    assert !dims.empty?, "#{size} 쪽#{pg[:number]}: 치수 없음"
  end
end

# ── 장별 세부 쪽: 가짜 장 데이터로 끝까지 그려 본다 ──
def unit_views(w, d, h)
  edges = [[[0, 0, 0], [w, 0, 0]], [[w, 0, 0], [w, 0, h]], [[w, 0, h], [0, 0, h]], [[0, 0, h], [0, 0, 0]],
           [[0, d, 0], [w, d, 0]], [[0, 0, h / 2.0], [w, 0, h / 2.0]], [[0, 0, 0], [0, d, 0]], [[w, 0, 0], [w, d, 0]], [[w, d, 0], [w, d, h]]]
  vis = { visible: edges, hidden: [[[w / 3.0, d / 2, 0], [w / 3.0, d / 2, h]]] }
  { 'u_front' => vis, 'u_inner' => vis, 'u_top' => vis, 'u_section' => vis }
end
unit_sizes = [[800.0, 580.0, 720.0], [600.0, 580.0, 720.0], [450.0, 600.0, 2100.0]]
udata = {
  size: [3600.0, 650.0, 900.0], lo: [0.0, 0.0, 0.0], internal: true, materials: [], skp: 'x', snapshot_corners: [], views: {}, boxes: [], tiers: { doors: [], bodies: [] },
  units: unit_sizes.each_with_index.map do |sz, i|
    parts = [{ role: 'side_left', dims: [sz[2], sz[1], 18.0] }, { role: 'side_right', dims: [sz[2], sz[1], 18.0] }, { role: 'bottom', dims: [sz[0] - 36, sz[1], 18.0] }]
    { index: i, name: "장 #{i + 1} (M#{i + 1})", size: sz, lo: [0.0, 0.0, 0.0], lo_abs: [i * 900.0, 0.0, 0.0], views: unit_views(*sz),
      boxes: [[[0, 0, 0], sz], [[0, 0, 0], [sz[0], sz[1], sz[2] / 2]]], parts: parts, info: { name: "장 #{i + 1} (M#{i + 1})", size: sz, index: i, parts: parts } }
  end
}
uplan = L.plan(udata[:size], 'pages' => %w[iso], 'units' => udata[:units].map { |u| { index: u[:index], name: u[:name], size: u[:size] } })
assert L.problems(uplan).empty?, "units plan: #{L.problems(uplan)}"
uplan[:pages].select { |pg| pg[:id] == 'unit' }.each do |pg|
  page = Page.new([])
  doc = Doc.new([page])
  canvas = Kabinet::Output::PageCanvas.new(page, :layer)
  canvas.draw_page(doc, Kabinet::Output::FurnitureSheet.unit_data(udata, pg[:unit]), pg, uplan, '가구 도면', 'site' => '')
  texts = page.entities.select { |e| e.is_a?(Layout::FormattedText) }.map { |e| e.args[0] }
  assert texts.any? { |t| t.include?('SCALE ' + L.scale_label(pg[:scale])) }, '장 쪽 SCALE 표기'
  assert texts.any? { |t| t.include?('내경(= 외곽 - 36)') }, '장 표 내경'
  assert texts.any? { |t| t.include?('장 표') }, '장 표 제목'
  assert texts.any? { |t| t.include?("#{pg[:number]} / #{pg[:total]}") }, '쪽 번호'
  assert texts.count { |t| t == '전면' } == 2, "전면 표시(평면·단면) #{texts.count { |t| t == '전면' }}"
  assert page.entities.count { |e| e.is_a?(Layout::LinearDimension) } >= 8, '장 쪽 치수'
  texts.each { |t| t.each_char { |ch| ch.encode(Encoding::CP949) rescue assert(false, "깨질 문자 U+#{ch.ord.to_s(16)}") } }
end
puts 'furniture_sheet_draw_test: OK'
