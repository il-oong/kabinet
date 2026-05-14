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
require File.join(Kabinet::PLUGIN_DIR, 'geometry', 'handle_builder')

# Domain
require File.join(Kabinet::PLUGIN_DIR, 'core', 'panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'carcase')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'door_panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'ep_finish_panel')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'accessory')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'shelf_module')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'drawer_module')
require File.join(Kabinet::PLUGIN_DIR, 'core', 'desk_module')
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

  # ── 로컬 소스 → 설치 폴더 동기화 + 핫 리로드 ──────────────────────────
  # 루비 콘솔에서: Kabinet.update!
  #
  # 개발 소스 폴더의 모든 .rb / 웹 파일을 설치된 Plugins 폴더로 복사한 뒤
  # reload! 를 호출합니다. .rbz 재설치 불필요.
  #
  # 소스 폴더가 다르면: Kabinet.update!(src: 'D:/my/kabinet')
  SOURCE_DIR = 'C:/Users/testos/Desktop/개인/스케치업 루비'.freeze unless defined?(SOURCE_DIR)

  def self.update!(src: SOURCE_DIR)
    require 'fileutils'

    src_root = File.join(src, 'kabinet')
    dst_root = PLUGIN_DIR   # 설치된 kabinet/ 폴더

    unless Dir.exist?(src_root)
      puts "Kabinet.update! 오류: 소스 폴더가 없습니다 → #{src_root}"
      return false
    end

    all_files = %w[
      main.rb version.rb constants.rb
      persistence/attributes.rb persistence/schema.rb
      geometry/transforms.rb geometry/builder.rb
      geometry/joinery.rb geometry/handle_builder.rb
      core/panel.rb core/carcase.rb core/door_panel.rb
      core/ep_finish_panel.rb core/accessory.rb
      core/shelf_module.rb core/drawer_module.rb
      core/desk_module.rb core/assembly.rb core/cut_list.rb
      commands/generate.rb commands/regenerate.rb commands/export.rb
      output/dimensions.rb output/views.rb
      output/png_export.rb output/pdf_bundler.rb
      ui/dialog.rb ui/menu.rb
      ui/web/index.html ui/web/app.js
      ui/web/modules.js ui/web/styles.css
    ]

    puts "Kabinet.update! — #{src_root} → #{dst_root}"
    copied = 0; errors = []

    all_files.each do |rel|
      from = File.join(src_root, rel)
      to   = File.join(dst_root, rel)
      unless File.exist?(from)
        puts "  건너뜀 (없음): #{rel}"
        next
      end
      begin
        FileUtils.mkdir_p(File.dirname(to))
        FileUtils.cp(from, to)
        puts "  ✓ #{rel}"
        copied += 1
      rescue => e
        puts "  ✗ #{rel}: #{e.message}"
        errors << rel
      end
    end

    puts "#{copied}개 복사 완료#{errors.empty? ? '' : ", 실패 #{errors.size}건"}."
    reload! if copied > 0
    errors.empty?
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
      'geometry/transforms', 'geometry/builder', 'geometry/joinery', 'geometry/handle_builder',
      'core/panel', 'core/carcase', 'core/door_panel',
      'core/ep_finish_panel', 'core/accessory',
      'core/shelf_module', 'core/drawer_module', 'core/desk_module',
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
