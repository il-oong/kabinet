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

  # ── GitHub 원클릭 업데이트 ─────────────────────────────────────────────
  # 루비 콘솔에서: Kabinet.update!
  # 또는 메뉴: Extensions > Kabinet > ⬆ 업데이트
  #
  # GitHub master 브랜치에서 모든 파일을 내려받아 Plugins 폴더에 덮어쓴 뒤
  # 자동으로 reload! 를 호출합니다. .rbz 재설치 불필요.
  def self.update!(branch: 'master')
    require 'net/http'
    require 'uri'
    require 'fileutils'
    require 'openssl'

    base_raw    = "https://raw.githubusercontent.com/il-oong/kabinet/#{branch}/"
    plugins_dir = Sketchup.find_support_file('Plugins')

    all_files = %w[
      kabinet_loader.rb
      kabinet/main.rb
      kabinet/version.rb
      kabinet/constants.rb
      kabinet/persistence/attributes.rb
      kabinet/persistence/schema.rb
      kabinet/geometry/transforms.rb
      kabinet/geometry/builder.rb
      kabinet/geometry/joinery.rb
      kabinet/core/panel.rb
      kabinet/core/carcase.rb
      kabinet/core/door_panel.rb
      kabinet/core/ep_finish_panel.rb
      kabinet/core/accessory.rb
      kabinet/core/shelf_module.rb
      kabinet/core/drawer_module.rb
      kabinet/core/assembly.rb
      kabinet/core/cut_list.rb
      kabinet/commands/generate.rb
      kabinet/commands/regenerate.rb
      kabinet/commands/export.rb
      kabinet/output/dimensions.rb
      kabinet/output/views.rb
      kabinet/output/png_export.rb
      kabinet/output/pdf_bundler.rb
      kabinet/ui/dialog.rb
      kabinet/ui/menu.rb
      kabinet/ui/web/index.html
      kabinet/ui/web/app.js
      kabinet/ui/web/modules.js
      kabinet/ui/web/styles.css
    ]

    puts "Kabinet: GitHub(#{branch})에서 업데이트 중..."
    updated = 0
    errors  = []

    all_files.each do |rel|
      url  = URI("#{base_raw}#{rel}")
      dest = File.join(plugins_dir, *rel.split('/'))

      begin
        FileUtils.mkdir_p(File.dirname(dest))
        body = _fetch_url(url)
        if body
          File.binwrite(dest, body)
          updated += 1
          puts "  ✓ #{rel}"
        else
          errors << rel
          puts "  ✗ #{rel}"
        end
      rescue StandardError => e
        errors << "#{rel}: #{e.message}"
        puts "  ✗ #{rel}: #{e.message}"
      end
    end

    puts "Kabinet: #{updated}/#{all_files.size}개 파일 갱신 완료."
    unless errors.empty?
      puts "  실패 #{errors.size}건:"
      errors.each { |e| puts "    - #{e}" }
    end

    reload! if updated > 0
    errors.empty?
  end

  # HTTP GET 헬퍼 (SSL 검증 실패 시 VERIFY_NONE 으로 재시도)
  def self._fetch_url(uri, redirect_limit: 5)
    return nil if redirect_limit <= 0

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = (uri.scheme == 'https')
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = 15
    http.read_timeout = 30

    begin
      response = http.get(uri.request_uri)
    rescue OpenSSL::SSL::SSLError
      # Windows 루트 인증서 문제 등 → 검증 없이 재시도
      http2 = Net::HTTP.new(uri.host, uri.port)
      http2.use_ssl     = true
      http2.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http2.open_timeout = 15
      http2.read_timeout = 30
      response = http2.get(uri.request_uri)
    end

    case response.code.to_i
    when 200
      response.body
    when 301, 302, 307, 308
      _fetch_url(URI(response['location']), redirect_limit: redirect_limit - 1)
    else
      nil
    end
  end
  private_class_method :_fetch_url

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
