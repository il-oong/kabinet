module Kabinet
  module EPDialog
    module_function

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      d = ::UI::HtmlDialog.new(dialog_title: 'Kabinet — EP 판재 · 도면', preferences_key: 'kabinet_ep_v2', width: 460, height: 740, resizable: true)
      @dialog = d
      d.set_file(File.join(__dir__, 'web', 'ep.html'))
      d.add_action_callback('ep_library_list') do |_context|
        respond(d) do
          send_library(d)
          '판재를 만들거나, 보관함에서 가구를 선택하세요.'
        end
      end
      d.add_action_callback('ep_library_save') do |_context, name|
        respond(d) do
          FurnitureLibrary.save(name)
          send_library(d)
          "‘#{name}’ 저장 완료. 다음 작업에서도 보관함에서 불러올 수 있습니다."
        end
      end
      d.add_action_callback('ep_library_place') do |_context, id|
        respond(d) do
          FurnitureLibrary.place(id)
          '가구를 놓을 위치를 SketchUp 화면에서 클릭하세요. Esc로 취소합니다.'
        end
      end
      d.add_action_callback('ep_create') do |_context, raw|
        respond(d) do
          board = EPBoard.create(JSON.parse(raw))
          "#{board.name} 생성 완료. 이동·회전·복사로 조합하세요."
        end
      end
      d.add_action_callback('ep_role') do |_context, role|
        respond(d) do
          count = EPBoard.mark_role(role)
          "#{count}개 부품 구분 완료. 가구 전체를 다시 선택하고 출력하세요."
        end
      end
      d.add_action_callback('ep_export') do |_context, raw|
        respond(d) do
          result = Output::FurnitureSheet.run(JSON.parse(raw))
          result ? "저장 완료: #{result}" : '저장을 취소했습니다.'
        end
      end
      d.set_on_closed { @dialog = nil }
      d.show
    end

    def send_library(dialog)
      dialog.execute_script("epLibrary(#{JSON.generate(FurnitureLibrary.list)})")
    end

    def respond(dialog)
      message = yield
      dialog.execute_script("epResult(#{JSON.generate(message)}, false)")
    rescue StandardError => e
      puts "Kabinet EP: #{e.full_message}"
      dialog.execute_script("epResult(#{JSON.generate(e.message)}, true)")
    end
  end
end
