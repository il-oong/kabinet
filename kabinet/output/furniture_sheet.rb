require 'fileutils'

module Kabinet
  module Output
    # A3 presentation sheet. Only the selected geometry is snapshotted; the
    # document being edited is never saved, reoriented, or stripped of entities.
    module FurnitureSheet
      module_function

      FRONT_AXES = { '-Y' => [0.0, -1.0], '+Y' => [0.0, 1.0], '-X' => [-1.0, 0.0], '+X' => [1.0, 0.0] }.freeze
      # 은선(가려진 선): 연한 회색 0.3 → 진한 파랑 0.5 (인쇄해도 구분되도록)
      HIDDEN_COLOR = '#1f5fa8'.freeze
      HIDDEN_WEIGHT = 0.5
      VISIBLE_COLOR = '#43483f'.freeze
      # 투영 뷰별 시선 방향(가구 로컬: x 오른쪽, y 뒤, z 위). 좌측면은 -X 쪽에서 본다.
      VIEW_DIRS_LOCAL = { 'front' => [0.0, -1.0, 0.0], 'side' => [1.0, 0.0, 0.0], 'side_left' => [-1.0, 0.0, 0.0], 'top' => [0.0, 0.0, 1.0] }.freeze
      DEFAULT_SITE = '경기도 수원시 영통구 광교호수공원로 80 광교아이파크 101동 4601호'.freeze
      ISO_TURNS = { 'front_right' => 0, 'front_left' => 90, 'back_left' => 180, 'back_right' => -90 }.freeze

      def axis_from_vector(vector)
        vector.x.abs > vector.y.abs ? (vector.x > 0 ? '+X' : '-X') : (vector.y > 0 ? '+Y' : '-Y')
      end

      def save_front(entity, axis)
        direction = FRONT_AXES.fetch(axis)
        local = Geom::Vector3d.new(direction[0], direction[1], 0).transform(entity.transformation.inverse)
        entity.set_attribute('kabinet_ep', 'front_local', local.to_a)
        entity.set_attribute('kabinet_ep', 'front_axis', axis)
      end

      def set_front(model = Sketchup.active_model)
        raise '그룹 편집을 닫고 가구 전체를 선택하세요.' if model.active_path
        targets = model.selection.to_a
        raise '가구 그룹 또는 컴포넌트를 선택하세요.' if targets.empty? || targets.any? { |e| !e.is_a?(Sketchup::Group) && !e.is_a?(Sketchup::ComponentInstance) }
        camera = model.active_view.camera
        outward = camera.eye - camera.target
        horizontal = Math.sqrt(outward.x**2 + outward.y**2)
        raise '가구의 앞쪽을 화면에서 바라본 뒤 다시 누르세요. 위에서 내려보는 화면은 사용할 수 없습니다.' if horizontal / outward.length < 0.25
        axis = axis_from_vector(outward)
        model.start_operation('가구 정면 지정', true)
        begin
          targets.each { |e| save_front(e, axis) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        "정면 저장: #{axis} 방향에서 바라본 모습. 좌우는 정면을 보는 사람 기준입니다."
      end

      def front_axis(targets)
        axes = targets.map do |e|
          local = e.get_attribute('kabinet_ep', 'front_local') || e.definition.get_attribute('kabinet_ep', 'front_local')
          if local.is_a?(Array) && local.length == 3 && local.all? { |n| n.is_a?(Numeric) && n.finite? }
            axis_from_vector(Geom::Vector3d.new(*local).transform(e.transformation))
          else
            e.get_attribute('kabinet_ep', 'front_axis', e.definition.get_attribute('kabinet_ep', 'front_axis', '-Y'))
          end
        end.uniq
        raise '서로 다른 정면 기준의 가구가 선택되었습니다. 가구마다 따로 출력하거나 정면을 다시 지정하세요.' unless axes.length == 1 && FRONT_AXES.key?(axes.first)
        axes.first
      end

      def front_status(model = Sketchup.active_model)
        targets = model.selection.to_a
        raise '가구 그룹 또는 컴포넌트를 선택하세요.' if targets.empty?
        "현재 정면: #{front_axis(targets)} 방향에서 바라본 모습. 평면도 화살표와 정면도를 확인하세요."
      end

      def reverse_front(model = Sketchup.active_model)
        targets = model.selection.to_a
        raise '가구 그룹 또는 컴포넌트를 선택하세요.' if targets.empty?
        old = front_axis(targets)
        axis = old.start_with?('+') ? old.sub('+', '-') : old.sub('-', '+')
        model.start_operation('가구 정면 반전', true)
        begin
          targets.each { |e| save_front(e, axis) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        "정면 반전 완료: #{axis} 방향에서 바라본 모습."
      end

      def orientation(axis)
        fx, fy = FRONT_AXES.fetch(axis)
        right = [-fy, fx]
        back = [-fx, -fy]
        to_local = ->(p) { [p[0] * right[0] + p[1] * right[1], p[0] * back[0] + p[1] * back[1], p[2]] }
        rotation = Geom::Transformation.axes(ORIGIN, Geom::Vector3d.new(right[0], right[1], 0), Geom::Vector3d.new(back[0], back[1], 0), Z_AXIS).inverse
        [to_local, rotation, right, back]
      end

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
        data = capture(model, targets, asset_dir, options.fetch('internal', true), options.fetch('iso_direction', 'front_right'))
        doc = compose(data, title, options)
        doc.save(path)
        begin
          doc.export(path.sub(/\.layout\z/i, '.pdf'))
        rescue StandardError => e
          raise "LayOut 파일은 저장했습니다: #{path}\nPDF 출력 실패: #{e.message}\nLayOut에서 파일을 열어 PDF로 내보내세요."
        end
        path
      end

      def capture(model, targets, dir, internal, iso_direction = 'front_right')
        raise '아이소 방향을 다시 선택하세요.' unless ISO_TURNS.key?(iso_direction)
        axis = front_axis(targets)
        to_local, rotation, right, back = orientation(axis)
        parts = []
        targets.each { |e| collect_parts(e, Geom::Transformation.new, parts) }
        mats = []
        segs = []
        boxes = []
        targets.each { |e| collect(e, Geom::Transformation.new, segs, boxes, mats) }
        raise '선택한 가구에 출력할 선이 없습니다.' if segs.empty?
        raise '선택한 형상이 너무 복잡합니다. 가구만 선택해 주세요.' if segs.length > 30_000
        points = segs.flatten(1).map(&to_local)
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
          %w[top side side_left front].each do |name|
            visible[name] = classify_edges(model, segs, name, right, back, to_local)
          end
          root = model.entities.add_group
          move = Geom::Transformation.translation(lo.zip(hi).map { |a, b| (-(a + b) / 2).mm })
          iso_turn = Geom::Transformation.rotation(ORIGIN, Z_AXIS, ISO_TURNS.fetch(iso_direction).degrees)
          targets.each do |e|
            copy = root.entities.add_instance(e.definition, iso_turn * move * rotation * e.transformation)
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
        local_box = lambda do |a, b|
          corners = (0..7).map { |i| to_local.call([(i & 1) != 0 ? b[0] : a[0], (i & 2) != 0 ? b[1] : a[1], (i & 4) != 0 ? b[2] : a[2]]) }
          [(0..2).map { |i| corners.map { |p| p[i] }.min }, (0..2).map { |i| corners.map { |p| p[i] }.max }]
        end
        local_parts = parts.map do |part|
          a, b = part[:lo], part[:hi]
          local_lo, local_hi = local_box.call(a, b)
          { role: part[:role], lo: local_lo, hi: local_hi }
        end
        local_boxes = boxes.map { |a, b| local_box.call(a, b) }
        { tiers: width_tiers(local_parts, lo), size: size, lo: lo, views: visible, boxes: local_boxes, skp: skp, snapshot_corners: snapshot_corners, materials: swatches, internal: internal, front_axis: axis }
      end

      # Sample each edge, then refine visible/occluded transitions. A partially
      # covered edge must not become one solid line through the cabinet door.
      def classify_edges(model, segments, name, right, back, to_local)
        local_direction = VIEW_DIRS_LOCAL.fetch(name)
        direction = Geom::Vector3d.new(right[0] * local_direction[0] + back[0] * local_direction[1], right[1] * local_direction[0] + back[1] * local_direction[1], local_direction[2])
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
            result[state ? :visible : :hidden] << [to_local.call(at.call(start)), to_local.call(at.call(boundary))]
            start = boundary
            state = sb
          end
          result[state ? :visible : :hidden] << [to_local.call(at.call(start)), to_local.call(q)]
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
          rod_silhouette(entity, t, segments)
          unless children.grep(Sketchup::Face).empty?
            corners = (0..7).map { |i| entity.definition.bounds.corner(i).transform(t).to_a.map(&:to_mm) }
            boxes << [(0..2).map { |i| corners.map { |p| p[i] }.min }, (0..2).map { |i| corners.map { |p| p[i] }.max }]
          end
        when Sketchup::Edge
          return if entity.soft? || entity.smooth?
          segments << [entity.start.position, entity.end.position].map { |p| p.transform(transform).to_a.map(&:to_mm) }
        end
      end

      # 옷걸이봉 같은 원통은 곡면 옆선이 soft/smooth 라 위 수집에서 빠져 은선에 안 나온다.
      # 축(X) 방향 윤곽선 4줄(위·아래·앞·뒤)을 직접 추가해 정면·측면·평면 어디서든 보이게 한다.
      def rod_silhouette(entity, transform, segments)
        return unless Kabinet::Persistence::Attributes.role(entity).to_s.include?('rod')
        bb = entity.definition.bounds
        cy = (bb.min.y + bb.max.y) / 2.0
        cz = (bb.min.z + bb.max.z) / 2.0
        r = [bb.max.y - bb.min.y, bb.max.z - bb.min.z].min / 2.0
        [[cy + r, cz], [cy - r, cz], [cy, cz + r], [cy, cz - r]].each do |y, z|
          segments << [bb.min.x, bb.max.x].map { |x| Geom::Point3d.new(x, y, z).transform(transform).to_a.map(&:to_mm) }
        end
      end

      # Explicit roles win. Unmarked front-facing thin panels can be doors;
      # remaining unmarked geometry forms one body until the user marks modules.
      def collect_parts(entity, parent, parts, inherited_role = 'auto')
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        return if entity.hidden? || !entity.layer.visible?
        transform = parent * entity.transformation
        role = entity.get_attribute('kabinet_ep', 'drawing_role', inherited_role)
        children = entity.definition.entities
        record = lambda do |points|
          return if points.empty?
          corners = points.map { |p| p.transform(transform).to_a.map(&:to_mm) }
          parts << { role: role, lo: (0..2).map { |i| corners.map { |p| p[i] }.min }, hi: (0..2).map { |i| corners.map { |p| p[i] }.max } }
        end
        if %w[body ep].include?(role)
          record.call((0..7).map { |i| entity.definition.bounds.corner(i) })
          return
        end
        # A door container is not a single door: descend into each child and
        # split loose geometry into connected shells (including imported groups).
        children.each { |child| collect_parts(child, transform, parts, role) }
        seen = {}
        children.grep(Sketchup::Face).each do |face|
          next if seen[face.entityID] || face.hidden? || !face.layer.visible?
          faces = face.all_connected.grep(Sketchup::Face)
          faces.each { |f| seen[f.entityID] = true }
          record.call(faces.reject { |f| f.hidden? || !f.layer.visible? }.flat_map { |f| f.vertices.map(&:position) })
        end
      end

      def width_tiers(parts, origin)
        front = parts.map { |p| p[:lo][1] }.min
        left = parts.map { |p| p[:lo][0] }.min
        right = parts.map { |p| p[:hi][0] }.max
        bottom = parts.map { |p| p[:lo][2] }.min
        top = parts.map { |p| p[:hi][2] }.max
        doors, ep, bodies, remaining = [], [], [], []
        parts.each do |part|
          a, b = part[:lo], part[:hi]
          role = part[:role]
          if role == 'door' || (role == 'auto' && a[1] <= front + 2.1 && b[1] - a[1] <= 35 && b[0] - a[0] > 50 && b[2] - a[2] > 50)
            doors << part if b[0] - a[0] > 50 && b[2] - a[2] > 50
          elsif role == 'ep' || (role == 'auto' && b[0] - a[0] <= 35 &&
                b[1] - a[1] > 50 && b[2] - a[2] >= (top - bottom) * 0.9 &&
                ((a[0] - left).abs < 0.1 || (b[0] - right).abs < 0.1))
            ep << [a[0] - origin[0], b[0] - origin[0]]
          elsif role == 'body'
            bodies << [a[0] - origin[0], b[0] - origin[0]]
          else
            remaining << part
          end
        end
        unless remaining.empty?
          bodies << [remaining.map { |p| p[:lo][0] }.min - origin[0], remaining.map { |p| p[:hi][0] }.max - origin[0]]
        end
        # Stacked wide lower fronts must not overlap the upper door chain.
        # Dimension one horizontal row: the highest row of actual door panels.
        unless doors.empty?
          top = doors.map { |p| p[:hi][2] }.max
          top_doors = doors.select { |p| (p[:hi][2] - top).abs < 1 }
          cut = top - top_doors.map { |p| p[:hi][2] - p[:lo][2] }.min / 2
          doors = doors.select { |p| p[:lo][2] < cut && p[:hi][2] >= cut }
        end
        doors = doors.sort_by { |p| p[:lo][0] }
        # Interior facing door edges receive 1mm each; exposed outer edges 2mm.
        # Keep measured widths: never force equal widths or absorb model errors.
        doors = doors.each_with_index.map do |p, i|
          previous = i > 0 ? doors[i - 1] : nil
          following = doors[i + 1]
          left_gap = previous && p[:lo][0] - previous[:hi][0]
          right_gap = following && following[:lo][0] - p[:hi][0]
          left_allowance = left_gap && left_gap >= -0.1 && left_gap <= 10 ? 1 : 2
          right_allowance = right_gap && right_gap >= -0.1 && right_gap <= 10 ? 1 : 2
          [p[:lo][0] - origin[0] - left_allowance, p[:hi][0] - origin[0] + right_allowance]
        end
        normalize = ->(items) { items.map { |a,b| [a.round(3),b.round(3)] }.uniq.sort }
        { doors: normalize.call(doors), bodies: normalize.call(ep + bodies) }
      end

      def door_runs(doors)
        doors.sort_by(&:first).each_with_object([]) do |door, runs|
          if runs.empty? || door[0] - runs.last.last[1] > 10
            runs << [door]
          else
            runs.last << door
          end
        end
      end

      DEFAULT_PAGES = %w[iso front side].freeze

      def pages_option(options)
        pages = options['pages']
        pages = DEFAULT_PAGES if pages.nil?
        pages = DEFAULT_PAGES & Array(pages).map(&:to_s)
        raise '출력할 쪽(입체도 / 정면·평면 / 측면)을 하나 이상 선택하세요.' if pages.empty?
        pages
      end

      # 쪽 구성은 SheetLayout 이 계산한다(겹침 없음, 쪽마다 표준 배율 하나).
      # 여기서는 그 사각형·배율대로 LayOut 요소를 놓는 얇은 어댑터만 둔다.
      def compose(data, title, options = {})
        # Keep LayOut's tool defaults in the document, so dimensions drawn
        # later by hand match the dimensions generated below.
        doc = Layout::Document.open(File.join(__dir__, 'drawing_template.layout'))
        doc.units = Layout::Document::DECIMAL_MILLIMETERS
        doc.precision = 1.0
        doc.page_info.width = SheetLayout::PAGE_W / 25.4
        doc.page_info.height = SheetLayout::PAGE_H / 25.4
        plan = SheetLayout.plan(data[:size], 'pages' => pages_option(options))
        # 공유 레이어에 그리면 쪽끼리 겹쳐 인쇄되므로, 쪽 전용(비공유) 레이어에 그린다.
        doc.layers.add('가구 도면 내용', false)
        layer = doc.layers[doc.layers.length - 1]
        plan[:pages].each_with_index do |pg, i|
          page = i.zero? ? doc.pages.first : doc.pages.add(SheetLayout.clean_text(pg[:title]))
          page.name = SheetLayout.clean_text("#{title} #{pg[:number]}-#{pg[:title]}")
          PageCanvas.new(page, layer).draw_page(doc, data, pg, plan, title, options)
        end
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

      def caption(doc, x, caption_y, label, width = 62.0)
        line(doc, x, caption_y, x + width, caption_y, color: '#8b8d87')
        line(doc, x, caption_y - 2, x + 2, caption_y)
        line(doc, x + 2, caption_y, x, caption_y + 2)
        line(doc, x, caption_y + 2, x - 2, caption_y)
        line(doc, x - 2, caption_y, x, caption_y - 2)
        text(doc, label, x + 7, caption_y - 6, width - 7, 6, size: 9, bold: true)
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
        paths = page_of(doc).entities.to_a.reject { |entity| before.any? { |old| old == entity } }
        group = Layout::Group.new(paths)
        group.set_scale_factor(scale, Layout::Document::DECIMAL_MILLIMETERS, Layout::Group::RESIZE_BEHAVIOR_NONE)
        group.scale_precision = 1.0
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
        style.set_dimension_units(Layout::Style::DECIMAL_MILLIMETERS, 1.0)
        style.suppress_dimension_units = true
        style.stroke_width = 0.2
        [Layout::Style::DIMENSION_LINE, Layout::Style::DIMENSION_START_EXTENSION_LINE,
         Layout::Style::DIMENSION_END_EXTENSION_LINE, Layout::Style::DIMENSION_LEADER_LINE].each do |type|
          stroke = style.get_sub_style(type)
          stroke.stroke_width = 0.2
          stroke.stroke_color = Sketchup::Color.new('#70756d')
          stroke.start_arrow_size = 0.6
          stroke.end_arrow_size = 0.6
          style.set_sub_style(type, stroke)
        end
        style.stroke_color = Sketchup::Color.new('#555951')
        label = style.get_sub_style(Layout::Style::DIMENSION_TEXT)
        label.font_family = '맑은 고딕'
        label.font_size = 10.0
        label.text_bold = true
        label.text_color = Sketchup::Color.new('#863c49')
        style.set_sub_style(Layout::Style::DIMENSION_TEXT, label)
        dim.style = style
        add(doc, dim)
      end

      def number(value)
        format('%.0f', value)
      end

      def bounds(x, y, w, h)
        Geom::Bounds2d.new(x / 25.4, y / 25.4, w / 25.4, h / 25.4)
      end

      # 그릴 페이지: PageCanvas 는 @page 를 지정, 그 외에는 첫 페이지
      def page_of(doc)
        @page || doc.pages.first
      end

      def add(doc, entity)
        doc.add_entity(entity, doc.layers.first, page_of(doc))
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
        entity = Layout::FormattedText.new(SheetLayout.clean_text(value), bounds(x, y, w, h))
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

    # 한 쪽(Layout page)에 그리는 도우미 — FurnitureSheet 의 선·글자·치수 도구를 쪽 전용으로 재사용한다.
    class PageCanvas
      include FurnitureSheet
      public :line, :text, :horizontal_dimension, :vertical_dimension

      HIDDEN_VIEWS = %w[front side_r side_l].freeze   # 평면도에는 점선을 넣지 않는다(과다 방지)
      HIDDEN_MIN_PAPER = 3.0                          # 종이 3mm 미만 점선 조각은 생략

      def initialize(page, layer = nil)
        @page = page
        @layer = layer
      end

      def add(doc, entity)
        doc.add_entity(entity, @layer || doc.layers.first, @page)
        entity
      end

      def draw_page(doc, data, pg, plan, title, options)
        header(doc, pg, title)
        if pg[:id] == 'iso'
          draw_iso_page(doc, data, pg, title, options)
        else
          pg[:views].each { |v| draw_plan_view(doc, data, v, options) }
        end
        foot_note(doc, data, pg)
        title_block(doc, plan, pg, title, options)
      end

      def header(doc, pg, title)
        text(doc, "#{title} - #{pg[:title]}", 15, 8, 300, 10, size: 14, bold: true)
        text(doc, "SCALE #{SheetLayout.scale_label(pg[:scale])}", 330, 8, 75, 10, size: 13, bold: true)
        line(doc, 15, 22, 405, 22, weight: 0.5)
      end

      def foot_note(doc, data, pg)
        hidden = data[:internal] && pg[:views].any? { |v| HIDDEN_VIEWS.include?(v[:name]) } ? ' · 파란 점선: 가려진 선' : ''
        note = pg[:scale] ? "단위 mm · SCALE #{SheetLayout.scale_label(pg[:scale])} (이 쪽의 모든 뷰 동일)#{hidden}" : '단위 mm · 입체도는 축척 없음(N.T.S) · 치수는 정면도·평면도·측면도 쪽 참고'
        note += " · 구간 #{pg[:window][0].round}~#{pg[:window][1].round} mm" if pg[:window]
        text(doc, note, 15, 262.5, 390, 5, size: 8)
      end

      def title_block(doc, plan, pg, title, options)
        site = options.fetch('site', '').to_s.strip
        site = FurnitureSheet::DEFAULT_SITE if site.empty?
        furniture = options.fetch('furniture_name', '').to_s.strip
        furniture = title if furniture.empty?
        date = options.fetch('drawing_date', '').to_s.strip
        date = Time.now.strftime('%Y-%m-%d') if date.empty?
        values = {
          'furniture' => furniture, 'site' => site, 'date' => date, 'author' => options.fetch('author', '').to_s.strip,
          'scale' => SheetLayout.scale_label(pg[:scale]), 'page' => "#{pg[:number]} / #{pg[:total]}"
        }
        cells = plan[:title_block]
        t = SheetLayout::TITLE_BLOCK
        [t[:y], t[:y] + t[:h] / 2, t[:y] + t[:h]].each { |y| line(doc, t[:x], y, t[:x] + t[:w], y, weight: 0.5) }
        line(doc, t[:x], t[:y], t[:x], t[:y] + t[:h], weight: 0.5)
        line(doc, t[:x] + t[:w], t[:y], t[:x] + t[:w], t[:y] + t[:h], weight: 0.5)
        cells.each do |c|
          x, y, w, h = c[:rect]
          line(doc, x + w, y, x + w, y + h, weight: 0.3)
          value = values[c[:key]].to_s
          text(doc, c[:label], x + 2, y + 1.2, 19, h - 1.5, size: 8, bold: true)
          text(doc, value.empty? ? '-' : value, x + 22, y + 1.0, w - 24, h - 1.5, size: value.length > 36 ? 8 : 9, bold: true)
        end
      end

      def draw_plan_view(doc, data, v, options)
        x, y, w, h = v[:rect]
        den = v[:den]
        scale = 1.0 / den
        name = v[:name]
        ai, bi = SheetLayout::AXES.fetch(name)
        win = v[:clip]
        extent = data[:size][ai]
        source = { 'side_r' => 'side', 'side_l' => 'side_left' }.fetch(name, name)
        before = page_of(doc).entities.to_a
        kinds = [:visible]
        kinds.unshift(:hidden) if data[:internal] && HIDDEN_VIEWS.include?(name)
        kinds.each do |kind|
          GroupProjection.project(data[:views][source][kind], ai, bi, data[:lo][ai], data[:lo][bi]).each do |s|
            seg = [s[:x1], s[:y1], s[:x2], s[:y2]]
            seg = [extent - seg[0], seg[1], extent - seg[2], seg[3]] if name == 'side_l'
            seg = win ? SheetLayout.clip_segment(seg, win[0], win[1]) : seg
            next unless seg
            next if kind == :hidden && Math.hypot(seg[2] - seg[0], seg[3] - seg[1]) * scale < HIDDEN_MIN_PAPER
            line(doc, x + seg[0] * scale, y + h - seg[1] * scale, x + seg[2] * scale, y + h - seg[3] * scale,
                 dashed: kind == :hidden, color: kind == :hidden ? HIDDEN_COLOR : VISIBLE_COLOR, weight: kind == :hidden ? HIDDEN_WEIGHT : 0.5)
          end
        end
        draw_surface_marks(doc, options, x, y, w, h) if name == 'top' && !win
        scaled_geometry(doc, before, scale, v[:label])
        draw_dimensions(doc, data, v, scale)
        label = "#{v[:label]}  SCALE #{SheetLayout.scale_label(den)}"
        caption(doc, v[:outer][0], y + h + 6 + SheetLayout::CAPTION_H - 1, label, [v[:outer][2], 72.0].max)
      end

      # 가로 치수줄 단: 구분(chain) → 도어 → EP·몸통 → 전체. 세로는 오른쪽(좌측면은 왼쪽)에 전체 + 구분.
      def draw_dimensions(doc, data, v, scale)
        x, y, w, h = v[:rect]
        name = v[:name]
        ai, bi = SheetLayout::AXES.fetch(name)
        win = v[:clip]
        rows = []
        chain_a = chain(data, ai, scale)
        if win
          chain_a = (chain_a + win).select { |c| c >= win[0] - 1e-6 && c <= win[1] + 1e-6 }.map { |c| c.round(3) }.uniq.sort
        end
        chain_a = chain_a.map { |c| name == 'side_l' ? data[:size][ai] - c : c }.sort if name == 'side_l'
        if chain_a.length > 2 || (win && chain_a.length >= 2)
          rows << lambda do |off|
            chain_a.each_cons(2) { |a, b| horizontal_dimension(doc, x + (a - (win ? win[0] : 0)) * scale, x + (b - (win ? win[0] : 0)) * scale, y, y - off, b - a) }
          end
        end
        if name == 'front' && !win
          door_rows = door_runs(data[:tiers][:doors])
          unless door_rows.empty?
            rows << lambda do |off|
              door_rows.each do |run|
                a, b = run.first[0], run.last[1]
                dim = horizontal_dimension(doc, x + a * scale, x + b * scale, y, y - off, b - a)
                next if run.length == 1
                label = dim.text
                label.plain_text = "#{number(b - a)}/#{run.length} EQ"
                dim.text = label
                dim.custom_text = true
              end
            end
          end
          unless data[:tiers][:bodies].empty?
            rows << lambda do |off|
              data[:tiers][:bodies].each { |a, b| horizontal_dimension(doc, x + a * scale, x + b * scale, y, y - off, b - a) }
            end
          end
        end
        rows << ->(off) { horizontal_dimension(doc, x, x + w, y, y - off, data[:size][ai]) } unless win
        rows.each_with_index { |row, i| row.call(6.0 + 7.0 * i) }
        # 세로
        side = name == 'side_l' ? -1 : 1
        edge = name == 'side_l' ? x : x + w
        vertical_dimension(doc, edge, y, y + h, edge + side * 12, data[:size][bi])
        if name == 'front'
          chain(data, bi, scale).each_cons(2) do |a, b|
            vertical_dimension(doc, edge, y + h - b * scale, y + h - a * scale, edge + side * 5, b - a)
          end
        end
      end

      # 평면도 노출면/벽면 기호(옵션). 범례 글자는 입체도 쪽 메모 칸에 둔다.
      def draw_surface_marks(doc, options, x, y, width, depth)
        choices = [['left', x - 3, y + depth / 2], ['right', x + width + 3, y + depth / 2], ['back', x + width / 2, y - 3]]
        choices.each do |key, px, py|
          value = options.fetch("surface_#{key}", 'none')
          if value == 'open'
            line(doc, px - 1.3, py - 2, px + 1.3, py, color: '#c67b12', weight: 0.8)
            line(doc, px + 1.3, py, px - 1.3, py + 2, color: '#c67b12', weight: 0.8)
            line(doc, px - 1.3, py + 2, px - 1.3, py - 2, color: '#c67b12', weight: 0.8)
          elsif value == 'wall'
            [-1, 1].each { |offset| line(doc, px + offset - 0.8, py + 2, px + offset + 0.8, py - 2, weight: 0.6) }
          end
        end
      end

      def surface_legend(options)
        names = { 'left' => '좌측', 'right' => '우측', 'back' => '뒤쪽' }
        names.map do |key, name|
          value = options.fetch("surface_#{key}", 'none')
          next unless %w[open wall].include?(value)
          "#{name}: #{value == 'open' ? '△ 노출' : '// 벽면'}"
        end.compact
      end

      def draw_iso_page(doc, data, pg, title, options)
        w, d, h = data[:size]
        bx, by, bw, bh = pg[:boxes][:iso]
        iso = Layout::SketchUpModel.new(data[:skp], bounds(bx, by, bw, bh))
        iso.view = Layout::SketchUpModel::ISO_VIEW
        iso.perspective = false
        iso.scale = [(bw - 20.0) / ((w + d) / Math.sqrt(2)), (bh - 20.0) / (h * Math.sqrt(2.0 / 3) + (w + d) / Math.sqrt(6))].min
        iso.render_mode = Layout::SketchUpModel::HYBRID_RENDER
        iso.display_background = false
        iso.line_weight = 0.35
        add(doc, iso)
        fit_model(iso, data[:snapshot_corners])
        mx, my, mw, = pg[:boxes][:materials]
        text(doc, '마감재', mx, my, mw, 7, size: 11, bold: true)
        line(doc, mx, my + 8, mx + mw, my + 8)
        draw_materials(doc, data[:materials], mx, my + 11, mw)
        nx, ny, nw, nh = pg[:boxes][:memo]
        text(doc, '메모 / 시공 유의사항', nx, ny, nw, 7, size: 11, bold: true)
        line(doc, nx, ny + 8, nx + nw, ny + 8)
        memo = options.fetch('memo', '').to_s.strip
        memo = '메모를 입력하세요.' if memo.empty?
        text(doc, memo, nx, ny + 10, nw, nh - 10, size: 10, color: '#222222', bold: true)
        ox, oy, ow, oh = pg[:boxes][:notes]
        legend = surface_legend(options)
        lines = ['도면 구성: 1쪽 입체도 · 2쪽 정면도/평면도 · 3쪽 측면도 (가구가 작으면 2쪽에 함께)']
        lines.concat(legend)
        text(doc, lines.join("\n"), ox, oy, ow, oh, size: 8)
      end

      def draw_materials(doc, materials, x0, y0, width)
        if materials.empty?
          text(doc, '마감재 미지정', x0, y0 + 4, width, 8, size: 10, color: '#96968e')
          return
        end
        sw = (width - 6.0) / 3
        materials.each_with_index do |mat, i|
          x = x0 + i * (sw + 3)
          entity = if mat[:image]
                     Layout::Image.new(mat[:image], bounds(x, y0, sw, 21))
                   else
                     rect = Layout::Rectangle.new(bounds(x, y0, sw, 21))
                     style = rect.style
                     style.solid_filled = true
                     style.fill_color = mat[:color]
                     style.stroked = false
                     rect.style = style
                     rect
                   end
          add(doc, entity)
          text(doc, mat[:name][0, 32], x, y0 + 23, sw, 9, size: 8, color: '#ad5868')
        end
      end
    end
  end
end
