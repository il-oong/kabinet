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
          @info = path && path.last.is_a?(::Sketchup::Face) ? Kabinet::Commands::FacePanel.analyze(path) : nil
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
    class SpaceDivideTool
      AXIS_LABELS = { '세로 칸막이 (좌우로 분할)' => 'x', '가로 선반 (상하로 분할)' => 'z' }.freeze
      DOOR_LABELS = { '오버레이 (전면 덮음)' => 'overlay', '인셋 (칸 안에)' => 'inset', '도어 없음' => 'none' }.freeze

      def initialize
        @probe = nil
        @error = nil
        @settings = {
          axis_label: AXIS_LABELS.keys.first, cells: 2,
          thickness: Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.to_f,
          door_label: DOOR_LABELS.keys.first,
          door_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.to_f
        }
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
        return unless ask_settings(@probe[:space][:size])
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
        c = Kabinet::Commands::SpaceDivide.box_corners(@probe)
        # box_corners 순서: (x,y,z) ∈ {0,1}³ → 인덱스 = 4x + 2y + z
        edges = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
        view.line_width = 2
        view.line_stipple = ''
        view.drawing_color = ::Sketchup::Color.new(30, 145, 235)
        edges.each { |a, b| view.draw(GL_LINES, [c[a], c[b]]) }
        s = @probe[:space][:size].map { |v| v.round(1) }
        view.draw_text(view.screen_coords(@probe[:origin]), "내부 #{s[0]} × #{s[1]} × #{s[2]} mm")
      end

      private

      def current_settings
        s = @settings
        { axis: AXIS_LABELS[s[:axis_label]], cells: s[:cells], thickness: s[:thickness],
          door_mode: DOOR_LABELS[s[:door_label]], door_thickness: s[:door_thickness] }
      end

      def ask_settings(size)
        s = @settings
        prompts = ['분할 방향', '칸 수', '칸막이 두께(mm)', '도어', '도어 두께(mm)']
        defaults = [s[:axis_label], s[:cells], s[:thickness], s[:door_label], s[:door_thickness]]
        lists = [AXIS_LABELS.keys.join('|'), '', '', DOOR_LABELS.keys.join('|'), '']
        title = "공간 분할 — 내부 #{size.map { |v| v.round }.join(' × ')} mm"
        input = ::UI.inputbox(prompts, defaults, lists, title)
        return false unless input
        s[:axis_label], s[:cells], s[:thickness], s[:door_label], s[:door_thickness] = input
        s[:cells] = s[:cells].to_i
        true
      end

      def update_status
        Sketchup.status_text =
          if @error
            @error
          elsif @probe
            s = @probe[:space][:size].map { |v| v.round }
            "인식된 공간 #{s.join(' × ')} mm · 클릭: 칸막이 + 도어 균등 생성"
          else
            '캐비닛 안쪽 면(뒷판·측판 안쪽 등)을 클릭하세요 · Esc: 종료'
          end
      end
    end
  end
end
