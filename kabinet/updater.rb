module Kabinet
  # GitHub(master)의 kabinet.rbz를 내려받아 설치하는 업데이터.
  # 메뉴 "GitHub에서 업데이트" 와 Kabinet 창 사이드바 "설정" 폴더에서 호출한다.
  module Updater
    module_function

    REPO_RAW    = 'https://raw.githubusercontent.com/il-oong/kabinet/master'.freeze
    RBZ_URL     = "#{REPO_RAW}/kabinet.rbz".freeze
    VERSION_URL = "#{REPO_RAW}/kabinet/version.rb".freeze
    PAGE_URL    = 'https://github.com/il-oong/kabinet/blob/master/kabinet.rbz'.freeze

    # on_status: 진행 메시지를 받을 블록 (Kabinet 창 상태줄 표시용, 없으면 무시)
    def run(&on_status)
      @on_status = on_status
      unless defined?(Sketchup::Http::Request)
        # SketchUp 2016 이하: 내장 HTTP 없음 → 브라우저로 받게 한다
        ::UI.messagebox("이 SketchUp 버전은 자동 다운로드를 지원하지 않습니다.\n" \
                        "브라우저에서 kabinet.rbz를 내려받아\n" \
                        "Window > Extension Manager > Install Extension 으로 설치하세요.")
        ::UI.openURL(PAGE_URL)
        return
      end
      status('최신 버전 확인 중…')
      fetch(VERSION_URL) do |ok, body|
        latest = ok ? body.to_s[/VERSION\s*=\s*'([^']+)'/, 1] : nil
        ask_and_install(latest)
      end
    end

    def ask_and_install(latest)
      cur = Kabinet::VERSION
      msg = if latest.nil?
              "최신 버전 정보를 확인하지 못했습니다.\n그래도 GitHub에서 내려받아 설치할까요?"
            elsif latest == cur
              "이미 최신 버전입니다 (v#{cur}).\n다시 설치할까요?"
            else
              "새 버전이 있습니다: v#{cur} → v#{latest}\n지금 설치할까요?"
            end
      return status('업데이트 취소됨') unless ::UI.messagebox(msg, MB_YESNO) == IDYES

      status('kabinet.rbz 내려받는 중…')
      fetch(RBZ_URL) do |ok, body|
        next fail!("다운로드 실패 (#{body})") unless ok
        install(body)
      end
    end

    def install(data)
      require 'tmpdir'
      path = File.join(Dir.tmpdir, "kabinet_update_#{Time.now.to_i}.rbz")
      File.open(path, 'wb') { |f| f.write(data.to_s.dup.force_encoding(Encoding::BINARY)) }
      raise '받은 파일이 올바른 rbz가 아닙니다.' unless File.binread(path, 2) == 'PK'

      Kabinet::UI::Dialog.close_if_open
      Sketchup.install_from_archive(path)
      status('업데이트 설치 완료 — SketchUp을 다시 시작하세요.')
      ::UI.messagebox("업데이트 설치 완료!\n\nSketchUp을 완전히 종료했다가 다시 실행하면\n새 버전(창·메뉴)이 적용됩니다.")
    rescue Interrupt
      status('설치가 취소되었습니다.')
    rescue StandardError => e
      fail!(e.message)
    end

    # 비동기 GET. 블록에 (성공여부, 본문 또는 오류문구) 전달.
    def fetch(url)
      sep = url.include?('?') ? '&' : '?'
      req = Sketchup::Http::Request.new("#{url}#{sep}t=#{Time.now.to_i}", Sketchup::Http::GET)
      @requests ||= []
      @requests << req # 응답 전에 GC로 사라지면 콜백이 오지 않으므로 참조 유지
      req.start do |request, response|
        @requests.delete(request)
        begin
          if response && response.status_code == 200
            yield true, response.body
          else
            yield false, "HTTP #{response ? response.status_code : '응답 없음'}"
          end
        rescue StandardError => e
          fail!(e.message)
        end
      end
    end

    def reload_with_message
      if Kabinet.reload!
        ::UI.messagebox("다시 로드 완료.\n\nExtensions > Kabinet > Kabinet 열기 로 창을 다시 여세요.")
      else
        ::UI.messagebox("다시 로드 중 오류가 발생했습니다.\n루비 콘솔을 확인하세요.")
      end
    end

    def fail!(message)
      status("업데이트 실패: #{message}")
      ::UI.messagebox("업데이트 실패:\n#{message}\n\n" \
                      "브라우저에서 kabinet.rbz를 받아 Extension Manager로 설치할 수도 있습니다.")
    end

    def status(text)
      @on_status&.call(text)
    rescue StandardError
      nil
    end
  end
end
