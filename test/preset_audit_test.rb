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

out, err, st = Open3.capture3('node', File.join(__dir__, 'export_furniture_presets.js'), '/dev/stdout')
raise "node failed: #{err}" unless st.success?
presets = JSON.parse(out)
expect = { 'wardrobe' => [900, 2300], 'kitchen_base' => [900, 880] }
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
