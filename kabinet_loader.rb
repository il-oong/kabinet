require 'sketchup.rb'
require 'extensions.rb'

module Kabinet
  PLUGIN_ROOT = File.dirname(__FILE__)
  PLUGIN_DIR  = File.join(PLUGIN_ROOT, 'kabinet')

  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Kabinet — 카케이스 생성기', File.join('kabinet', 'main'))
    ext.creator     = 'Kabinet'
    ext.version     = '0.1.0'
    ext.copyright   = '2026'
    ext.description = '파라메트릭 카케이스 가구(붙박이장/주방가구/화장대) 생성기. ' \
                      '판 두께를 보존하면서 모듈을 적층하고 도면을 PNG/PDF로 출력합니다.'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
