module Kabinet
  module UI
    module Menu
      module_function

      ICON_DIR = File.join(File.dirname(__FILE__), 'icons').freeze

      def tool_command(title, tip, status, icon, &block)
        cmd = ::UI::Command.new(title, &block)
        cmd.tooltip = tip
        cmd.status_bar_text = status
        cmd.small_icon = cmd.large_icon = File.join(ICON_DIR, icon)
        cmd
      end

      def install
        face_cmd = tool_command('면 → 18T 패널', '면 → 18T 패널',
                                '면을 클릭하면 두께를 인식해 18T 패널로 만듭니다', 'face_panel.svg') do
          Sketchup.active_model.select_tool(Kabinet::UI::FacePanelTool.new)
        end
        space_cmd = tool_command('공간 분할 + 도어', '공간 분할 + 도어 균등',
                                 '캐비닛 안쪽을 클릭하면 칸막이와 도어를 균등 분할해 만듭니다', 'space_divide.svg') do
          Sketchup.active_model.select_tool(Kabinet::UI::SpaceDivideTool.new)
        end
        toolbar = ::UI::Toolbar.new('Kabinet')
        toolbar.add_item(face_cmd)
        toolbar.add_item(space_cmd)
        toolbar.restore

        plugins_menu = ::UI.menu('Extensions')
        kabinet_menu = plugins_menu.add_submenu('Kabinet — 카케이스 생성기')

        kabinet_menu.add_item('새 어셈블리…') { Kabinet::UI::Dialog.show }
        kabinet_menu.add_item('선택 어셈블리 편집…') { Kabinet::UI::Dialog.show_with_selection }
        kabinet_menu.add_separator
        kabinet_menu.add_item(face_cmd)
        kabinet_menu.add_item(space_cmd)
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
        kabinet_menu.add_item('⬆ GitHub에서 업데이트') do
          ans = ::UI.messagebox(
            "GitHub(master)에서 최신 버전을 내려받습니다.\n" \
            "인터넷 연결이 필요합니다.\n\n계속하시겠습니까?",
            MB_YESNO
          )
          next unless ans == IDYES

          ok = Kabinet.update!
          if ok
            ::UI.messagebox("업데이트 완료!\n\n" \
                            "Extensions > Kabinet > 새 어셈블리…\n" \
                            "를 다시 열면 UI 변경분도 반영됩니다.")
          else
            ::UI.messagebox("업데이트 중 일부 오류가 발생했습니다.\n루비 콘솔을 확인하세요.")
          end
        end
        kabinet_menu.add_item('🔄 플러그인 다시 로드') do
          ok = Kabinet.reload!
          if ok
            ::UI.messagebox("다시 로드 완료.\n\n" \
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
