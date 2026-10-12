module Kabinet
  module Commands
    # 선택한 하부장들 위에 주방 상판을 한 번에 설치한다.
    # - 각 가구의 평면 외곽(도어 앞면 포함, 손잡이 제외)과 윗면 높이를 읽는다.
    # - 정면은 Kabinet 가구/저장 정면(kabinet_ep front_local)이 있으면 그것, 없으면 로컬 -Y.
    # - 90° 단위로 꺾인 배치(일자/ㄱ자/ㄷ자)를 하나의 상판으로 잇는다.
    module Countertop
      module_function

      MATERIALS = {
        '인조대리석 (화이트)'    => [242, 241, 236],
        '엔지니어드스톤 (그레이)' => [196, 196, 192],
        '세라믹 (다크)'         => [72, 72, 74],
        '원목 (오크)'           => [190, 150, 105],
        '스테인리스'            => [182, 185, 188],
        'PET (화이트)'          => [248, 248, 246]
      }.freeze

      def material_names(model = Sketchup.active_model)
        (MATERIALS.keys + model.materials.map(&:display_name)).uniq
      end

      # opts: thickness, material, front_overhang, side_overhang, back_gap, height_mode('auto'|'fixed'), top_height
      def run(opts, model: Sketchup.active_model)
        t = opts['thickness'].to_f
        raise '상판 두께를 3~100mm로 입력하세요.' unless t >= 3 && t <= 100
        targets = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        raise '상판을 올릴 하부장(그룹/컴포넌트)을 모두 선택하세요.' if targets.empty?

        parent = model.edit_transform
        first_tr = parent * targets.first.transformation
        xa = flat(first_tr.xaxis)
        raise '첫 번째 가구의 방향을 읽을 수 없습니다.' unless xa
        ya = Z_AXIS.cross(xa).normalize
        origin = first_tr.origin

        items = targets.map do |inst|
          tr = parent * inst.transformation
          ix = flat(tr.xaxis)
          unless ix && (ix.dot(xa).abs > 0.999 || ix.dot(xa).abs < 0.001)
            raise "‘#{label(inst)}’ 가구가 다른 가구와 90° 단위로 정렬되어 있지 않습니다. 각도가 같은 가구끼리 따로 설치하세요."
          end
          bb = local_bounds(inst)
          raise "‘#{label(inst)}’ 안에 형상이 없습니다." if bb.empty?
          pts = (0..7).map { |k| bb.corner(k).transform(tr) }
          us = pts.map { |p| mm((p - origin).dot(xa)) }
          vs = pts.map { |p| mm((p - origin).dot(ya)) }
          front = flat(front_vector(inst).transform(tr))
          raise "‘#{label(inst)}’의 정면 방향을 읽을 수 없습니다." unless front
          fu = front.dot(xa)
          fv = front.dot(ya)
          f = fu.abs > fv.abs ? [fu.positive? ? 1 : -1, 0] : [0, fv.positive? ? 1 : -1]
          { rect: [us.min, vs.min, us.max, vs.max], front: f, top: pts.map { |p| mm(p.z) }.max }
        end

        plan = Kabinet::Core::Countertop.plan(
          items,
          front_overhang: opts.fetch('front_overhang', 20).to_f,
          side_overhang: opts.fetch('side_overhang', 0).to_f,
          back_gap: opts.fetch('back_gap', 0).to_f
        )
        bottom = if opts['height_mode'] == 'fixed'
                   h = opts['top_height'].to_f
                   raise '상판 윗면 높이를 입력하세요.' unless h > t
                   h - t
                 else
                   plan[:top]
                 end

        build(model, plan, t, bottom, origin, xa, ya, opts['material'].to_s)
      end

      def build(model, plan, t, bottom_mm, origin, xa, ya, material_name)
        model.start_operation('Kabinet — 주방 상판 설치', true)
        begin
          grp = model.active_entities.add_group
          o = Geom::Point3d.new(origin.x, origin.y, bottom_mm.mm)
          grp.transformation = model.edit_transform.inverse * Geom::Transformation.axes(o, xa, ya, Z_AXIS)
          ents = grp.entities
          plan[:cells].each do |x0, y0, x1, y1|
            ents.add_face([x0.mm, y0.mm, 0], [x1.mm, y0.mm, 0], [x1.mm, y1.mm, 0], [x0.mm, y1.mm, 0])
          end
          # 조각 사이 이음선 제거 → 한 장의 면으로 합침
          ents.grep(Sketchup::Edge).each do |e|
            next unless e.valid? && e.faces.size == 2
            e.erase! if e.faces[0].normal.parallel?(e.faces[1].normal)
          end
          ents.grep(Sketchup::Face).each do |f|
            next unless f.valid?
            f.reverse! if f.normal.z < 0
            f.pushpull(t.mm)
          end
          grp.name = "주방 상판 #{t.round(1).to_s.sub(/\.0\z/, '')}T"
          grp.material = material(model, material_name) unless material_name.strip.empty?
          Kabinet::Persistence::Attributes.set_role(grp, 'countertop', thickness: t.mm.to_f)
          Kabinet::Persistence::Attributes.set(grp, 'thickness_mm', t)
          model.commit_operation
          model.selection.clear
          model.selection.add(grp)
          area = plan[:cells].sum { |c| (c[2] - c[0]) * (c[3] - c[1]) } / 1_000_000.0
          msg = "주방 상판 설치 완료 — #{t.round(1)}T, 윗면 높이 #{(bottom_mm + t).round}mm, 면적 #{area.round(2)}㎡"
          plan[:warnings].empty? ? msg : "#{msg}\n#{plan[:warnings].join("\n")}"
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def material(model, name)
        mat = model.materials.find { |m| m.display_name == name || m.name == name }
        return mat if mat
        mat = model.materials.add(name)
        mat.color = Sketchup::Color.new(*(MATERIALS[name] || [230, 230, 228]))
        mat
      end

      # 가구 로컬 외곽 (손잡이 제외 — 손잡이 돌출까지 상판을 내밀지 않도록, 하위 그룹 끝까지)
      def local_bounds(inst)
        bb = Geom::BoundingBox.new
        walk(inst.definition.entities, Geom::Transformation.new, bb)
        bb
      end

      def walk(ents, tr, bb)
        ents.each do |e|
          if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            next if e.hidden? || handle?(e)
            walk(e.definition.entities, tr * e.transformation, bb)
          elsif e.is_a?(Sketchup::Edge) && !e.hidden?
            e.vertices.each { |v| bb.add(v.position.transform(tr)) }
          end
        end
      end

      def handle?(e)
        Kabinet::Persistence::Attributes.role(e).to_s.start_with?('handle')
      end

      def front_vector(inst)
        local = inst.get_attribute('kabinet_ep', 'front_local') ||
                inst.definition.get_attribute('kabinet_ep', 'front_local')
        local ? Geom::Vector3d.new(*local) : Geom::Vector3d.new(0, -1, 0)
      end

      def flat(v)
        h = Geom::Vector3d.new(v.x, v.y, 0)
        h.length < 1e-9 ? nil : h.normalize
      end

      def mm(len)
        len.to_f * 25.4
      end

      def label(inst)
        n = inst.name.to_s
        n = inst.definition.name.to_s if n.empty?
        n.empty? ? '가구' : n
      end
    end
  end
end
