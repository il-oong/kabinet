module Kabinet
  module UI
    # 메뉴/툴바는 "Kabinet 창 열기" 하나로 통일한다.
    # 면 → 패널, 공간 분할, 도면 출력, 프리셋 등 모든 기능은 Kabinet 창 왼쪽 사이드바에서 실행.
    module Menu
      module_function

      ICON_DIR = File.join(File.dirname(__FILE__), 'icons').freeze

      def install
        open_cmd = ::UI::Command.new('Kabinet 열기') { Kabinet::UI::Dialog.show_with_selection }
        open_cmd.tooltip = 'Kabinet 창 열기'
        open_cmd.status_bar_text = '프리셋 · 도구(면 → 패널, 공간 분할) · 도면 출력을 한 창에서 사용합니다'
        open_cmd.small_icon = open_cmd.large_icon = File.join(ICON_DIR, 'kabinet.svg')

        toolbar = ::UI::Toolbar.new('Kabinet')
        toolbar.add_item(open_cmd)
        toolbar.restore

        kabinet_menu = ::UI.menu('Extensions').add_submenu('Kabinet — 카케이스 생성기')
        kabinet_menu.add_item(open_cmd)
        kabinet_menu.add_separator
        kabinet_menu.add_item('⬆ GitHub에서 업데이트') { Kabinet::Updater.run }
        kabinet_menu.add_item('🔄 플러그인 다시 로드') { Kabinet::Updater.reload_with_message }
        kabinet_menu.add_item('Kabinet 정보…') do
          ::UI.messagebox("Kabinet — 카케이스 생성기\n버전 #{Kabinet::VERSION}\n\n" \
                          "Extensions > Kabinet > Kabinet 열기 에서 모든 기능을 사용합니다.")
        end
      end
    end
  end
end
