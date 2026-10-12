# frozen_string_literal: false
# 창 정면도 미리보기: 실제 생성 코드(Assembly)로 만든 형상을 정면 투영 — 전체 폭/높이가 실제 모델과 일치
require 'json'
require_relative 'support/geom'
module Kabinet; end
%w[constants core/gaps persistence/attributes persistence/schema geometry/transforms geometry/builder
   geometry/joinery geometry/handle_builder core/fitting core/panel core/carcase
   core/door_panel core/ep_finish_panel core/accessory core/shelf_module core/drawer_module
   core/desk_module core/assembly geometry/preview_entities].each { |f| require_relative "../kabinet/#{f}" }
module Kabinet; module UI; module Dialog; module_function; end; end; end
src = File.read(File.join(__dir__, '../kabinet/ui/dialog.rb'), encoding: 'UTF-8')
Kabinet::UI::Dialog.module_eval(src[/      def front_projection.*?\n      end\n/m])
Kabinet::UI::Dialog.send(:module_function, :front_projection)
def assert(v, m); raise m unless v; end

# 주방 하부장 900 · 받침 80 · 몸통 740 · 상판 20 (스크린샷과 같은 구성)
spec = { 'width' => 900, 'max_depth' => 580, 'base_height' => 80, 'ep' => { 'left' => false, 'right' => false },
         'top_panel' => { 'thickness' => 20 },
         'modules' => [{ 'kind' => 'shelf_module', 'width' => 900, 'depth' => 580, 'height' => 740,
                         'door_config' => 'pair', 'handle_type' => 'bar', 'shelves' => [{ 'height_from_bottom' => 300 }] }] }
r = Kabinet::UI::Dialog.front_projection(spec)
w = r[:max][0] - r[:min][0]
h = r[:max][1] - r[:min][1]
assert (w - 900).abs < 1, "width #{w}"
assert (h - 840).abs < 1, "height #{h}"
assert r[:segs].any? { |s| s[4] == 1 } && r[:segs].any? { |s| s[4] == 0 }, 'front + internal lines'
assert r[:segs].all? { |s| s.size == 5 }, 'segment shape'
assert JSON.generate(r).size < 200_000, 'payload size'
puts "front_projection_test: OK (#{r[:segs].size} segs)"

# 도어 간격(door_gaps)이 실제 형상에 반영되는지: 바깥 간격 10 → 도어 왼쪽 끝 x=10, 위 간격 10 → 도어 윗끝 내려감
fronts = ->(sp) { Kabinet::UI::Dialog.front_projection(sp)[:segs].select { |s| s[4] == 1 } }
f0 = fronts.(spec)
f1 = fronts.(spec.merge('door_gaps' => { 'outside' => 10, 'top' => 10 }))
minx = ->(f) { f.flat_map { |s| [s[0], s[2]] }.min }
maxz = ->(f) { f.flat_map { |s| [s[1], s[3]] }.max }
assert (minx.(f1) - minx.(f0) - 8).abs < 0.6, "outside gap #{minx.(f0)} → #{minx.(f1)}"
assert (maxz.(f0) - maxz.(f1) - 8).abs < 0.6, "top gap #{maxz.(f0)} → #{maxz.(f1)}"
puts 'front_projection_test: door_gaps OK'

# 내부 서랍: 도어 안쪽(점선)으로 생기고 외곽 크기는 그대로
ward = { 'width' => 900, 'max_depth' => 580, 'base_height' => 50, 'ep' => { 'left' => true, 'right' => true },
         'top_panel' => { 'thickness' => 18 },
         'modules' => [{ 'kind' => 'shelf_module', 'width' => 860, 'depth' => 580, 'height' => 2232,
                         'door_config' => 'pair', 'handle_type' => 'push_open', 'shelves' => [] }] }
plain = Kabinet::UI::Dialog.front_projection(ward)
withd = Kabinet::UI::Dialog.front_projection(
  ward.merge('modules' => [ward['modules'][0].merge('inner_drawers' => { 'bottom' => 60, 'count' => 3, 'height' => 180 })]))
assert withd[:max] == plain[:max] && withd[:min] == plain[:min], 'outer size unchanged'
inner = withd[:segs].select { |s| s[4] == 0 }.size - plain[:segs].select { |s| s[4] == 0 }.size
assert inner > 12, "inner drawer lines drawn as hidden (#{inner})"
assert withd[:segs].select { |s| s[4] == 1 }.size == plain[:segs].select { |s| s[4] == 1 }.size, 'doors unchanged'
puts 'front_projection_test: inner drawers OK'

# 걸레받이(받침 80)가 바깥 부재(실선, 2)로 그려짐: 바닥(z=0~80) 근처 실선 존재
kick = r[:segs].select { |s| s[4] == 2 && [s[1], s[3]].max <= 81 }
assert !kick.empty?, 'kickboard drawn as solid outer line'
puts 'front_projection_test: kickboard OK'
