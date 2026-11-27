module Kabinet
  module Commands
    # 선택한 가구(그룹/컴포넌트)를 부재 역할별 레이어의 3D DXF(3DFACE)로 저장한다.
    # 안 보이는 부분이 겹쳐 보이지 않게 두 가지 보기 방식을 준다.
    #   split   : 장(모듈)마다 DXF 파일을 따로 저장(좌표는 원래 위치 그대로)
    #   section : 'x'(세로 단면) / 'y'(가로 단면) 평면으로 가구의 절반을 잘라내 내부를 보이게 한다
    module Export3d
      module_function

      MAX_DEPTH = 12
      MM = 25.4

      def selection_targets(model)
        model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      end

      # → [{ unit:, layer:, pts: [[x,y,z]mm, ...], hidden: [..] }]
      # base_tr: 선택이 놓인 편집 컨텍스트 -> 월드 변환(중첩 편집 중이면 부모 변환)
      def collect(targets, base_tr = Geom::Transformation.new, faces = false)
        recs = []
        targets.each { |t| walk(t, base_tr, nil, nil, recs, faces, 0) }
        recs
      end

      def edit_transform(model)
        model.respond_to?(:edit_transform) ? model.edit_transform : Geom::Transformation.new
      end

      def walk(entity, parent_tr, inherited, unit, recs, faces, depth)
        return if depth > MAX_DEPTH
        return if entity.respond_to?(:hidden?) && entity.hidden?
        return if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?
        tr = parent_tr * entity.transformation
        role = Kabinet::Persistence::Attributes.role(entity)
        name = entity.name.to_s
        name = entity.definition.name.to_s if name.empty? && entity.respond_to?(:definition)
        layer = Kabinet::Output::Dxf3d.layer_for(role, name) || inherited
        idx = Kabinet::Persistence::Attributes.get(entity, 'module_index')
        unit = idx.to_i unless idx.nil?
        ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
        ents.each do |c|
          if c.is_a?(Sketchup::Edge)
            add_edge(c, tr, layer || 'K3D_OTHER', unit, recs) unless skip_edge?(c)
          elsif c.is_a?(Sketchup::Face)
            add_face(c, tr, layer || 'K3D_OTHER', unit, recs) if faces && !(c.hidden? || (c.layer && !c.layer.visible?))
          elsif c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance)
            walk(c, tr, layer, unit, recs, faces, depth + 1)
          end
        end
      end

      # 숨김·소프트/스무스(곡면 분할선)·숨긴 태그의 모서리는 내보내지 않는다.
      def skip_edge?(e)
        e.hidden? || e.soft? || e.smooth? || (e.layer && !e.layer.visible?)
      end

      def add_edge(edge, tr, layer, unit, recs)
        a = edge.start.position.transform(tr)
        b = edge.end.position.transform(tr)
        recs << { type: :line, unit: unit, layer: layer,
                  pts: [[a.x.to_f * MM, a.y.to_f * MM, a.z.to_f * MM], [b.x.to_f * MM, b.y.to_f * MM, b.z.to_f * MM]] }
      end

      def add_face(face, tr, layer, unit, recs)
        mesh = face.mesh(0)
        pts = mesh.points.map do |p|
          q = p.transform(tr)
          [q.x.to_f * MM, q.y.to_f * MM, q.z.to_f * MM]
        end
        mesh.polygons.each do |poly|
          hidden = []
          poly.each_with_index { |i, k| hidden << k if i < 0 }
          recs << { type: :face, unit: unit, layer: layer, pts: poly.map { |i| pts[i.abs - 1] }, hidden: hidden }
        end
      end

      # 레코드 → Dxf3d. section: nil | 'x' | 'y'. 절단 위치는 이 묶음의 가운데.
      def to_dxf(recs, section = nil)
        dxf = Kabinet::Output::Dxf3d.new
        axis = { 'x' => 0, 'y' => 1 }[section.to_s]
        pos = nil
        keep = :le
        if axis
          vals = recs.flat_map { |r| r[:pts].map { |p| p[axis] } }
          pos = (vals.min + vals.max) / 2.0 unless vals.empty?
          keep = axis == 0 ? :le : :ge    # X: 오른쪽 반 제거(오른쪽에서 봄) / Y: 앞쪽 반 제거(앞에서 봄), 앞 = Y 작은 쪽 가정
        end
        recs.each do |r|
          if r[:type] == :line
            seg = axis && pos ? Kabinet::Output::Dxf3d.clip_segment(r[:pts][0], r[:pts][1], axis, pos, keep) : r[:pts]
            dxf.line(seg[0], seg[1], r[:layer]) if seg
          elsif axis && pos
            dxf.polygon(Kabinet::Output::Dxf3d.clip(r[:pts], axis, pos, keep), r[:layer])
          else
            dxf.face(r[:pts], r[:layer], r[:hidden])
          end
        end
        dxf
      end

      def base_name(targets)
        first = targets.first
        g = first.name.to_s
        g = first.definition.name.to_s if g.empty? && first.respond_to?(:definition)
        (g.empty? ? '가구' : g).gsub(/[\\\/\:\*\?\"\<\>\|]/, '_')
      end

      # opts: 'split' => true/false, 'section' => nil/'x'/'y', 'faces' => true 면(3DFACE)도 포함(기본: 모서리 선만)
      def run(opts = {}, model = Sketchup.active_model)
        targets = selection_targets(model)
        raise '그룹 또는 컴포넌트(가구)를 먼저 선택하세요.' if targets.empty?
        split = opts['split'] ? true : false
        section = %w[x y].include?(opts['section'].to_s) ? opts['section'].to_s : nil
        stamp = Time.now.strftime('%Y%m%d_%H%M%S')
        base = base_name(targets)
        path = ::UI.savepanel('3D CAD DXF 저장', Dir.home, "#{base}_3D_#{stamp}.dxf")
        return nil unless path
        path = Kabinet::Output::Sheet::Text.utf8(path)
        path += '.dxf' unless path.downcase.end_with?('.dxf')
        # module_index 는 가구마다 0 부터라 가구가 여럿이면 장 번호·절단 위치가 섞인다.
        if (split || section) && targets.length > 1
          raise '장별 분할·단면은 가구 하나만 선택했을 때 쓸 수 있습니다.'
        end
        recs = collect(targets, edit_transform(model), opts['faces'] ? true : false)
        raise '내보낼 선이 없습니다(숨김 상태이거나 모서리가 없는 선택).' if recs.empty?
        files = []
        groups = split ? recs.group_by { |r| r[:unit] } : { nil => recs }
        if split && groups.keys.compact.empty?
          raise '장(모듈)을 구분할 수 없습니다. Kabinet 으로 만든 가구를 선택하거나 「장별 분할」을 끄세요.'
        end
        groups.keys.sort_by { |k| k.nil? ? 1_000_000 : k }.each do |u|
          dxf = to_dxf(groups[u], section)
          next if dxf.face_count.zero?
          out = split ? path.sub(/\.dxf\z/i, u.nil? ? '_기타.dxf' : "_장#{u + 1}.dxf") : path
          dxf.write(Kabinet::Output::Sheet::Text.utf8(out))
          files << { path: out, faces: dxf.face_count, layers: dxf.layer_counts }
        end
        raise '절단 결과가 비었습니다.' if files.empty?
        files
      end

      # ── SketchUp 기본 DWG/DXF 내보내기(SketchUp Pro) ─────────────────────
      # 모델 형상을 SketchUp 이 직접 CAD 로 쓴다(삼각분할·변환 없음). 내보내기 동안만 부재 역할별 태그를
      # 붙여 레이어가 역할별로 나오게 하고, 끝나면 작업을 취소해 모델은 그대로 둔다.
      NATIVE_FORMATS = { 'dwg' => 'DWG', 'dxf' => 'DXF' }.freeze

      def assign_role_tags(entity, model, inherited = nil, depth = 0)
        return if depth > MAX_DEPTH
        role = Kabinet::Persistence::Attributes.role(entity)
        name = entity.name.to_s
        name = entity.definition.name.to_s if name.empty? && entity.respond_to?(:definition)
        layer = Kabinet::Output::Dxf3d.layer_for(role, name) || inherited
        entity.layer = (model.layers[layer] || model.layers.add(layer)) if layer
        ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
        ents.each do |c|
          next unless c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance)
          assign_role_tags(c, model, layer, depth + 1)
        end
      end

      def run_native(opts = {}, model = Sketchup.active_model)
        targets = selection_targets(model)
        raise '그룹 또는 컴포넌트(가구)를 먼저 선택하세요.' if targets.empty?
        fmt = NATIVE_FORMATS.key?(opts['format'].to_s) ? opts['format'].to_s : 'dwg'
        path = ::UI.savepanel("3D #{fmt.upcase} 저장 (SketchUp 기본 내보내기)", Dir.home,
                              "#{base_name(targets)}_3D_#{Time.now.strftime('%Y%m%d_%H%M%S')}.#{fmt}")
        return nil unless path
        path = Kabinet::Output::Sheet::Text.utf8(path)
        path += ".#{fmt}" unless path.downcase.end_with?(".#{fmt}")
        options = { show_summary: false, selectionset_only: true, triangulated_faces: false,
                    faces: true, edges: true, construction_geometry: false, dimensions: false, text: false }
        ok = nil
        model.start_operation('3D CAD 내보내기용 태그', true)
        begin
          targets.each { |t| assign_role_tags(t, model) } if opts['role_layers'] != false
          ok = model.export(path, options)
        ensure
          model.abort_operation
        end
        raise 'SketchUp 이 파일을 만들지 못했습니다. DWG/DXF 내보내기는 SketchUp Pro 에서만 됩니다.' unless ok && File.exist?(path)
        { path: path }
      end
    end
  end
end
