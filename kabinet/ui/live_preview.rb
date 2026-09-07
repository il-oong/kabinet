module Kabinet
  module UI
    # Tool graphics remain outside the model, so cancel/close never needs Undo.
    class LivePreview
      attr_reader :model, :target, :spec

      def initialize(model, &on_stop)
        @model = model
        @on_stop = on_stop
        @batches = []
        @bounds = ::Geom::BoundingBox.new
        @active = false
      end

      def update(spec, target: nil, internal: false, selected_module: nil)
        raise '그룹 편집을 닫은 뒤 미리보기를 사용하세요.' if @model.active_path
        raise '다른 모델로 전환되었습니다. 미리보기를 다시 켜세요.' unless Sketchup.active_model == @model
        if target
          raise '수정할 가구가 삭제되었거나 잠겨 있습니다.' unless target.valid? && !target.locked?
          raise 'Kabinet 가구 그룹만 미리 수정할 수 있습니다.' unless target.is_a?(Sketchup::Group) && Kabinet::Persistence::Attributes.assembly?(target)
        end
        norm = Kabinet::Persistence::Schema.normalize(spec)
        Kabinet::Persistence::Schema.validate!(norm)
        entities = Kabinet::Geometry::Preview::Entities.new
        root = Kabinet::Core::Assembly.from_hash(norm).build(entities)
        batches = root.entities.collect
        raise '미리볼 부재가 없습니다. 모듈을 추가하세요.' if batches.empty?
        local_bounds = ::Geom::BoundingBox.new
        batches.each { |b| local_bounds.add(b[:points]) }
        transform = target ? target.transformation : ::Geom::Transformation.new
        bounds = ::Geom::BoundingBox.new
        batches.each do |batch|
          batch[:points] = batch[:points].map { |p| p.transform(transform) }
          bounds.add(batch[:points])
        end
        @spec, @target = norm, target
        @batches, @bounds, @local_bounds, @transform = batches, bounds, local_bounds, transform
        @internal, @selected_module = internal, selected_module
        first = !@active
        @model.select_tool(self) if first
        @model.active_view.zoom(@bounds) if first
        @model.active_view.invalidate
      end

      def activate
        @active = true
      end

      def deactivate(view)
        @active = false
        @batches = []
        view.invalidate
        @on_stop.call if @on_stop
      end

      def stop
        @model.select_tool(nil) if @active
      end

      def onCancel(_reason, _view)
        stop
      end

      def suspend(view)
        view.invalidate
      end

      def resume(view)
        view.invalidate
      end

      def getExtents
        @bounds
      end

      def set_view(name)
        return if @batches.empty?
        vectors = { 'front' => [0, -1, 0], 'side' => [1, 0, 0],
                    'top' => [0, 0, 1], 'iso' => [1, -1, 0.8] }
        direction = vectors[name]
        return unless direction
        center = @bounds.center
        axis = ::Geom::Vector3d.new(*direction).transform(@transform).normalize
        up = ::Geom::Vector3d.new(*(name == 'top' ? [0, 1, 0] : [0, 0, 1])).transform(@transform).normalize
        eye = center.offset(axis, [@bounds.diagonal * 2, 1000.mm].max)
        view = @model.active_view
        view.camera = Sketchup::Camera.new(eye, center, up, false)
        view.zoom(@bounds)
        view.invalidate
      end

      def draw(view)
        return if @batches.empty?
        # Screen-space wireframe stays readable over the untouched original.
        view.line_stipple = ''
        @batches.each do |batch|
          next if @internal && batch[:front]
          selected = !@selected_module.nil? && batch[:module_index] == @selected_module
          view.drawing_color = selected ? Sketchup::Color.new(235, 145, 25) : Sketchup::Color.new(30, 145, 235)
          view.line_width = selected ? 3 : 1
          view.draw2d(GL_LINES, batch[:points].map { |p| view.screen_coords(p) })
        end
        view.drawing_color = Sketchup::Color.new(20, 90, 160)
        sx, sy, sz = [@transform.xaxis, @transform.yaxis, @transform.zaxis].map(&:length)
        sizes = [@local_bounds.width * sx, @local_bounds.height * sy, @local_bounds.depth * sz]
        text = sizes.map { |v| (v.to_f / 1.mm.to_f).round(1) }.join(' × ')
        view.draw_text([16, 16], "미리보기 · 폭 × 깊이 × 높이 #{text} mm (손잡이 포함)")
        view.draw_text([16, 36], @target ? '파란 선: 변경안 / 기존 모델 유지 · 적용 버튼으로 확정 · Esc: 종료' : '파란 선: 생성 예정 · 적용 버튼으로 확정 · Esc: 종료')
      end
    end
  end
end
