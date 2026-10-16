# frozen_string_literal: false
# 전체 프리셋: Schema 검증 + Assembly 빌드 + 치수 실측(붙박이장 900x2300, 주방 하부장 900x880)
require 'json'
require 'open3'
require_relative 'support/geom'
module Kabinet; end
%w[constants core/gaps persistence/attributes persistence/schema geometry/transforms geometry/builder
   geometry/joinery geometry/handle_builder core/fitting core/panel core/carcase
   core/door_panel core/ep_finish_panel core/accessory core/shelf_module core/drawer_module
   core/desk_module core/assembly core/validation geometry/preview_entities].each { |f| require_relative "../kabinet/#{f}" }
module Kabinet; module UI; module Dialog; module_function; end; end; end
src = File.read(File.join(__dir__, '../kabinet/ui/dialog.rb'), encoding: 'UTF-8')
Kabinet::UI::Dialog.module_eval(src[/      def front_projection.*?\n      end\n/m])
Kabinet::UI::Dialog.send(:module_function, :front_projection)
def assert(v, m); raise m unless v; end

js = <<~JS
  const fs=require('fs'),vm=require('vm');
  const ctx=vm.createContext({document:{addEventListener(){}}});
  vm.runInContext(fs.readFileSync(#{File.join(__dir__, '../kabinet/ui/web/app.js').to_json},'utf8'),ctx);
  process.stdout.write(vm.runInContext('JSON.stringify(FURNITURE_PRESETS)',ctx));
JS
out, err, st = Open3.capture3('node', '-e', js)
raise "node failed: #{err}" unless st.success?
presets = JSON.parse(out)
assert presets.size >= 12, "preset count #{presets.size}"
expect = { 'wardrobe' => [900, 2300], 'kitchen_base' => [900, 880] }
expect.each_key { |k| assert presets.key?(k), "missing preset #{k}" }
presets.each do |k, spec|
  n = Kabinet::Persistence::Schema.normalize(spec)
  Kabinet::Persistence::Schema.validate!(n)
  Kabinet::Core::Validation.warnings(n)
  r = Kabinet::UI::Dialog.front_projection(spec)
  w = (r[:max][0] - r[:min][0]).round
  h = (r[:max][1] - r[:min][1]).round
  assert w == expect[k][0] && h == expect[k][1], "#{k} #{w}x#{h}" if expect[k]
end
puts "preset_audit_test: OK (#{presets.size} presets)"

# 오픈장(도어 없음): EP 앞면이 도어 라인(도어 두께 + 간격)까지 나옴, align_door_line=false면 카케이스 앞면
F = Kabinet::Core::Fitting
open_mods = [{ 'kind' => 'shelf_module', 'door_config' => 'none', 'door_thickness' => 20 }]
off = Kabinet::Core::Gaps.front_offset.to_f
assert (F.front_protrusion_mm(open_mods) - (20 + off)).abs < 0.01, 'open cabinet EP at door line'
assert F.front_protrusion_mm(open_mods, align_open: false) == 0.0, 'opt-out'
assert F.front_protrusion_mm([{ 'kind' => 'shelf_module', 'door_config' => 'pair', 'door_thickness' => 22 }]) > 22, 'door unchanged'
puts 'preset_audit_test: open door-line OK'
