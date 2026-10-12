module Kabinet
  module Commands
    # 면 클릭 → 두께 인식 → 18T 패널 자동 생성.
    #
    # - 판재(슬랩)의 면을 클릭하면 반대편 평행면까지의 거리를 두께로 인식하고,
    #   클릭한 면을 기준면으로 유지한 채 18T로 다시 만든다 (원본이 단순 판재 그룹이면 교체).
    # - 두께 없는 면(사각형만 그린 상태)은 보이는 쪽(카메라 방향)으로 18T를 만든다.
    module FacePanel
      module_function

      SLAB_TOL_MM = 0.3

      # raytest 결과 path([..., Face]) → 면 정보 해시. 면이 아니면 nil.
      def analyze(path, model)
        face = path.last
        return nil unless face.is_a?(::Sketchup::Face) && face.valid?
        tr = instance_transform(path[0...-1])
        loops_w = face.loops.sort_by { |l| l.outer? ? 0 : 1 }.map do |lp|
          lp.vertices.map { |v| v.position.transform(tr) }
        end
        normal_w = face.normal.transform(tr).normalize
        opp = opposite(face)
        dir_w = nil
        found_mm = nil
        scale = 1.0
        if opp
          dir_local = face.normal.clone
          dir_local.reverse! if opp[:offset] < 0   # 반대면이 있는 쪽(= 솔리드 안쪽)으로
          dir_w = dir_local.transform(tr).normalize
          scale = dir_local.transform(tr).length / dir_local.length
          found_mm = Kabinet::Core::Fitting.len_mm(opp[:distance]) * scale
        end
        container = path.length >= 2 && instance?(path[-2]) ? path[-2] : nil
        in_assembly = path[0...-1].any? { |e| Kabinet::Persistence::Attributes.assembly?(e) }
        # 그룹 안에 들어가 판재 면을 직접 클릭한 경우(면이 지금 편집 중인 곳에 있음):
        # 새 패널을 만들지 않고 반대쪽 면을 밀고 당겨 그 자리에서 두께를 바꾼다.
        resize = !opp.nil? && path[0...-1] == (model.active_path || []) && !opp[:face].nil?
        # Kabinet 가구 부재 면(가구 밖에서 클릭): 부재는 건드리지 않고 보이는 쪽(바깥)으로 새 패널을 붙인다.
        # (안쪽으로 만들면 기존 부재와 정확히 겹쳐 쓸모가 없음 — 재생성 시 부재 두께는 폼에서 수정)
        dir_w = nil if in_assembly && !resize
        {
          face: face, path: path, loops_w: loops_w, normal_w: normal_w,
          dir_w: dir_w, found_mm: found_mm, container: container,
          in_assembly: in_assembly, resize: resize, opp_face: opp && opp[:face], scale: scale,
          replaceable: !in_assembly && container && !container.locked? &&
                       same_context?(path[0...-2], model) &&
                       slab_container?(container, path, dir_w, found_mm)
        }
      end

      # 같은 컨텍스트에서 반대 방향 평행·겹침 면 중 가장 가까운 것 → 두께.
      def opposite(face)
        owner = face.parent
        return nil unless owner.respond_to?(:entities)
        n = face.normal.normalize
        base = face.vertices.first.position
        best = nil
        owner.entities.grep(::Sketchup::Face).each do |other|
          next if other == face || !other.valid?
          next unless other.normal.normalize.dot(n) < -0.9999
          off = (other.vertices.first.position - base).dot(n)
          next if off.abs < 0.1.mm
          next unless overlaps?(face, other)
          best = { distance: off.abs, offset: off, face: other } if best.nil? || off.abs < best[:distance]
        end
        best
      end

      def overlaps?(a, b)
        sample_inside?(a, b) || sample_inside?(b, a)
      end

      # a의 꼭짓점·무게중심을 b 평면에 투영했을 때 b 면 안에 들어오는 점이 있는가
      def sample_inside?(a, b)
        pts = a.vertices.map(&:position)
        pts << ::Geom::Point3d.new(pts.sum(&:x) / pts.size, pts.sum(&:y) / pts.size, pts.sum(&:z) / pts.size)
        pts.any? do |p|
          c = b.classify_point(p.project_to_plane(b.plane))
          c != ::Geom::PT_OUTSIDE && c != ::Geom::PT_NOT_ON_PLANE
        end
      end

      def instance?(e)
        e.is_a?(::Sketchup::Group) || e.is_a?(::Sketchup::ComponentInstance)
      end

      def instance_transform(elements)
        elements.inject(Kabinet::Geometry::Transforms::IDENTITY) do |acc, e|
          instance?(e) ? acc * e.transformation : acc
        end
      end

      # 교체(삭제)는 현재 편집 컨텍스트에 직접 놓인 판재만 허용한다.
      # 다른 그룹/컴포넌트 안에 중첩된 경우 정의가 공유될 수 있어 지우면 다른 인스턴스까지 사라진다.
      def same_context?(ancestors, model)
        ancestors == (model.active_path || [])
      end

      # 컨테이너 전체 외곽이 감지 두께와 같으면 "단순 판재 그룹"
      def slab_container?(container, path, dir_w, found_mm)
        return false unless dir_w && found_mm
        parent_tr = instance_transform(path[0...-2])
        bb = container.bounds
        proj = (0..7).map { |k| ::Geom::Vector3d.new(*bb.corner(k).transform(parent_tr).to_a).dot(dir_w) }
        extent_mm = Kabinet::Core::Fitting.len_mm(proj.max - proj.min)
        (extent_mm - found_mm).abs <= SLAB_TOL_MM
      end

      # 패널 생성. flip: 방향 반전. 반환: 새 그룹
      def build(model, info, thickness_mm, flip: false)
        t = thickness_mm.to_f
        raise '두께가 올바르지 않습니다.' unless t > 0 && t <= 100
        face = info[:face]
        raise '면이 더 이상 존재하지 않습니다.' unless face.valid?
        return resize_in_place(model, info, t) if info[:resize] && !flip

        dir_w = info[:dir_w]
        unless dir_w
          # 두께 없는 면 → 카메라 쪽으로 돌출
          eye = model.active_view.camera.direction
          dir_w = info[:normal_w].dot(eye) < 0 ? info[:normal_w] : info[:normal_w].reverse
        end
        dir_w = dir_w.reverse if flip

        inv = model.edit_transform.inverse
        dir_a = dir_w.transform(inv)
        loops_a = info[:loops_w].map { |lp| lp.map { |p| p.transform(inv) } }

        t_label = t.round(1).to_s.sub(/\.0\z/, '')
        model.start_operation("Kabinet — 면 → #{t_label}T 패널", true)
        begin
          grp = model.active_entities.add_group
          ents = grp.entities
          nf = ents.add_face(loops_a.first)
          loops_a[1..-1].each do |lp|
            hole = ents.add_face(lp)
            hole.erase! if hole && hole.valid? && hole != nf
          end
          dist = t.mm
          nf.pushpull(nf.normal.dot(dir_a) >= 0 ? dist : -dist)

          grp.name = "패널 #{t_label}T"
          Kabinet::Persistence::Attributes.set_role(grp, 'free_panel', thickness: dist.to_f)
          Kabinet::Persistence::Attributes.set(grp, 'thickness_mm', t)

          remove_source(info, flip)
          model.commit_operation
          model.selection.clear
          model.selection.add(grp)
          grp
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      # 그룹 안 판재: 클릭한 면은 그대로 두고 반대쪽 면을 밀어 두께를 t(mm)로 맞춘다.
      def resize_in_place(model, info, t)
        face = info[:face]
        opp = info[:opp_face]
        raise '반대쪽 면을 찾지 못했습니다. 다시 클릭하세요.' unless opp && opp.valid?
        delta_mm = (t - info[:found_mm].to_f) / info[:scale].to_f
        return face if delta_mm.abs < 0.01
        # 반대면 법선이 판재 바깥(클릭한 면 반대쪽)을 향하면 +가 두꺼워짐
        away = opp.vertices.first.position - face.vertices.first.position
        sign = opp.normal.dot(away) >= 0 ? 1 : -1
        t_label = t.round(1).to_s.sub(/\.0\z/, '')
        model.start_operation("Kabinet — 판재 두께 #{t_label}T로 변경", true)
        begin
          opp.pushpull(sign * delta_mm.mm)
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        face
      end

      # 원본 처리: 단순 판재 그룹은 교체(삭제), 고립된 두께 없는 면은 삭제. 그 외는 유지.
      def remove_source(info, flip)
        return if flip && info[:dir_w] # 반대 방향으로 만든 경우 원본 유지 (겹침 방지는 사용자 몫)
        if info[:replaceable]
          info[:container].erase!
        elsif info[:dir_w].nil? && info[:container].nil?
          face = info[:face]
          edges = face.edges
          return unless edges.all? { |e| e.faces.size == 1 }
          face.erase!
          edges.each { |e| e.erase! if e.valid? && e.faces.empty? }
        end
      end
    end
  end
end
