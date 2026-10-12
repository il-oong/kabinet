module Kabinet
  module UI
    # ── 모델 위 반투명 하이라이트 (면/박스 채우기) ─────────────────────────
    # 호버한 면은 연한 파랑, 마우스를 누르고 있는 면은 진한 파랑으로 채운다.
    module Highlight
      module_function

      HOVER   = [30, 145, 235, 70].freeze
      PRESSED = [20, 100, 230, 150].freeze
      PART    = [235, 145, 25, 60].freeze
      DOOR    = [40, 170, 90, 45].freeze
      LIFT_MM = 0.3   # 원래 면과 겹쳐 깜빡이지 않도록 카메라 쪽으로 살짝 띄움

      # box_corners 순서: (x,y,z) ∈ {0,1}³ → 인덱스 = 4x + 2y + z
      BOX_QUADS = [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]].freeze

      # 면을 삼각형으로 쪼갠 월드 좌표 목록(GL_TRIANGLES 용). 구멍 있는 면도 처리된다.
      def face_triangles(face, tr)
        mesh = face.mesh(0)
        mesh.polygons.each_with_object([]) do |poly, tris|
          pts = poly.map { |i| mesh.point_at(i.abs).transform(tr) }
          (1...pts.size - 1).each { |k| tris.push(pts[0], pts[k], pts[k + 1]) }
        end
      end

      def fill_face(view, tris, normal_w, rgba)
        return if tris.nil? || tris.empty?
        n = normal_w.dot(view.camera.direction) > 0 ? normal_w.reverse : normal_w
        lift = LIFT_MM.mm
        view.drawing_color = ::Sketchup::Color.new(*rgba)
        view.draw(GL_TRIANGLES, tris.map { |p| p.offset(n, lift) })
      end

      def fill_box(view, corners, rgba)
        view.drawing_color = ::Sketchup::Color.new(*rgba)
        view.draw(GL_QUADS, BOX_QUADS.flat_map { |q| q.map { |i| corners[i] } })
      end
    end

    # ── 면 클릭 → 두께 인식 → 18T 패널 ────────────────────────────────────
    class FacePanelTool
      PREF = 'Kabinet'.freeze
      QUICK_THICKNESS = [9, 12, 15, 18, 20, 25].freeze

      def initialize(thickness = nil)
        @thickness = (thickness || Sketchup.read_default(PREF, 'face_t',
                                                        Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM)).to_f
        @thickness = Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.to_f unless @thickness >= 3 && @thickness <= 100
        @mouse = nil
        @flip = false
        @info = nil
        @key = nil
        @tris = nil
        @pressed = false
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
        set_thickness(text.to_s.tr(',', '.')[/\d+(\.\d+)?/].to_f, view)
      end

      def onKeyUp(key, _repeat, _flags, view)
        case key
        when 9 then @flip = !@flip            # Tab: 돌출 방향 반전
        when 13 then return ask_thickness(view) # Enter: 두께 입력 창
        else return
        end
        update_status
        view.invalidate
      end

      # 우클릭: 자주 쓰는 두께 / 직접 입력 / 방향 반전
      def getMenu(menu, _flags, _x, _y, view)
        QUICK_THICKNESS.each do |t|
          item = menu.add_item("#{t}T") { apply_thickness(t, view) }
          menu.set_validation_proc(item) { (@thickness - t).abs < 0.01 ? MF_CHECKED : MF_ENABLED }
        end
        menu.add_item('두께 직접 입력…') { ask_thickness(view, true) }
        menu.add_separator
        menu.add_item('돌출 방향 반전 (Tab)') { @flip = !@flip; update_status; view.invalidate }
        true
      end

      def onMouseMove(_flags, x, y, view)
        @mouse = [x, y]
        r = view.model.raytest(view.pickray(x, y), true)
        path = r && r[1]
        key = path ? path.map(&:entityID) : nil
        if key != @key
          @key = key
          @pressed = false
          @info = path && path.last.is_a?(::Sketchup::Face) ? Kabinet::Commands::FacePanel.analyze(path, view.model) : nil
          @tris = @info ? Highlight.face_triangles(@info[:face], Kabinet::Commands::FacePanel.instance_transform(path[0...-1])) : nil
        end
        update_status
        view.invalidate
      rescue StandardError => e
        @info = nil
        @message = e.message
        view.invalidate
      end

      # 누르는 동안 면을 진한 파랑으로 잡아 보여주고, 놓을 때 생성한다.
      def onLButtonDown(_flags, _x, _y, view)
        return unless @info
        @pressed = true
        view.invalidate
      end

      def onLButtonUp(_flags, _x, _y, view)
        pressed = @pressed
        @pressed = false
        return view.invalidate unless pressed && @info
        Kabinet::Commands::FacePanel.build(view.model, @info, @thickness, flip: @flip)
        @info = nil
        @tris = nil
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
        Highlight.fill_face(view, @tris, @info[:normal_w], @pressed ? Highlight::PRESSED : Highlight::HOVER)
        view.line_width = 2
        view.line_stipple = ''
        view.drawing_color = ::Sketchup::Color.new(235, 145, 25)
        view.draw(GL_LINE_LOOP, outer)
        view.drawing_color = ::Sketchup::Color.new(30, 145, 235)
        view.draw(GL_LINE_LOOP, moved)
        outer.each_with_index { |p, i| view.draw(GL_LINES, [p, moved[i]]) }
        draw_hint(view)
      end

      private

      # 커서 옆 안내 — 상태표시줄을 안 봐도 쓰는 법이 보이게
      def draw_hint(view)
        return unless @mouse
        pt = ::Geom::Point3d.new(@mouse[0] + 18, @mouse[1] + 14, 0)
        lines = ["#{@thickness.round(1).to_s.sub(/\.0\z/, '')}T 패널#{@flip ? ' (반전)' : ''}",
                 '클릭: 생성 · 우클릭/Enter: 두께 · Tab: 방향']
        if @info && @info[:resize] && !@flip
          lines << "현재 #{@info[:found_mm].to_f.round(1)}T → 클릭하면 이 판재 두께를 변경"
        elsif @info && @info[:in_assembly]
          lines << '가구 부재 면 → 바깥쪽에 새 패널 추가'
        end
        view.draw_text(pt, lines.join("\n"), size: 11, color: ::Sketchup::Color.new(20, 60, 120))
      rescue ArgumentError
        view.draw_text(pt, lines.join("\n")) # SketchUp 2019 이하: 옵션 미지원
      end

      def set_thickness(v, view)
        v = v.to_f
        if v >= 3 && v <= 100
          @thickness = v
          @message = nil
          Sketchup.write_default(PREF, 'face_t', v)
        else
          @message = '두께는 3~100mm 사이로 입력하세요.'
        end
        update_status
        view.invalidate
      end

      def ask_thickness(view, apply = false)
        input = ::UI.inputbox(['패널 두께(mm)'], [@thickness.round(1)], '18T 패널 두께')
        return unless input
        apply ? apply_thickness(input[0], view) : set_thickness(input[0], view)
      end

      # 우클릭 메뉴에서 두께를 고르면: 두께 설정 + 마우스 아래 면이 있으면 곧바로 적용
      def apply_thickness(v, view)
        set_thickness(v, view)
        return unless @info && @message.nil?
        Kabinet::Commands::FacePanel.build(view.model, @info, @thickness, flip: @flip)
        @info = nil
        @tris = nil
        @key = nil
        view.invalidate
      rescue StandardError => e
        @message = e.message
        ::UI.messagebox("패널 생성 실패:\n#{e.message}")
      end

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
            tail = if @info[:resize] && !@flip then ' · 그룹 안 판재 — 이 자리에서 두께 변경'
                   elsif @info[:in_assembly] then ' · Kabinet 가구 부재 — 바깥쪽에 새 패널 추가'
                   elsif @info[:replaceable] then ' · 원본 판재 교체'
                   else ''
                   end
            "#{head}#{tail} · 클릭: 생성 · Tab: 방향#{@flip ? '(반전됨)' : ''} · 우클릭/Enter/숫자: 두께 변경"
          else
            "면을 클릭하면 #{@thickness.round(1)}T 패널로 만듭니다 · 우클릭/Enter/숫자: 두께 변경 · Esc: 종료"
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
        @face_hl = nil
        @pressed = false
        @hover_key = nil
        @press_key = nil
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
        @face_hl = nil
        ray = view.pickray(x, y)
        r = view.model.raytest(ray, true)
        key = r ? r[1].map(&:entityID) : nil
        @hover_key = key
        @pressed = false if key != @press_key   # 누른 채 다른 면으로 옮기면 누름 취소
        if r
          @probe = Kabinet::Commands::SpaceDivide.probe(view.model, r[0], r[1], ray[1])
          @face_hl = face_highlight(r[1])
        end
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

      # 누르는 동안 공간을 진한 파랑으로 잡아 보여주고, 놓을 때 생성한다.
      def onLButtonDown(_flags, _x, _y, view)
        return unless @probe
        @pressed = true
        @press_key = @hover_key
        view.invalidate
      end

      def onLButtonUp(_flags, _x, _y, view)
        pressed = @pressed
        @pressed = false
        return view.invalidate unless pressed && @probe
        probe = @probe
        return view.invalidate unless ask_settings   # 칸 수·방향·도어·두께 입력 창 (취소하면 생성 안 함)
        result = Kabinet::Commands::SpaceDivide.build(view.model, probe, current_settings)
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
        if @face_hl
          Highlight.fill_face(view, @face_hl[:tris], @face_hl[:normal], @pressed ? Highlight::PRESSED : Highlight::HOVER)
        end
        draw_box(view, Kabinet::Commands::SpaceDivide.box_corners(@probe), ::Sketchup::Color.new(30, 145, 235), 2)
        plan = preview_plan
        if plan
          plan[:partitions].each { |p| Highlight.fill_box(view, Kabinet::Commands::SpaceDivide.item_corners(@probe, p), Highlight::PART) }
          plan[:doors].each { |d| Highlight.fill_box(view, Kabinet::Commands::SpaceDivide.item_corners(@probe, d), Highlight::DOOR) }
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

      def face_highlight(path)
        face = path.last
        return nil unless face.is_a?(::Sketchup::Face)
        tr = Kabinet::Commands::FacePanel.instance_transform(path[0...-1])
        { tris: Highlight.face_triangles(face, tr), normal: face.normal.transform(tr).normalize }
      end

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

      # 클릭 후 뜨는 설정 창. 확인하면 값을 저장하고 true.
      def ask_settings
        axis_names = AXIS_LABELS.values
        door_names = DOOR_MODES.map { |m| DOOR_LABELS[m] }
        input = ::UI.inputbox(
          ['몇 칸으로 나눌까요? (2~20)', '방향', '도어', '칸막이 두께(mm)', '도어 두께(mm)'],
          [@cells, AXIS_LABELS[@axis], DOOR_LABELS[@door_mode], @thickness, @door_thickness],
          ['', axis_names.join('|'), door_names.join('|'), '', ''],
          '공간 분할 설정'
        )
        return false unless input
        cells = input[0].to_i
        unless cells.between?(2, 20)
          ::UI.messagebox('칸 수는 2~20 사이로 입력하세요.')
          return false
        end
        self.cells = cells
        @axis = AXIS_LABELS.key(input[1]) || @axis
        save('space_axis', @axis)
        @door_mode = DOOR_LABELS.key(input[2]) || @door_mode
        save('space_door', @door_mode)
        @thickness = input[3].to_f if input[3].to_f > 0
        @door_thickness = input[4].to_f if input[4].to_f > 0
        save('space_t', @thickness)
        save('space_dt', @door_thickness)
        update_status
        true
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
            "[#{head}] 클릭: 칸 수 입력 창 → 생성 · #{keys}"
          else
            "[#{head}] 캐비닛 안쪽 면을 가리키세요 · #{keys} · Esc: 종료"
          end
      end
    end
  end
end
