# frozen_string_literal: false
# 가구 공통사항: Ruby 적용 규칙 + 웹 창(app.js applyCommon)과 결과 일치 (전체 프리셋)
require 'json'
require 'open3'
module Kabinet; end
require_relative '../kabinet/core/common'
C = Kabinet::Core::Common
def assert(v, m); raise m unless v; end

common = { 'body_thickness' => '15', 'door_thickness' => 22, 'shelf_thickness' => 20, 'material' => 'PET',
           'door_material' => 'acrylic', 'handle_type' => 'push_open', 'ep_thickness' => 18, 'back_thickness' => '',
           'bogus' => 1 }
assert C.clean(common).keys.sort == %w[body_thickness door_material door_thickness ep_thickness handle_type material shelf_thickness],
       "clean #{C.clean(common)}"

spec = { 'material' => 'LPM', 'ep' => { 'left' => true, 'thickness' => 20 },
         'modules' => [{ 'kind' => 'shelf_module', 'body_thickness' => 18, 'back_thickness' => 9, 'door_thickness' => 20,
                         'shelves' => [{ 'thickness' => 18 }], 'vertical_dividers' => [{ 'x' => 300, 'thickness' => 18 }] },
                       { 'kind' => 'drawer_module', 'drawer_thickness' => 20 }, { 'kind' => 'bed_gap', 'width' => 1000 }] }
out = C.apply(spec, common)
m0, m1, gap = out['modules']
assert m0['body_thickness'] == 15.0 && m0['back_thickness'] == 9 && m0['door_thickness'] == 22.0, 'thickness'
assert m0['shelves'][0]['thickness'] == 20.0 && m0['vertical_dividers'][0]['thickness'] == 20.0, 'shelf'
assert m1['drawer_thickness'] == 22.0 && m1['handle_type'] == 'push_open', 'drawer'
assert !gap.key?('material'), 'gap untouched'
assert out['ep'] == { 'left' => true, 'thickness' => 18.0 } && out['material'] == 'PET', 'ep/material'
assert spec['modules'][0]['body_thickness'] == 18, 'input not mutated'
assert C.apply(spec, {}) == spec, 'empty common = no change'

# 웹 창과 같은 결과인지: 모든 기본 프리셋에 같은 공통값을 적용해 비교
js = <<~JS
  const fs=require('fs'),vm=require('vm');
  const ctx=vm.createContext({document:{addEventListener(){}}});
  vm.runInContext(fs.readFileSync(#{File.join(__dir__, '../kabinet/ui/web/app.js').to_json},'utf8'),ctx);
  const c=#{JSON.generate(common)};
  const r=vm.runInContext('Object.fromEntries(Object.entries(FURNITURE_PRESETS).map(([k,p])=>[k,[p,kabinet.applyCommon(p,'+JSON.stringify(c)+')]]))',ctx);
  process.stdout.write(JSON.stringify(r));
JS
stdout, err, st = Open3.capture3('node', '-e', js)
raise "node failed: #{err}" unless st.success?
pairs = JSON.parse(stdout)
norm = ->(h) { JSON.parse(JSON.generate(h)) { |x| x } }
num = ->(o) { o.is_a?(Hash) ? o.transform_values { |v| num.(v) } : o.is_a?(Array) ? o.map { |v| num.(v) } : (o.is_a?(Numeric) ? o.to_f : o) }
pairs.each do |key, (preset, js_out)|
  rb = C.apply(preset, common)
  raise "mismatch #{key}" unless num.(norm.(rb)) == num.(js_out)
end
puts "common_test: OK (#{pairs.size} presets match)"
