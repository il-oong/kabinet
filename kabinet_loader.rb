require 'sketchup.rb'
require 'extensions.rb'

module Kabinet
  PLUGIN_ROOT = File.dirname(__FILE__)
  PLUGIN_DIR  = File.join(PLUGIN_ROOT, 'kabinet')

  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Kabinet — EP 판재 · 도면', File.join('kabinet', 'ep_main'))
    ext.creator     = 'Kabinet'
    ext.version     = '2.0.0'
    ext.copyright   = '2026'
    ext.description = 'EP 판재를 한 장씩 만들고, 직접 조합한 가구를 A3 LayOut/PDF 도면으로 출력합니다.'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
