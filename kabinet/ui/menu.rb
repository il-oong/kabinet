module Kabinet
  module UI
    # 메뉴 분류: Kabinet 열기(창 — 가구·프리셋·도면 전부) / 판재 · 분할 도구(모델 위 클릭 도구) / 설정.
    # 판재 · 분할 도구는 Kabinet 창 사이드바의 같은 이름 폴더에서도 실행할 수 있다.
    module Menu
      module_function

      def tool_command(title, status, icon, &block)
        cmd = ::UI::Command.new(title, &block)
        cmd.tooltip = title
        cmd.status_bar_text = status
        cmd.small_icon = cmd.large_icon = File.join(ICON_DIR, icon)
        cmd
      end

      ICON_DIR = File.join(File.dirname(__FILE__), 'icons').freeze

      def install
        open_cmd = ::UI::Command.new('Kabinet 열기') { Kabinet::UI::Dialog.show_with_selection }
        open_cmd.tooltip = 'Kabinet 창 열기'
        open_cmd.status_bar_text = '프리셋 · 도구(면 → 패널, 공간 분할) · 도면 출력을 한 창에서 사용합니다'
        open_cmd.small_icon = open_cmd.large_icon = File.join(ICON_DIR, 'kabinet.svg')

        # 판재 · 분할 도구 (모델 위에서 바로 클릭해 쓰는 도구 — 별도 분류)
        face_cmd = tool_command('면 → 18T 패널', '면을 클릭하면 18T(두께 변경 가능) 판재로 만듭니다',
                                'face_panel.svg') do
          Sketchup.active_model.select_tool(Kabinet::UI::FacePanelTool.new)
        end
        space_cmd = tool_command('공간 균등 분할 (칸막이 + 도어)', '캐비닛 안쪽을 클릭 → 칸 수 입력 → 균등 분할',
                                 'space_divide.svg') do
          Sketchup.active_model.select_tool(Kabinet::UI::SpaceDivideTool.new)
        end

        door_cmd = ::UI::Command.new('도어 열기/닫기') { Kabinet::Commands::DoorToggle.run }
        door_cmd.tooltip = '도어 열기/닫기 (선택한 가구, 없으면 전체)'
        door_cmd.status_bar_text = '여닫이 도어를 열거나 닫습니다 — 단축키: 확장 프로그램 > Kabinet 메뉴 항목에 지정'
        door_cmd.small_icon = door_cmd.large_icon = File.join(ICON_DIR, 'kabinet.svg')

        toolbar = ::UI::Toolbar.new('Kabinet')
        toolbar.add_item(open_cmd)
        toolbar.add_separator
        toolbar.add_item(face_cmd)
        toolbar.add_item(space_cmd)
        toolbar.add_item(door_cmd)
        toolbar.restore

        kabinet_menu = ::UI.menu('Extensions').add_submenu('Kabinet — 카케이스 생성기')
        kabinet_menu.add_item(open_cmd)
        kabinet_menu.add_item(door_cmd)
        kabinet_menu.add_separator
        tools_menu = kabinet_menu.add_submenu('판재 · 분할 도구')
        tools_menu.add_item(face_cmd)
        tools_menu.add_item(space_cmd)
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
