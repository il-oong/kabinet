# frozen_string_literal: false
# 도면 치수표 → 가구 spec: 프리셋 구조 + 치수 덮어쓰기가 실제 생성 형상(폭/높이/깊이)과 일치
require 'json'
require 'open3'
require_relative 'support/geom'
module Kabinet; end
%w[constants core/gaps persistence/attributes persistence/schema geometry/transforms geometry/builder
   geometry/joinery geometry/handle_builder core/fitting core/panel core/carcase
   core/door_panel core/ep_finish_panel core/accessory core/shelf_module core/drawer_module
   core/desk_module core/assembly core/validation geometry/preview_entities].each { |f| require_relative "../kabinet/#{f}" }
require_relative '../kabinet/commands/drawing_import'
module Kabinet; module UI; module Dialog; module_function; end; end; end
src = File.read(File.join(__dir__, '../kabinet/ui/dialog.rb'), encoding: 'UTF-8')
Kabinet::UI::Dialog.module_eval(src[/      def front_projection.*?\n      end\n/m])
Kabinet::UI::Dialog.send(:module_function, :front_projection)
def assert(v, m); raise m unless v; end

rows = [
  { preset: 'otondo_tall', width: 1082, height: 2550, depth: 600, thickness: 18 },
  { preset: 'otondo_tall', width: 1200, height: 2400, depth: 550, thickness: 18 },   # 도면 값과 다르게 변경
  { preset: 'wardrobe', width: 1000, height: 2400, depth: 580, thickness: 18 },
  { preset: 'otondo_desk', width: 1768, height: 720, depth: 600, thickness: 18 },
  { preset: 'otondo_upper_pair', width: 1120, height: 971, depth: 350, thickness: 18 },
  { preset: 'otondo_low_open', width: 1182, height: 700, depth: 400, thickness: 18 },
  { preset: 'drawer_tower', width: 500, height: 900, depth: 450, thickness: 18, drawers: 3 },
  { preset: 'kitchen_upper', width: 800, height: 700, depth: 320, thickness: 18, doors: 'single', extra_h: 20 }   # 도어 하부 내림 20 은 형상 높이에 더해짐
]
js = <<~JS
  const fs=require('fs'),vm=require('vm');
  const el=()=>new Proxy(function(){}, {get:(t,k)=>k==='style'?{}:k==='classList'?{add(){},remove(){},toggle(){}}:k==='querySelectorAll'?(()=>[]):k==='querySelector'?(()=>null):(typeof k==='symbol'?undefined:(()=>el())), set:()=>true, apply:()=>el()});
  const doc={addEventListener(){},getElementById:()=>null,querySelectorAll:()=>[],querySelector:()=>null,createElement:()=>el()};
  const ctx=vm.createContext({document:doc,window:{},localStorage:{getItem(){return null},setItem(){}},console});
  vm.runInContext('function renderModuleList(){}',ctx);
  vm.runInContext(fs.readFileSync(#{File.join(__dir__, '../kabinet/ui/web/app.js').to_json},'utf8'),ctx);
  const rows=#{JSON.generate(rows)};
  const out=rows.map(r=>vm.runInContext('kabinet.buildDrawingSpec('+JSON.stringify(r)+')',ctx));
  process.stdout.write(JSON.stringify(out));
JS
stdout, err, st = Open3.capture3('node', '-e', js)
raise "node failed: #{err}" unless st.success?
results = JSON.parse(stdout)
results.each_with_index do |res, i|
  r = rows[i]
  assert res['error'].nil?, "row #{i} #{r[:preset]}: #{res['error']}"
  spec = res['spec']
  n = Kabinet::Persistence::Schema.normalize(spec)
  Kabinet::Persistence::Schema.validate!(n)
  p = Kabinet::UI::Dialog.front_projection(spec)
  w = (p[:max][0] - p[:min][0]).round
  h = (p[:max][1] - p[:min][1]).round
  assert (w - r[:width]).abs <= 1, "row #{i} #{r[:preset]} width #{w} != #{r[:width]}"
  assert (h - r[:height] - r.fetch(:extra_h, 0)).abs <= 2, "row #{i} #{r[:preset]} height #{h} != #{r[:height]}"
  assert spec['max_depth'].to_f == r[:depth].to_f, "row #{i} depth #{spec['max_depth']}"
end
drawers = results[6]['spec']['modules'].find { |m| m['kind'] == 'drawer_module' }
assert drawers['drawer_count'] == 3, 'drawer count override'
door = results[7]['spec']['modules'].find { |m| m['kind'] == 'shelf_module' }
assert door['door_config'] == 'single', 'door override'

# 배치 변환: 숫자 파싱
D = Kabinet::Commands::DrawingImport
assert D.placement({ 'x' => 1082, 'y' => '900', 'z' => 1579, 'rot' => nil }) == [1082.0, 900.0, 1579.0, 0.0], 'placement'
puts "drawing_import_test: OK (#{results.size} rows)"
