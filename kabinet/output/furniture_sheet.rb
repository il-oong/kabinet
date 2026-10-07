require 'fileutils'

module Kabinet
  module Output
    # A3 presentation sheet. Only the selected geometry is snapshotted; the
    # document being edited is never saved, reoriented, or stripped of entities.
    module FurnitureSheet
      module_function

      def run(options = {}, model: Sketchup.active_model, path: nil)
        raise 'SketchUp 2022 이상에서 실행하세요.' unless defined?(Layout::Document)
        raise '그룹 편집을 닫고 가구를 선택한 뒤 출력하세요.' if model.active_path
        targets = model.selection.to_a
        unless !targets.empty? && targets.all? { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          raise '출력할 EP 판재 또는 가구 그룹/컴포넌트만 선택하세요.'
        end
        title = options.fetch('title', '가구 도면').to_s.strip[0, 60]
        title = '가구 도면' if title.empty?
        safe = title.gsub(/[\\\/:*?"<>|]/, '_')
        path ||= ::UI.savepanel('가구 도면 저장', nil, "#{safe}.layout")
        return nil unless path
        path = path.sub(/\.(layout|pdf)\z/i, '') + '.layout'
        # Every export gets its own immutable model reference. Re-exporting a
        # drawing must not silently change the models linked by older drawings.
        asset_dir = path.sub(/\.layout\z/i, '') + "_assets_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{Process.pid}"
        asset_dir += '_1' while File.exist?(asset_dir)
        FileUtils.mkdir_p(asset_dir)
        data = capture(model, targets, asset_dir, options.fetch('internal', true))
        doc = compose(data, title)
        doc.save(path)
        begin
          doc.export(path.sub(/\.layout\z/i, '.pdf'))
        rescue StandardError => e
          raise "LayOut 파일은 저장했습니다: #{path}\nPDF 출력 실패: #{e.message}\nLayOut에서 파일을 열어 PDF로 내보내세요."
        end
        path
      end

      def capture(model, targets, dir, internal)
        mats = []
        segs = []
        boxes = []
        targets.each { |e| collect(e, Geom::Transformation.new, segs, boxes, mats) }
        raise '선택한 가구에 출력할 선이 없습니다.' if segs.empty?
        raise '선택한 형상이 너무 복잡합니다. 가구만 선택해 주세요.' if segs.length > 30_000
        points = segs.flatten(1)
        lo = (0..2).map { |i| points.map { |p| p[i] }.min }
        hi = (0..2).map { |i| points.map { |p| p[i] }.max }
        size = hi.zip(lo).map { |a, b| a - b }
        raise '가로·깊이·높이가 있는 입체 가구를 선택하세요.' if size.any? { |v| v < 0.01 }
        skp = File.join(dir, 'furniture.skp')
        selection = model.selection.to_a
        original_camera = model.active_view.camera
        model.start_operation('도면용 임시 복사', true)
        begin
          # Hide non-selected geometry only during ray tests; abort restores it.
          model.entities.each { |e| e.hidden = true if e.respond_to?(:hidden=) && !targets.include?(e) }
          visible = {}
          %w[top front side].each do |name|
            visible[name] = classify_edges(model, segs, name)
          end
          root = model.entities.add_group
          move = Geom::Transformation.translation(lo.zip(hi).map { |a, b| (-(a + b) / 2).mm })
          targets.each do |e|
            copy = root.entities.add_instance(e.definition, move * e.transformation)
            copy.material = e.material if e.material
          end
          model.active_view.camera = Sketchup::Camera.new([1, -1, 1], ORIGIN, Z_AXIS, false)
          model.active_view.zoom(root)
          raise '도면용 모델 저장에 실패했습니다.' unless root.definition.save_as(skp)
        ensure
          model.abort_operation
          model.active_view.camera = original_camera
          model.selection.clear
          selection.each { |e| model.selection.add(e) if e.valid? }
        end
        swatches = mats.uniq.first(3).map.with_index do |mat, i|
          image = nil
          if mat.texture
            image = File.join(dir, "material_#{i}.png")
            image = nil unless mat.texture.write(image)
          end
          { name: mat.display_name, color: mat.color, image: image }
        end
        { size: size, lo: lo, views: visible, boxes: boxes, skp: skp, materials: swatches, internal: internal }
      end

      # Sample each edge, then refine visible/occluded transitions. A partially
      # covered edge must not become one solid line through the cabinet door.
      def classify_edges(model, segments, name)
        direction = Geom::Vector3d.new(*GroupProjection::VIEW_DIRS.fetch(name))
        result = { visible: [], hidden: [] }
        segments.each do |p, q|
          delta = p.zip(q).map { |a, b| b - a }
          length = Math.sqrt(delta.sum { |v| v * v })
          at = ->(t) { p.zip(delta).map { |a, b| a + b * t } }
          visible = lambda do |t|
            point = Geom::Point3d.new(at.call(t).map(&:mm)).offset(direction, 0.1.mm)
            model.raytest([point, direction], true).nil?
          end
          count = [[(length / 10.0).ceil, 2].max, 256].min
          samples = (0...count).map { |i| [(i + 0.5) / count, visible.call((i + 0.5) / count)] }
          start = 0.0
          state = samples.first[1]
          samples.each_cons(2) do |(a, sa), (b, sb)|
            next if sa == sb
            8.times do
              mid = (a + b) / 2
              visible.call(mid) == sa ? a = mid : b = mid
            end
            boundary = (a + b) / 2
            result[state ? :visible : :hidden] << [at.call(start), at.call(boundary)]
            start = boundary
            state = sb
          end
          result[state ? :visible : :hidden] << [at.call(start), q]
        end
        result
      end

      def collect(entity, transform, segments, boxes, materials)
        return if entity.respond_to?(:hidden?) && entity.hidden?
        return if entity.respond_to?(:layer) && !entity.layer.visible?
        materials << entity.material if entity.respond_to?(:material) && entity.material
        case entity
        when Sketchup::Group, Sketchup::ComponentInstance
          t = transform * entity.transformation
          children = entity.definition.entities
          children.each { |child| collect(child, t, segments, boxes, materials) }
          unless children.grep(Sketchup::Face).empty?
            corners = (0..7).map { |i| entity.definition.bounds.corner(i).transform(t).to_a.map(&:to_mm) }
            boxes << [(0..2).map { |i| corners.map { |p| p[i] }.min }, (0..2).map { |i| corners.map { |p| p[i] }.max }]
          end
        when Sketchup::Edge
          return if entity.soft? || entity.smooth?
          segments << [entity.start.position, entity.end.position].map { |p| p.transform(transform).to_a.map(&:to_mm) }
        end
      end

      def compose(data, title)
        doc = Layout::Document.new
        doc.page_info.width = 420.0 / 25.4
        doc.page_info.height = 297.0 / 25.4
        doc.pages.first.name = title
        w, d, h = data[:size]
        # One scale across all orthographic views, with fixed room for dimensions.
        scale = [125.0 / w, 62.0 / d, 155.0 / h, 47.0 / d].min
        draw_view(doc, data, 'top', 0, 1, 20, 22 + 62 - d * scale, scale, 101, 'TOP VIEW')
        draw_view(doc, data, 'front', 0, 2, 20, 120 + 155 - h * scale, scale, 287, 'ELEVATION')
        draw_view(doc, data, 'side', 1, 2, 183, 120 + 155 - h * scale, scale, 287, 'SIDE VIEW')
        iso = Layout::SketchUpModel.new(data[:skp], bounds(271, 22, 137, 194))
        iso.view = Layout::SketchUpModel::ISO_VIEW
        iso.perspective = false
        iso.scale = [117.0 / ((w + d) / Math.sqrt(2)), 174.0 / (h * Math.sqrt(2.0 / 3) + (w + d) / Math.sqrt(6))].min
        iso.render_mode = Layout::SketchUpModel::HYBRID_RENDER
        iso.display_background = false
        iso.line_weight = 0.35
        add(doc, iso)
        iso.render
        text(doc, title, 271, 10, 130, 10, size: 14)
        draw_materials(doc, data[:materials])
        text(doc, "단위 mm · 정투상 축척 1:#{(1.0 / scale).round(2)} · #{data[:internal] ? '실선: 보이는 선 / 점선: 가려진 선' : '보이는 선만 표시'}", 20, 291, 245, 6, size: 8)
        text(doc, "모델 변경 후 다시 출력\n문 열림·철물·가공 표시는 별도 작성", 271, 283, 135, 12, size: 8)
        doc
      end

      def draw_view(doc, data, name, ai, bi, x, y, scale, caption_y, label)
        width = data[:size][ai] * scale
        height = data[:size][bi] * scale
        [:hidden, :visible].each do |kind|
          next if kind == :hidden && !data[:internal]
          segments = GroupProjection.project(data[:views][name][kind], ai, bi, data[:lo][ai], data[:lo][bi])
          segments.each do |s|
            line(doc, x + s[:x1] * scale, y + height - s[:y1] * scale,
                 x + s[:x2] * scale, y + height - s[:y2] * scale,
                 dashed: kind == :hidden, color: kind == :hidden ? '#92968c' : '#43483f', weight: kind == :hidden ? 0.3 : 0.5)
          end
        end
        horizontal_dimension(doc, x, x + width, y, y - 12, data[:size][ai])
        vertical_dimension(doc, x + width, y, y + height, x + width + 12, data[:size][bi])
        if name == 'front'
          chain(data, ai, scale).each_cons(2) do |a, b|
            horizontal_dimension(doc, x + a * scale, x + b * scale, y, y - 5, b - a)
          end
          chain(data, bi, scale).each_cons(2) do |a, b|
            vertical_dimension(doc, x + width, y + height - b * scale, y + height - a * scale, x + width + 5, b - a)
          end
        end
        line(doc, x, caption_y, x + 62, caption_y, color: '#8b8d87')
        line(doc, x, caption_y - 2, x + 2, caption_y)
        line(doc, x + 2, caption_y, x, caption_y + 2)
        line(doc, x, caption_y + 2, x - 2, caption_y)
        line(doc, x - 2, caption_y, x, caption_y - 2)
        text(doc, label, x + 7, caption_y - 6, 55, 6, size: 11, bold: true)
      end

      # Interior boundaries closer than 10 paper mm are omitted to keep labels
      # legible. Overall dimensions are always retained at full precision.
      def chain(data, axis, scale)
        values = data[:boxes].flat_map { |a, b| [a[axis], b[axis]] }.map { |v| (v - data[:lo][axis]).round(3) }.uniq.sort
        total = data[:size][axis]
        keep = [0.0]
        values.each { |v| keep << v if (v - keep.last) * scale >= 10 && (total - v) * scale >= 10 }
        keep << total
        keep.length > 2 ? keep : []
      end

      def horizontal_dimension(doc, x1, x2, edge_y, y, value)
        line(doc, x1, edge_y, x1, y - 2, color: '#858780', weight: 0.25)
        line(doc, x2, edge_y, x2, y - 2, color: '#858780', weight: 0.25)
        line(doc, x1, y, x2, y, weight: 0.3)
        [x1, x2].each { |x| line(doc, x - 0.7, y + 0.7, x + 0.7, y - 0.7, weight: 0.6) }
        text(doc, number(value), (x1 + x2) / 2 - 12, y - 5, 24, 5, size: 10, color: '#ad5868', center: true)
      end

      def vertical_dimension(doc, edge_x, y1, y2, x, value)
        line(doc, edge_x, y1, x + 2, y1, color: '#858780', weight: 0.25)
        line(doc, edge_x, y2, x + 2, y2, color: '#858780', weight: 0.25)
        line(doc, x, y1, x, y2, weight: 0.3)
        [y1, y2].each { |y| line(doc, x - 0.7, y + 0.7, x + 0.7, y - 0.7, weight: 0.6) }
        cx = x + 2.5
        cy = (y1 + y2) / 2
        label = text(doc, number(value), cx - 12, cy - 2.5, 24, 5, size: 10, color: '#ad5868', center: true)
        label.transform!(Geom::Transformation2d.rotation(Geom::Point2d.new(cx / 25.4, cy / 25.4), -Math::PI / 2))
      end

      def draw_materials(doc, materials)
        if materials.empty?
          text(doc, '마감재 미지정', 285, 251, 112, 8, size: 10, color: '#96968e')
          return
        end
        materials.each_with_index do |mat, i|
          x = 280 + i * 42
          entity = if mat[:image]
                     Layout::Image.new(mat[:image], bounds(x, 239, 37, 30))
                   else
                     rect = Layout::Rectangle.new(bounds(x, 239, 37, 30))
                     style = rect.style
                     style.solid_filled = true
                     style.fill_color = mat[:color]
                     style.stroked = false
                     rect.style = style
                     rect
                   end
          add(doc, entity)
          text(doc, mat[:name][0, 32], x, 271, 38, 12, size: 9, color: '#ad5868')
        end
      end

      def number(value)
        format('%.1f', value).sub(/\.0\z/, '')
      end

      def bounds(x, y, w, h)
        Geom::Bounds2d.new(x / 25.4, y / 25.4, w / 25.4, h / 25.4)
      end

      def add(doc, entity)
        doc.add_entity(entity, doc.layers.first, doc.pages.first)
        entity
      end

      def line(doc, x1, y1, x2, y2, color: '#555951', weight: 0.4, dashed: false)
        return if (x1 - x2).abs + (y1 - y2).abs < 0.00001
        entity = Layout::Path.new(Geom::Point2d.new(x1 / 25.4, y1 / 25.4), Geom::Point2d.new(x2 / 25.4, y2 / 25.4))
        style = entity.style
        style.stroke_color = Sketchup::Color.new(color)
        style.stroke_width = weight
        style.stroke_pattern = dashed ? Layout::Style::STROKE_PATTERN_DASH : Layout::Style::STROKE_PATTERN_SOLID
        style.stroke_pattern_scale = 1.0
        entity.style = style
        add(doc, entity)
      end

      def text(doc, value, x, y, w, h, size: 8, color: '#353b34', bold: false, center: false)
        entity = Layout::FormattedText.new(value, bounds(x, y, w, h))
        style = entity.style
        style.font_family = '맑은 고딕'
        style.font_size = size.to_f
        style.text_color = Sketchup::Color.new(color)
        style.text_bold = bold
        style.text_alignment = Layout::Style::ALIGN_CENTER if center
        entity.apply_style(style)
        add(doc, entity)
      end
    end
  end
end
