# frozen_string_literal: false
# 모서리 R: 책상 상판 / 상판(top_panel) — 둥근 모서리 판 생성, R=0이면 직각 박스와 동일
require 'json'
require_relative 'support/geom'
module Kabinet; end
%w[constants core/gaps persistence/attributes persistence/schema geometry/transforms geometry/builder
   geometry/joinery geometry/handle_builder core/fitting core/panel core/carcase
   core/door_panel core/ep_finish_panel core/accessory core/shelf_module core/drawer_module
   core/desk_module core/assembly geometry/preview_entities].each { |f| require_relative "../kabinet/#{f}" }
def assert(v, m); raise m unless v; end
E = Kabinet::Geometry::Preview::Entities
B = Kabinet::Geometry::Builder

# R=0 → 4점 직각 박스, R>0 앞 두 모서리 → 점이 늘고 외곽 크기는 그대로
sq = E.new; B.rounded_box(sq, 1000.0, 600.0, 25.0, nil, radius: 0, corners: %w[fl fr])
rd = E.new; B.rounded_box(rd, 1000.0, 600.0, 25.0, nil, radius: 100.0, corners: %w[fl fr])
fsq = sq.items.first.entities.items.first
frd = rd.items.first.entities.items.first
assert fsq.points.size == 4, 'square 4 pts'
assert frd.points.size == 2 * (B::ROUND_SEGMENTS + 1) + 2, "rounded pts #{frd.points.size}"
xs = frd.points.map(&:x); ys = frd.points.map(&:y)
assert (xs.max - xs.min - 1000).abs < 1e-6 && (ys.max - ys.min - 600).abs < 1e-6, 'extent kept'
assert frd.distance == 25.0, 'thickness'
# 모서리 반경은 짧은 변 절반을 넘지 않음
big = E.new; B.rounded_box(big, 1000.0, 200.0, 25.0, nil, radius: 500.0, corners: %w[fl])
bp = big.items.first.entities.items.first.points
assert bp.map(&:y).min >= -1e-6 && bp.map(&:x).min >= -1e-6, 'radius clamped'

# 책상: top_radius가 책상 상판에 적용되고 전체 크기는 그대로
spec = { 'width' => 1768, 'max_depth' => 600, 'base_height' => 0, 'ep' => { 'left' => false, 'right' => false },
         'top_panel' => nil,
         'modules' => [{ 'kind' => 'desk_module', 'width' => 1768, 'depth' => 600, 'height' => 720,
                         'top_thickness' => 18, 'top_radius' => 100, 'top_round_corners' => 'fl' }] }
norm = Kabinet::Persistence::Schema.normalize(spec)
root = Kabinet::Core::Assembly.from_hash(norm).build(E.new)
pts = []
walk = ->(ents) { ents.items.each { |i| i.respond_to?(:entities) ? walk.(i.entities) : (pts << i.points.size if i.respond_to?(:points)) } }
walk.(root.entities)
assert pts.any? { |n| n > 8 }, 'desk top rounded polygon present'
puts 'rounded_corner_test: OK'
