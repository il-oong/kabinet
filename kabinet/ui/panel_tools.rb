module Kabinet
  module UI
    # ── 면 클릭 → 두께 인식 → 18T 패널 ────────────────────────────────────
    class FacePanelTool
      def initialize
        @thickness = Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.to_f
        @flip = false
        @info = nil
        @key = nil
        @message = nil
      end

      def activate
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def enableVCB?
        true
      end

      # VCB에 숫자(mm)를 입력하면 다음 패널부터 그 두께로 만든다.
      def onUserText(text, view)
        v = text.to_s.tr(',', '.')[/\d+(\.\d+)?/].to_f
        if v >= 3 && v <= 100
          @thickness = v
          @message = nil
        else
          @message = '두께는 3~100mm 사이로 입력하세요.'
        end
        update_status
        view.invalidate
      end

      def onKeyUp(key, _repeat, _flags, view)
        return unless key == 9 # Tab: 돌출 방향 반전
        @flip = !@flip
        update_status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        r = view.model.raytest(view.pickray(x, y), true)
        path = r && r[1]
        key = path ? path.map(&:entityID) : nil
        if key != @key
          @key = key
          @info = path && path.last.is_a?(::Sketchup::Face) ? Kabinet::Commands::FacePanel.analyze(path, view.model) : nil
        end
        update_status
        view.invalidate
      rescue StandardError => e
        @info = nil
        @message = e.message
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @info
        Kabinet::Commands::FacePanel.build(view.model, @info, @thickness, flip: @flip)
        @info = nil
        @key = nil
        @message = nil
        view.invalidate
      rescue StandardError => e
        @message = e.message
        ::UI.messagebox("패널 생성 실패:\n#{e.message}")
      end

      def getExtents
        bb = ::Geom::BoundingBox.new
        bb.add(@info[:loops_w].flatten) if @info
        bb
      end

      def draw(view)
        return unless @info
        dir = preview_direction(view)
        t = @thickness.mm
        outer = @info[:loops_w].first
        moved = outer.map { |p| p.offset(dir, t) }
        view.line_width = 2
        view.line_stipple = ''
        view.drawing_color = ::Sketchup::Color.new(235, 145, 25)
        view.draw(GL_LINE_LOOP, outer)
        view.drawing_color = ::Sketchup::Color.new(30, 145, 235)
        view.draw(GL_LINE_LOOP, moved)
        outer.each_with_index { |p, i| view.draw(GL_LINES, [p, moved[i]]) }
      end

      private

      def preview_direction(view)
        dir = @info[:dir_w]
        unless dir
          n = @info[:normal_w]
          dir = n.dot(view.camera.direction) < 0 ? n : n.reverse
        end
        @flip ? dir.reverse : dir
      end

      def update_status
        Sketchup.vcb_label = '두께(mm)'
        Sketchup.vcb_value = @thickness.round(1).to_s.sub(/\.0\z/, '')
        Sketchup.status_text =
          if @message
            @message
          elsif @info
            found = @info[:found_mm]
            head = found ? "감지 두께 #{found.round(1)}mm → #{@thickness.round(1)}T" : "두께 없는 면 → #{@thickness.round(1)}T"
            tail = if @info[:in_assembly] then ' · Kabinet 어셈블리 부재(수정 불가)'
                   elsif @info[:replaceable] then ' · 원본 판재 교체'
                   else ''
                   end
            "#{head}#{tail} · 클릭: 생성 · Tab: 방향#{@flip ? '(반전됨)' : ''} · 숫자 입력: 두께 변경"
          else
            "면을 클릭하면 #{@thickness.round(1)}T 패널로 만듭니다 · 숫자 입력: 두께 변경 · Esc: 종료"
          end
      end
    end

    # ── 공간 클릭 → 칸막이 균등 분할 + 도어 균등 생성 ─────────────────────
    # 클릭 한 번으로 생성. 호버 중 미리보기를 보며 키로 설정을 바꾼다.
    #   ↑/↓ 또는 숫자 입력(VCB): 칸 수   Tab: 세로/가로 전환
    #   ←/→: 도어 방식 순환(오버레이/인셋/없음)   Enter: 두께 설정 창
    class SpaceDivideTool
      DOOR_MODES  = %w[overlay inset none].freeze
      DOOR_LABELS = { 'overlay' => '오버레이', 'inset' => '인셋', 'none' => '도어 없음' }.freeze
      AXIS_LABELS = { 'x' => '세로 칸막이', 'z' => '가로 선반' }.freeze
      PREF = 'Kabinet'.freeze

      def initialize
        @probe = nil
        @error = nil
        @axis = pref('space_axis', 'x')
        @axis = 'x' unless AXIS_LABELS.key?(@axis)
        @cells = pref('space_cells', 2).to_i.clamp(2, 20)
        @door_mode = pref('space_door', 'overlay')
        @door_mode = 'overlay' unless DOOR_MODES.include?(@door_mode)
        @thickness = pref('space_t', Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM).to_f
        @door_thickness = pref('space_dt', Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM).to_f
      end

      def activate
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def enableVCB?
        true
      end

      def onUserText(text, view)
        v = text.to_s[/\d+/].to_i
        if v >= 2 && v <= 20
          self.cells = v
        else
          Sketchup.status_text = '칸 수는 2~20 사이로 입력하세요.'
          return
        end
        update_status
        view.invalidate
      end

      def onKeyUp(key, _repeat, _flags, view)
        case key
        when 38 then self.cells = [@cells + 1, 20].min              # ↑
        when 40 then self.cells = [@cells - 1, 2].max               # ↓
        when 39 then cycle_door(1)                                  # →
        when 37 then cycle_door(-1)                                 # ←
        when 9
          @axis = @axis == 'x' ? 'z' : 'x'                          # Tab
          save('space_axis', @axis)
        when 13 then return ask_thickness(view)                     # Enter
        else return
        end
        update_status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @probe = nil
        @error = nil
        ray = view.pickray(x, y)
        r = view.model.raytest(ray, true)
        @probe = Kabinet::Commands::SpaceDivide.probe(view.model, r[0], r[1], ray[1]) if r
        update_status
        view.invalidate
      rescue Kabinet::Core::SpaceDivider::Error => e
        @error = e.message
        update_status
        view.invalidate
      rescue StandardError => e
        @error = "공간 인식 오류: #{e.message}"
        update_status
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @probe
        result = Kabinet::Commands::SpaceDivide.build(view.model, @probe, current_settings)
        plan = result[:plan]
        Sketchup.status_text = "칸막이 #{plan[:partitions].size}개 · 도어 #{plan[:doors].size}장 생성 · 칸 내폭 #{plan[:cell_mm].round(1)}mm"
        ::UI.messagebox("경고:\n" + plan[:warnings].join("\n")) unless plan[:warnings].empty?
        @probe = nil
        view.invalidate
      rescue Kabinet::Core::SpaceDivider::Error => e
        ::UI.messagebox(e.message)
      rescue StandardError => e
        ::UI.messagebox("공간 분할 실패:\n#{e.message}")
      end

      def getExtents
        bb = ::Geom::BoundingBox.new
        bb.add(Kabinet::Commands::SpaceDivide.box_corners(@probe)) if @probe
        bb
      end

      def draw(view)
        return unless @probe
        view.line_stipple = ''
        draw_box(view, Kabinet::Commands::SpaceDivide.box_corners(@probe), ::Sketchup::Color.new(30, 145, 235), 2)
        plan = preview_plan
        if plan
          plan[:partitions].each { |p| draw_box(view, Kabinet::Commands::SpaceDivide.item_corners(@probe, p), ::Sketchup::Color.new(235, 145, 25), 2) }
          plan[:doors].each { |d| draw_box(view, Kabinet::Commands::SpaceDivide.item_corners(@probe, d), ::Sketchup::Color.new(40, 170, 90), 1) }
        end
        s = @probe[:space][:size].map { |v| v.round }
        label = "내부 #{s.join(' × ')} mm"
        label += " · 칸 #{plan[:cell_mm].round(1)}mm" if plan
        view.draw_text(view.screen_coords(@probe[:origin]), label)
      end

      private

      # box_corners 순서: (x,y,z) ∈ {0,1}³ → 인덱스 = 4x + 2y + z
      BOX_EDGES = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]].freeze

      def draw_box(view, c, color, width)
        view.line_width = width
        view.drawing_color = color
        BOX_EDGES.each { |a, b| view.draw(GL_LINES, [c[a], c[b]]) }
      end

      def preview_plan
        Kabinet::Core::SpaceDivider.plan(@probe[:space], axis: @axis, cells: @cells, thickness: @thickness,
                                         door_mode: @door_mode, door_thickness: @door_thickness)
      rescue Kabinet::Core::SpaceDivider::Error
        nil
      end

      def current_settings
        { axis: @axis, cells: @cells, thickness: @thickness,
          door_mode: @door_mode, door_thickness: @door_thickness }
      end

      def cells=(v)
        @cells = v
        save('space_cells', v)
      end

      def cycle_door(step)
        @door_mode = DOOR_MODES[(DOOR_MODES.index(@door_mode) + step) % DOOR_MODES.size]
        save('space_door', @door_mode)
      end

      def ask_thickness(view)
        input = ::UI.inputbox(['칸막이 두께(mm)', '도어 두께(mm)'], [@thickness, @door_thickness], '두께 설정')
        return unless input
        @thickness = input[0].to_f if input[0].to_f > 0
        @door_thickness = input[1].to_f if input[1].to_f > 0
        save('space_t', @thickness)
        save('space_dt', @door_thickness)
        update_status
        view.invalidate
      end

      def pref(key, default)
        Sketchup.read_default(PREF, key, default)
      end

      def save(key, value)
        Sketchup.write_default(PREF, key, value)
      end

      def update_status
        Sketchup.vcb_label = '칸 수'
        Sketchup.vcb_value = @cells.to_s
        head = "#{AXIS_LABELS[@axis]} #{@cells}칸 · #{@thickness.round(1)}T · #{DOOR_LABELS[@door_mode]}"
        keys = '↑↓/숫자: 칸 수 · Tab: 방향 · ←→: 도어 · Enter: 두께'
        Sketchup.status_text =
          if @error
            @error
          elsif @probe
            "[#{head}] 클릭: 생성 · #{keys}"
          else
            "[#{head}] 캐비닛 안쪽 면을 가리키세요 · #{keys} · Esc: 종료"
          end
      end
    end
  end
end
