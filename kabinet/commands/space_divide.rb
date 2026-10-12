module Kabinet
  module Commands
    # 공간 클릭 → 6방향 레이캐스트로 둘러싼 판재를 찾아 내부 공간을 인식 →
    # 칸막이(기본 18T) 균등 분할 + 도어 균등 분할을 한 번에 생성.
    module SpaceDivide
      module_function

      PROBE_OFFSET_MM = 0.5

      # raytest 결과(point, path)와 시선 방향으로 공간을 인식한다.
      # 반환: { origin:, axes: [xa, ya, za] (월드 단위벡터), space: SpaceDivider 결과 }
      # 인식 실패 시 Kabinet::Core::SpaceDivider::Error
      def probe(model, point, path, ray_dir)
        face = path.last
        unless face.is_a?(::Sketchup::Face)
          raise Kabinet::Core::SpaceDivider::Error, '면 위를 클릭하세요.'
        end
        inst_tr = Kabinet::Commands::FacePanel.instance_transform(path[0...-1])
        xa = inst_tr.xaxis.normalize
        ya = inst_tr.yaxis.normalize
        za = xa.cross(ya).normalize

        normal = face.normal.transform(inst_tr).normalize
        normal = normal.reverse if normal.dot(ray_dir) > 0   # 카메라를 향한 쪽 = 공간 안쪽
        origin = point.offset(normal, PROBE_OFFSET_MM.mm)

        axes = [xa, ya, za]
        hits = {}
        axes.each_with_index do |axis, i|
          [-1, 1].each do |sign|
            dir = sign < 0 ? axis.reverse : axis
            r = model.raytest([origin, dir], true)
            hits[[i, sign]] = hit_info(r, origin, axes, i) if r
          end
        end
        space = Kabinet::Core::SpaceDivider.resolve_space(hits)
        { origin: origin, axes: axes, space: space }
      end

      # 충돌 부재의 외곽 박스(원점 기준 로컬 mm)와 두께
      def hit_info(result, origin, axes, axis_index)
        pt, hpath = result
        container = hpath.length >= 2 && Kabinet::Commands::FacePanel.instance?(hpath[-2]) ? hpath[-2] : nil
        if container
          tr = Kabinet::Commands::FacePanel.instance_transform(hpath[0...-2])
          bb = container.bounds
        else
          tr = Kabinet::Commands::FacePanel.instance_transform(hpath[0...-1])
          bb = hpath.last.bounds
        end
        rel = (0..7).map do |k|
          v = bb.corner(k).transform(tr) - origin
          axes.map { |a| Kabinet::Core::Fitting.len_mm(v.dot(a)) }
        end
        bmin = (0..2).map { |i| rel.map { |p| p[i] }.min }
        bmax = (0..2).map { |i| rel.map { |p| p[i] }.max }
        {
          dist: Kabinet::Core::Fitting.len_mm((pt - origin).length),
          bmin: bmin, bmax: bmax,
          thick: container ? bmax[axis_index] - bmin[axis_index] : 0.0
        }
      end

      # 공간 박스의 월드 꼭짓점 8개 (미리보기용)
      def box_corners(probe)
        lo = probe[:space][:lo]
        hi = probe[:space][:hi]
        [0, 1].product([0, 1], [0, 1]).map do |ix, iy, iz|
          world_point(probe, [ix == 0 ? lo[0] : hi[0], iy == 0 ? lo[1] : hi[1], iz == 0 ? lo[2] : hi[2]])
        end
      end

      # 원점 기준 로컬 mm → 월드 좌표
      def world_point(probe, rel_mm)
        o = probe[:origin]
        xa, ya, za = probe[:axes]
        d = rel_mm.map(&:mm)
        ::Geom::Point3d.new(o.x + xa.x * d[0] + ya.x * d[1] + za.x * d[2],
                            o.y + xa.y * d[0] + ya.y * d[1] + za.y * d[2],
                            o.z + xa.z * d[0] + ya.z * d[1] + za.z * d[2])
      end

      # settings: { axis: 'x'|'z', cells:, thickness:, door_mode:, door_thickness: }
      # 반환: { group:, plan: }
      def build(model, probe, settings)
        plan = Kabinet::Core::SpaceDivider.plan(
          probe[:space],
          axis: settings[:axis], cells: settings[:cells], thickness: settings[:thickness],
          door_mode: settings[:door_mode], door_thickness: settings[:door_thickness]
        )
        xa, ya, za = probe[:axes]
        corner_w = world_point(probe, probe[:space][:lo])
        frame = ::Geom::Transformation.axes(corner_w, xa, ya, za)

        model.start_operation('Kabinet — 공간 분할 + 도어', true)
        begin
          root = model.active_entities.add_group
          root.transformation = model.edit_transform.inverse * frame
          root.name = "공간 분할 (#{settings[:cells]}칸)"
          Kabinet::Persistence::Attributes.set_role(root, 'free_divider')
          Kabinet::Persistence::Attributes.set(root, 'cells', settings[:cells].to_i)

          plan[:partitions].each { |p| add_box(root, p, settings[:thickness]) }
          plan[:doors].each { |d| add_box(root, d, settings[:door_thickness]) }

          model.commit_operation
          model.selection.clear
          model.selection.add(root)
          { group: root, plan: plan }
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def add_box(root, item, thickness_mm)
        pos = item[:pos]
        dims = item[:dims]
        tr = ::Geom::Transformation.new(::Geom::Point3d.new(pos[0].mm, pos[1].mm, pos[2].mm))
        grp = Kabinet::Geometry::Builder.box(root.entities, dims[0].mm, dims[1].mm, dims[2].mm, tr)
        is_door = item[:role].start_with?('door')
        grp.name = is_door ? "도어 #{item[:role][/\d+\z/]}" : (item[:role].start_with?('free_shelf') ? "선반 #{item[:role][/\d+\z/]}" : "칸막이 #{item[:role][/\d+\z/]}")
        Kabinet::Persistence::Attributes.set_role(grp, item[:role])
        Kabinet::Persistence::Attributes.set(grp, 'thickness_mm', thickness_mm.to_f)
        Kabinet::Persistence::Attributes.set(grp, 'size_mm', dims.map { |v| v.round(1) }.join(' x '))
        grp
      end
    end
  end
end
