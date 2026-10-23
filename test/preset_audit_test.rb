# frozen_string_literal: false
# 전체 프리셋: Schema 검증 + Assembly 빌드 + 치수 실측(붙박이장 900x2300, 주방 하부장 900x830)
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
expect = { 'wardrobe' => [900, 2300], 'kitchen_base' => [900, 830],
           # 도면(오톤도 30X33) 가구: 도면 치수 그대로
           'otondo_tall' => [1082, 2550], 'otondo_upper_pair' => [1120, 971], 'otondo_upper_single' => [560, 971],
           'otondo_desk' => [1768, 720], 'otondo_low_open' => [1182, 700], 'otondo_low_drawer' => [750, 270] }
expect.each_key { |k| assert presets.key?(k), "missing preset #{k}" }
presets.each do |k, spec|
  n = Kabinet::Persistence::Schema.normalize(spec)
  Kabinet::Persistence::Schema.validate!(n)
  Kabinet::Core::Validation.warnings(n)
  r = Kabinet::UI::Dialog.front_projection(spec)
  w = (r[:max][0] - r[:min][0]).round
  h = (r[:max][1] - r[:min][1]).round
  assert w == expect[k][0] && h == expect[k][1], "#{k} #{w}x#{h}" if expect[k]
  next unless k.start_with?('otondo_')
  # 도면 가구는 판재 전부 18T (뒷판만 9T)
  ths = []
  spec['modules'].each do |m|
    %w[body_thickness door_thickness drawer_thickness top_thickness].each { |f| ths << m[f] if m[f] }
    (m['shelves'] || []).each { |sh| ths << sh['thickness'] }
    (m['vertical_dividers'] || []).each { |dv| ths << dv['thickness'] }
  end
  ths << spec['top_panel']['thickness'] if spec['top_panel']
  assert ths.all? { |t| t == 18 }, "#{k} thickness #{ths.uniq}"
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

# 판재는 전부 각각 그룹: 면(Face)을 직접 가진 그룹은 하위 그룹을 가지지 않는다 (한 덩어리로 뭉친 그룹 없음)
S = Kabinet::Geometry::Preview
presets.each do |k, spec|
  next unless k.start_with?('otondo_')
  norm = Kabinet::Persistence::Schema.normalize(spec)
  root = Kabinet::Core::Assembly.from_hash(norm).build(S::Entities.new)
  lumps = []
  walk = lambda do |g, path|
    faces  = g.entities.items.count { |i| i.is_a?(S::Face) }
    groups = g.entities.items.select { |i| i.is_a?(S::Group) }
    lumps << path if faces.positive? && groups.any?
    groups.each { |c| walk.call(c, "#{path}/#{Kabinet::Persistence::Attributes.role(c) || c.name}") }
  end
  walk.call(root, k)
  assert lumps.empty?, "#{k} 뭉친 그룹: #{lumps.first(3)}"
end
puts 'preset_audit_test: panels each in own group OK'
