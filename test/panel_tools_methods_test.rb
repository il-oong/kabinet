# frozen_string_literal: false
# 도구 클래스가 자기 안에서 호출하는 메서드를 실제로 가지고 있는지 (ask_settings 누락 회귀 방지)
require_relative 'support/geom'
module Sketchup; class Color; def initialize(*); end; end; end
module Kabinet; end
require_relative '../kabinet/ui/panel_tools'
def assert(v, m); raise m unless v; end
src = File.read(File.join(__dir__, '../kabinet/ui/panel_tools.rb'), encoding: 'UTF-8')
{ Kabinet::UI::FacePanelTool => src[/class FacePanelTool.*?(?=\n    class |\z)/m],
  Kabinet::UI::SpaceDivideTool => src[/class SpaceDivideTool.*/m] }.each do |klass, body|
  defined_here = body.scan(/^\s+def ([a-z_?=!]+)/).flatten
  called = body.scan(/(?:^|[\s(!])((?:ask|set|update|cycle|save|pref|draw|preview|face|current)_[a-z_]+)\b(?!:)/).flatten.uniq
  missing = called - defined_here - %w[draw_text draw_box]
  missing.reject! { |m| klass.private_method_defined?(m) || klass.method_defined?(m) }
  assert missing.empty?, "#{klass}: 정의 안 된 메서드 호출 #{missing}"
end
assert Kabinet::UI::SpaceDivideTool.private_method_defined?(:ask_settings), 'SpaceDivideTool#ask_settings'
assert !Kabinet::UI::FacePanelTool.private_method_defined?(:ask_settings), 'ask_settings는 공간 분할 도구 전용'
puts 'panel_tools_methods_test: OK'
