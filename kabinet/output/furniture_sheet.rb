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
        memo = options.fetch('memo', '').to_s
        raise '메모는 180자, 8줄 이내로 입력하세요.' if memo.length > 180 || memo.lines.count > 8
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
        doc = compose(data, title, options)
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
          %w[top front side elevation].each do |name|
            visible[name] = classify_edges(model, segs, name)
          end
          root = model.entities.add_group
          move = Geom::Transformation.translation(lo.zip(hi).map { |a, b| (-(a + b) / 2).mm })
          targets.each do |e|
            copy = root.entities.add_instance(e.definition, move * e.transformation)
            copy.material = e.material if e.material
          end
          snapshot_corners = (0..7).map { |i| root.definition.bounds.corner(i).to_a }
          center = root.bounds.center
          model.active_view.camera = Sketchup::Camera.new(center.offset(Geom::Vector3d.new(1, -1, 1)), center, Z_AXIS, false)
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
        { size: size, lo: lo, views: visible, boxes: boxes, skp: skp, snapshot_corners: snapshot_corners, materials: swatches, internal: internal }
      end

      # Sample each edge, then refine visible/occluded transitions. A partially
      # covered edge must not become one solid line through the cabinet door.
      def classify_edges(model, segments, name)
        direction = Geom::Vector3d.new(*(name == 'elevation' ? [0.45, -1.0, 0.3] : GroupProjection::VIEW_DIRS.fetch(name)))
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

      def compose(data, title, options = {})
        doc = Layout::Document.new
        doc.units = Layout::Document::DECIMAL_MILLIMETERS
        doc.precision = 0.1
        doc.page_info.width = 420.0 / 25.4
        doc.page_info.height = 297.0 / 25.4
        doc.pages.first.name = title
        w, d, h = data[:size]
        # One scale across all orthographic views, with fixed room for dimensions.
        scale = [130.0 / (w + d * 0.45), 175.0 / (h + d * 0.3), 47.0 / d, 1.0].min
        draw_view(doc, data, 'top', 0, 1, 20, 22, scale, 22 + d * scale + 12, 'TOP VIEW')
        draw_elevation(doc, data, 20, 275, scale)
        draw_view(doc, data, 'side', 1, 2, 183, 120 + 155 - h * scale, scale, 287, 'SIDE VIEW')
        iso = Layout::SketchUpModel.new(data[:skp], bounds(271, 22, 137, 194))
        iso.view = Layout::SketchUpModel::ISO_VIEW
        iso.perspective = false
        iso.scale = [117.0 / ((w + d) / Math.sqrt(2)), 174.0 / (h * Math.sqrt(2.0 / 3) + (w + d) / Math.sqrt(6))].min
        iso.render_mode = Layout::SketchUpModel::HYBRID_RENDER
        iso.display_background = false
        iso.line_weight = 0.35
        add(doc, iso)
        fit_model(iso, data[:snapshot_corners])
        iso.render
        text(doc, title, 271, 10, 130, 10, size: 14)
        draw_materials(doc, data[:materials])
        draw_notes(doc, title, options)
        text(doc, "단위 mm · 정면 축척 1:#{(1.0 / scale).round(2)} · 깊이는 사선 축약 · #{data[:internal] ? '점선: 가려진 선' : '실선: 보이는 선'}", 20, 291, 245, 6, size: 8)

        doc
      end

      # Measure the actual projected corners, rather than assuming an ideal
      # isometric camera or a particular shape. Includes a 10mm paper margin.
      def fit_model(viewport, corners)
        box = viewport.bounds
        cx = (box.upper_left.x + box.lower_right.x) / 2
        cy = (box.upper_left.y + box.lower_right.y) / 2
        rx = (box.lower_right.x - box.upper_left.x) / 2 - 10.0 / 25.4
        ry = (box.lower_right.y - box.upper_left.y) / 2 - 10.0 / 25.4
        5.times do
          viewport.render
          points = corners.map { |p| viewport.model_to_paper_point(Geom::Point3d.new(p)) }
          dx = points.map { |p| (p.x - cx).abs }.max
          dy = points.map { |p| (p.y - cy).abs }.max
          return if dx <= rx && dy <= ry
          factor = [rx / [dx, 0.0001].max, ry / [dy, 0.0001].max, 0.95].min
          viewport.scale = viewport.scale * factor * 0.98
        end
        raise '입체도 영역을 맞추지 못했습니다. 선택한 가구의 형상을 확인하세요.'
      end

      # Cabinet projection: X/Z keep their true scale and depth recedes up/right.
      # Thus elevation dimensions stay readable without pretending the depth
      # diagonal is a true-scale orthographic measurement.
      def draw_elevation(doc, data, x, bottom, scale)
        w, d, h = data[:size]
        front_top = bottom - h * scale
        dx = d * 0.45 * scale
        dy = d * 0.3 * scale
        project = lambda do |point|
          px, py, pz = point.zip(data[:lo]).map { |a, b| a - b }
          [x + (px + py * 0.45) * scale, bottom - (pz + py * 0.3) * scale]
        end
        before_geometry = doc.pages.first.entities.to_a
        [:hidden, :visible].each do |kind|
          next if kind == :hidden && !data[:internal]
          seen = {}
          data[:views]['elevation'][kind].each do |a, b|
            p, q = project.call(a), project.call(b)
            key = [p.map { |v| v.round(4) }, q.map { |v| v.round(4) }].sort
            next if seen[key]
            seen[key] = true
            line(doc, *p, *q, dashed: kind == :hidden, color: kind == :hidden ? '#92968c' : '#43483f', weight: kind == :hidden ? 0.3 : 0.5)
          end
        end
        scaled_geometry(doc, before_geometry, scale, 'ELEVATION')
        horizontal_dimension(doc, x, x + w * scale, front_top, front_top - dy - 14, w)
        chain(data, 0, scale).each_cons(2) do |a, b|
          horizontal_dimension(doc, x + a * scale, x + b * scale, front_top, front_top - dy - 6, b - a)
        end
        vertical_dimension(doc, x + w * scale + dx, front_top - dy, bottom - dy, x + w * scale + dx + 14, h)
        chain(data, 2, scale).each_cons(2) do |a, b|
          vertical_dimension(doc, x + w * scale + dx, bottom - b * scale - dy, bottom - a * scale - dy, x + w * scale + dx + 6, b - a)
        end
        text(doc, "깊이 #{number(d)}", x + w * scale + 2, front_top - dy - 9, 36, 5, size: 9, color: '#ad5868')
        caption(doc, x, 287, 'ELEVATION')
      end

      def draw_view(doc, data, name, ai, bi, x, y, scale, caption_y, label)
        width = data[:size][ai] * scale
        height = data[:size][bi] * scale
        before_geometry = doc.pages.first.entities.to_a
        [:hidden, :visible].each do |kind|
          next if kind == :hidden && !data[:internal]
          segments = GroupProjection.project(data[:views][name][kind], ai, bi, data[:lo][ai], data[:lo][bi])
          segments.each do |s|
            line(doc, x + s[:x1] * scale, y + height - s[:y1] * scale,
                 x + s[:x2] * scale, y + height - s[:y2] * scale,
                 dashed: kind == :hidden, color: kind == :hidden ? '#92968c' : '#43483f', weight: kind == :hidden ? 0.3 : 0.5)
          end
        end
        scaled_geometry(doc, before_geometry, scale, label)
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
        caption(doc, x, caption_y, label)
      end

      def caption(doc, x, caption_y, label)
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

      def scaled_geometry(doc, before, scale, name)
        paths = doc.pages.first.entities.to_a.reject { |entity| before.any? { |old| old == entity } }
        group = Layout::Group.new(paths)
        group.set_scale_factor(scale, Layout::Document::DECIMAL_MILLIMETERS, Layout::Group::RESIZE_BEHAVIOR_NONE)
        group.scale_precision = 0.1
        group
      end

      def horizontal_dimension(doc, x1, x2, edge_y, y, value)
        dimension(doc, [x1, edge_y], [x2, edge_y], [x1, y], [x2, y], (x2 - x1).abs / value)
      end

      def vertical_dimension(doc, edge_x, y1, y2, x, value)
        dimension(doc, [edge_x, y1], [edge_x, y2], [x, y1], [x, y2], (y2 - y1).abs / value)
      end

      def dimension(doc, a, b, ea, eb, scale)
        point = ->(p) { Geom::Point2d.new(p[0] / 25.4, p[1] / 25.4) }
        dim = Layout::LinearDimension.new(point.call(a), point.call(b), 5.0 / 25.4)
        dim.start_extent_point = point.call(ea)
        dim.end_extent_point = point.call(eb)
        dim.start_offset_length = 1.0 / 25.4
        dim.end_offset_length = 1.0 / 25.4
        dim.auto_scale = false
        dim.scale = scale
        dim.custom_text = false
        style = dim.style
        style.set_dimension_units(Layout::Style::DECIMAL_MILLIMETERS, 0.1)
        style.suppress_dimension_units = true
        style.stroke_width = 0.35
        style.stroke_color = Sketchup::Color.new('#555951')
        label = style.get_sub_style(Layout::Style::DIMENSION_TEXT)
        label.font_family = '맑은 고딕'
        label.font_size = 10.0
        label.text_bold = true
        label.text_color = Sketchup::Color.new('#984857')
        style.set_sub_style(Layout::Style::DIMENSION_TEXT, label)
        dim.style = style
        add(doc, dim)
      end

      def draw_notes(doc, title, options)
        text(doc, '메모 / 시공 유의사항', 183, 20, 78, 8, size: 11, bold: true)
        line(doc, 183, 29, 261, 29)
        memo = options.fetch('memo', '').to_s.strip
        memo = '메모를 입력하세요.' if memo.empty?
        text(doc, memo, 183, 32, 78, 48, size: 11, color: '#222222', bold: true)
        rows = [
          ['가구명', options.fetch('furniture_name', '').to_s.strip],
          ['현장정보', options.fetch('site', '').to_s.strip],
          ['제작날짜', options.fetch('drawing_date', '').to_s.strip],
          ['작성자', options.fetch('author', '').to_s.strip]
        ]
        rows[0][1] = title if rows[0][1].empty?
        rows[2][1] = Time.now.strftime('%Y-%m-%d') if rows[2][1].empty?
        rows.each_with_index do |(label, value), i|
          y = 253 + i * 9
          line(doc, 271, y, 408, y)
          text(doc, label, 273, y + 1.5, 24, 7, size: 10, bold: true)
          text(doc, value.empty? ? '입력하세요' : value, 299, y + 1.5, 107, 7, size: value.length > 28 ? 8 : 10, bold: true)
        end
        line(doc, 271, 289, 408, 289)
        [271, 297, 408].each { |x| line(doc, x, 253, x, 289) }
      end

      def draw_materials(doc, materials)
        if materials.empty?
          text(doc, '마감재 미지정', 285, 234, 112, 8, size: 10, color: '#96968e')
          return
        end
        materials.each_with_index do |mat, i|
          x = 280 + i * 42
          entity = if mat[:image]
                     Layout::Image.new(mat[:image], bounds(x, 221, 37, 21))
                   else
                     rect = Layout::Rectangle.new(bounds(x, 221, 37, 21))
                     style = rect.style
                     style.solid_filled = true
                     style.fill_color = mat[:color]
                     style.stroked = false
                     rect.style = style
                     rect
                   end
          add(doc, entity)
          text(doc, mat[:name][0, 32], x, 243, 38, 9, size: 9, color: '#ad5868')
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
