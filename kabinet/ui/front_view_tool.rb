module Kabinet
  module UI
    # 도면 정면 방향 보기: 선택한 가구마다 LayOut 도면이 "정면도"로 그릴 면을 모델 화면에 표시한다.
    #   - 정면이 되는 면을 초록색으로 채우고, 바닥에 정면 화살표 + "정면" 글자
    #   - 정면에서 바라본 기준의 좌/우, 뒤 글자
    # 모델은 바꾸지 않는다(도구 그래픽). Esc 또는 다른 도구 선택 시 사라짐.
    class FrontViewTool
      FRONT_FILL = [40, 180, 90, 70].freeze

      def initialize(targets)
        @items = targets.map { |e| item(e) }.compact
        raise '방향을 볼 가구(그룹/컴포넌트)를 선택하세요.' if @items.empty?
      end

      def activate
        Sketchup.status_text = '초록 면 = 도면 정면도 · 화살표 = 정면 방향 · 좌/우는 정면에서 본 기준 · Esc: 닫기'
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @items.each { |it| bb.add(it[:corners]); bb.add(it[:arrow_tip]) }
        bb
      end

      def draw(view)
        view.line_stipple = ''
        @items.each do |it|
          view.drawing_color = Sketchup::Color.new(*FRONT_FILL)
          view.draw(GL_QUADS, it[:front_quad])
          view.drawing_color = Sketchup::Color.new(30, 150, 70)
          view.line_width = 3
          view.draw(GL_LINE_LOOP, it[:front_quad])
          view.draw(GL_LINES, [it[:arrow_base], it[:arrow_tip]])
          view.draw(GL_LINES, [it[:arrow_tip], it[:head_l], it[:arrow_tip], it[:head_r]])
          label(view, it[:arrow_tip], "정면 (#{it[:axis]})", [20, 120, 60])
          label(view, it[:left], '좌', [40, 40, 40])
          label(view, it[:right], '우', [40, 40, 40])
          label(view, it[:back], '뒤', [120, 120, 120])
        end
        view.drawing_color = Sketchup::Color.new(20, 90, 50)
        view.draw_text([16, 16], '도면 정면 방향 — 초록 면이 정면도 · 화살표 쪽에서 바라본 모습 · 좌/우는 정면에서 본 기준 · Esc 닫기')
      end

      private

      def label(view, pt, text, rgb)
        view.draw_text(view.screen_coords(pt), text, size: 13, bold: true, color: Sketchup::Color.new(*rgb))
      rescue ArgumentError
        view.draw_text(view.screen_coords(pt), text)
      end

      def item(e)
        return nil unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        axis = Kabinet::Output::FurnitureSheet.front_axis([e])
        fx, fy = Kabinet::Output::FurnitureSheet::FRONT_AXES.fetch(axis)
        bb = e.bounds
        lo = bb.min
        hi = bb.max
        # 정면 면(앞쪽 bbox 면)
        quad = if fx.zero?
                 y = fy.negative? ? lo.y : hi.y
                 [[lo.x, y, lo.z], [hi.x, y, lo.z], [hi.x, y, hi.z], [lo.x, y, hi.z]]
               else
                 x = fx.negative? ? lo.x : hi.x
                 [[x, lo.y, lo.z], [x, hi.y, lo.z], [x, hi.y, hi.z], [x, lo.y, hi.z]]
               end.map { |p| Geom::Point3d.new(*p) }
        c = bb.center
        depth = fx.zero? ? (hi.y - lo.y) : (hi.x - lo.x)
        width = fx.zero? ? (hi.x - lo.x) : (hi.y - lo.y)
        len = [[width, depth].max * 0.6, 300.mm].max
        f = Geom::Vector3d.new(fx, fy, 0)
        r = Geom::Vector3d.new(-fy, fx, 0) # 정면에서 바라봤을 때 오른쪽
        base = Geom::Point3d.new(c.x + fx * depth / 2.0, c.y + fy * depth / 2.0, lo.z)
        tip = base.offset(f, len)
        head = len * 0.18
        {
          axis: axis, corners: (0..7).map { |k| bb.corner(k) }, front_quad: quad,
          arrow_base: base, arrow_tip: tip,
          head_l: tip.offset(f.reverse, head).offset(r, head * 0.6),
          head_r: tip.offset(f.reverse, head).offset(r.reverse, head * 0.6),
          # 정면에서 바라본 사람 기준 좌/우는 r의 반대/같은 쪽
          left: Geom::Point3d.new(c.x, c.y, c.z).offset(r.reverse, width / 2.0 + 50.mm).offset(f, depth / 2.0),
          right: Geom::Point3d.new(c.x, c.y, c.z).offset(r, width / 2.0 + 50.mm).offset(f, depth / 2.0),
          back: Geom::Point3d.new(c.x, c.y, hi.z).offset(f.reverse, depth / 2.0 + 50.mm)
        }
      end
    end
  end
end
