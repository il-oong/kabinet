require 'sketchup.rb'
require 'json'

module Kabinet
  PLUGIN_DIR = File.dirname(__FILE__) unless defined?(PLUGIN_DIR)
end

# Foundation
require File.join(Kabinet::PLUGIN_DIR, 'version')
require File.join(Kabinet::PLUGIN_DIR, 'constants')

# Persistence + geometry primitives
require File.join(Kabinet::PLUGIN_DIR, 'persistence', 'attributes')
require File.join(Kabinet::PLUGIN_DIR, 'persistence', 'schema')
require File.join(Kabinet::PLUGIN_DIR, 'geometry', 'transforms')
require File.join(Kabinet::PLUGIN_DIR, 'geometry', 'builder')
require File.join(Kabinet::PLUGIN_DIR, 'geometry', 'joinery')

# Domain
require File.join(Kabinet::PLUGIN_DIR, 'core', 'panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'carcase')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'door_panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'ep_finish_panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'accessory')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'shelf_module')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'drawer_module')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'assembly')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'cut_list')

# Commands
require File.join(Kabinet::PLUGIN_DIR, 'commands', 'generate')
require File.join(Kabinet::PLUGIN_DIR, 'commands', 'regenerate')
require File.join(Kabinet::PLUGIN_DIR, 'commands', 'export')

# Output (drawings)
require File.join(Kabinet::PLUGIN_DIR, 'output', 'dimensions')
require File.join(Kabinet::PLUGIN_DIR, 'output', 'views')
require File.join(Kabinet::PLUGIN_DIR, 'output', 'png_export')
require File.join(Kabinet::PLUGIN_DIR, 'output', 'pdf_bundler')

# UI (last — depends on everything)
require File.join(Kabinet::PLUGIN_DIR, 'ui', 'dialog')
require File.join(Kabinet::PLUGIN_DIR, 'ui', 'menu')

module Kabinet
  unless file_loaded?(__FILE__)
    Kabinet::UI::Menu.install
    file_loaded(__FILE__)
  end

  # ── 개발자용 핫 리로드 ──────────────────────────────────────────────────
  # 루비 콘솔에서: Kabinet.reload!
  # 또는 메뉴: Extensions > Kabinet > 다시 로드
  #
  # JS/HTML/CSS 변경분은 다이얼로그를 닫고 다시 열면 자동 반영됩니다.
  def self.reload!
    files = [
      'version', 'constants',
      'persistence/attributes', 'persistence/schema',
      'geometry/transforms', 'geometry/builder', 'geometry/joinery',
      'core/panel', 'core/carcase', 'core/door_panel',
      'core/ep_finish_panel', 'core/accessory',
      'core/shelf_module', 'core/drawer_module',
      'core/assembly', 'core/cut_list',
      'commands/generate', 'commands/regenerate', 'commands/export',
      'output/dimensions', 'output/views',
      'output/png_export', 'output/pdf_bundler',
      'ui/dialog', 'ui/menu'
    ]

    errors = []
    files.each do |rel|
      path = File.join(PLUGIN_DIR, rel + '.rb')
      begin
        load path
      rescue StandardError => e
        errors << "#{rel}: #{e.message}"
      end
    end

    # 다이얼로그가 열려있으면 닫기 (JS/HTML 변경 반영을 위해)
    begin
      if Kabinet::UI::Dialog.instance_variable_get(:@dialog)&.visible?
        Kabinet::UI::Dialog.instance_variable_get(:@dialog).close
        puts 'Kabinet: 다이얼로그를 닫았습니다. Extensions > Kabinet > 열기로 다시 여세요.'
      end
    rescue StandardError
      # 무시
    end

    if errors.empty?
      puts "Kabinet: #{files.size}개 파일 다시 로드 완료."
    else
      puts "Kabinet: 리로드 완료 (오류 #{errors.size}건):"
      errors.each { |e| puts "  - #{e}" }
    end
    errors.empty?
  end
end
