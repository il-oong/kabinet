require 'sketchup.rb'
require 'json'
require_relative 'core/ep_board'
require_relative 'core/furniture_library'
require_relative 'output/group_projection'
require_relative 'output/furniture_sheet'
require_relative 'output/space_sheet'
require_relative 'ui/ep_dialog'

module Kabinet
  unless file_loaded?(__FILE__)
    menu = ::UI.menu('Extensions').add_submenu('Kabinet — EP 판재 · 도면')
    menu.add_item('EP 한 장 만들기…') { EPDialog.show }
    menu.add_item('선택 가구 도면 출력…') { EPDialog.show }
    file_loaded(__FILE__)
  end
end
