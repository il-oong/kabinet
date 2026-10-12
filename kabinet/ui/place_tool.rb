module Kabinet
  module UI
    # 새 가구 배치 도구: "가구 생성"을 누르면 가구 윤곽이 마우스를 따라다니고,
    # 클릭한 자리에 생성한다 (예전엔 항상 원점 0,0,0에 생성됨).
    #   - 바닥/물체 윗면: 앞-왼쪽-아래 모서리를 클릭 지점에 놓음
    #   - 벽(세로 면): 등판을 벽에 붙이고 정면이 방 안쪽을 보게 자동 회전
    #   - Tab: 90° 회전 · Enter: 원점에 생성 · Esc: 취소
    #   - 스냅(끝점/모서리)이 적용되므로 벽 아래 모서리를 찍으면 바닥에 딱 붙는다.
    class PlaceTool
      def initialize(spec, &on_placed)
        @spec = Kabinet::Persistence::Schema.normalize(spec)
        Kabinet::Persistence::Schema.validate!(@spec)
        @on_placed = on_placed
        root = Kabinet::Core::Assembly.from_hash(@spec).build(Kabinet::Geometry::Preview::Entities.new)
        @batches = root.entities.collect
        raise '배치할 부재가 없습니다. 모듈을 추가하세요.' if @batches.empty?
        @local = ::Geom::BoundingBox.new
        @batches.each { |b| @local.add(b[:points]) }
        @ip = ::Sketchup::InputPoint.new
        @turn = 0
        @world = nil
        @wall = false
        @placed = false
      end

      def activate
        Sketchup.status_text = hint
      end

      def deactivate(view)
        view.invalidate
        @on_placed&.call(nil) unless @placed
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @world = placement(view) if @ip.valid?
        view.tooltip = @ip.tooltip if @ip.valid?
        Sketchup.status_text = hint
        view.invalidate
      end

      def onKeyUp(key, _repeat, _flags, view)
        case key
        when 9 # Tab
          @turn = (@turn + 1) % 4
          @world = placement(view) if @ip.valid?
          view.invalidate
        when 13 # Enter: 예전처럼 원점에
          place(view.model, ::Geom::Transformation.new)
        end
      end

      def onLButtonDown(_flags, _x, _y, view)
        place(view.model, @world) if @world
      end

      def getExtents
        bb = ::Geom::BoundingBox.new
        @batches.each { |b| bb.add(b[:points].map { |p| p.transform(@world) }) } if @world
        bb
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        return unless @world
        view.line_stipple = ''
        view.line_width = 1
        view.drawing_color = ::Sketchup::Color.new(30, 145, 235)
        @batches.each do |b|
          view.draw2d(GL_LINES, b[:points].map { |p| view.screen_coords(p.transform(@world)) })
        end
        size = [@local.width, @local.height, @local.depth].map { |v| (v.to_f / 1.mm.to_f).round }
        z = (@ip.position.z.to_f / 1.mm.to_f).round
        view.drawing_color = ::Sketchup::Color.new(20, 90, 160)
        view.draw_text([16, 16], "가구 배치 · #{size.join(' × ')} mm · 바닥에서 #{z} mm#{@wall ? ' · 벽에 붙임' : ''}")
        view.draw_text([16, 36], '클릭: 여기에 생성 · Tab: 90° 회전 · Enter: 원점에 생성 · Esc: 취소')
      end

      private

      def hint
        '가구를 놓을 곳을 클릭하세요 (벽을 가리키면 등판을 벽에 붙임) · Tab: 회전 · Enter: 원점 · Esc: 취소'
      end

      # 클릭 지점 → 가구 로컬 원점 변환 (월드 기준)
      def placement(view)
        pt = @ip.position
        angle = @turn * Math::PI / 2
        anchor = ::Geom::Point3d.new(0, 0, 0)        # 앞-왼쪽-아래
        @wall = false
        n = wall_normal(view)
        if n
          @wall = true
          # 로컬 +Y(등판 방향)가 벽 안쪽(-n)을 향하도록
          angle += Math.atan2(n.x, -n.y)
          anchor = ::Geom::Point3d.new(0, @local.max.y, 0) # 왼쪽-뒤-아래를 벽 위 지점에
        end
        rot = ::Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
        ::Geom::Transformation.new(pt) * rot * ::Geom::Transformation.new(ORIGIN - anchor)
      end

      # 커서 아래 면이 벽(세로 면)이면 방 안쪽(카메라 쪽)을 향하는 수평 법선
      def wall_normal(view)
        face = @ip.face
        return nil unless face
        n = face.normal.transform(@ip.transformation)
        return nil if n.length.zero?
        n.normalize!
        return nil if n.z.abs > 0.1
        n.reverse! if n.dot(view.camera.direction) > 0
        h = ::Geom::Vector3d.new(n.x, n.y, 0)
        h.length.zero? ? nil : h.normalize
      end

      def place(model, world)
        local = model.edit_transform.inverse * world
        root = Kabinet::Commands::Generate.run_assembly(@spec, model: model, transform: local,
                                                               entities: model.active_entities)
        @placed = true
        model.select_tool(nil)
        @on_placed&.call(root)
      rescue StandardError => e
        ::UI.messagebox("가구 생성 실패:\n#{e.message}")
      end
    end
  end
end
