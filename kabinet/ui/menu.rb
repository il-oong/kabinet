module Kabinet
  module UI
    module Menu
      module_function

      def install
        plugins_menu = ::UI.menu('Extensions')
        kabinet_menu = plugins_menu.add_submenu('Kabinet — 카케이스 생성기')

        kabinet_menu.add_item('새 어셈블리…') { Kabinet::UI::Dialog.show }
        kabinet_menu.add_item('선택 어셈블리 편집…') { Kabinet::UI::Dialog.show_with_selection }
        kabinet_menu.add_separator
        kabinet_menu.add_item('선택 어셈블리 재생성') { Kabinet::Commands::Regenerate.run }
        kabinet_menu.add_separator
        kabinet_menu.add_item('도면 출력 (PNG + PDF)…') { Kabinet::Commands::Export.run }
        kabinet_menu.add_separator
        kabinet_menu.add_item('Kabinet 정보…') do
          ::UI.messagebox("Kabinet — 카케이스 생성기\n버전 #{Kabinet::VERSION}\n\n" \
                          '파라메트릭 가구(붙박이장/주방가구/화장대)를 생성하고\n' \
                          '판 두께를 유지하며 재생성할 수 있습니다.')
        end
        kabinet_menu.add_separator
        kabinet_menu.add_item('🔄 플러그인 다시 로드 (개발자용)') do
          ok = Kabinet.reload!
          if ok
            ::UI.messagebox("Kabinet 다시 로드 완료.\n\n" \
                            "JS/HTML/CSS 변경분은\n" \
                            "Extensions > Kabinet > 새 어셈블리… 를\n" \
                            "다시 열면 반영됩니다.")
          else
            ::UI.messagebox("다시 로드 중 오류가 발생했습니다.\n루비 콘솔을 확인하세요.")
          end
        end
      end
    end
  end
end
