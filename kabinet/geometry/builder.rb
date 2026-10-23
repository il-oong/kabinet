module Kabinet
  module Geometry
    module Builder
      # Build an axis-aligned box (W along X, D along Y, T along Z) inside `parent_entities`,
      # rooted at the given origin transform. Returns the wrapping Group.
      #
      # All inputs in SU Length (call .mm before passing).
      def self.box(parent_entities, width, depth, thickness, transform,
                   role: nil, label: nil, material_name: nil, locked: false, attrs: {})
        group = parent_entities.add_group
        ents  = group.entities

        p0 = ::Geom::Point3d.new(0, 0, 0)
        p1 = ::Geom::Point3d.new(width, 0, 0)
        p2 = ::Geom::Point3d.new(width, depth, 0)
        p3 = ::Geom::Point3d.new(0, depth, 0)
        face = ents.add_face(p0, p1, p2, p3)
        face.reverse! if face.normal.z < 0
        face.pushpull(thickness)

        group.transformation = transform if transform

        if role
          Kabinet::Persistence::Attributes.set_role(group, role,
                                                    width: width.to_f, depth: depth.to_f, thickness: thickness.to_f)
        end
        attrs.each { |k, v| Kabinet::Persistence::Attributes.set(group, k, v) }
        group.name = label if label
        # 컬러 미적용 — 사용자가 SketchUp 재질 편집기로 직접 지정
        # material_name 파라미터는 커트리스트 소재 태깅용으로만 보존
        Kabinet::Persistence::Attributes.set(group, 'material_hint', material_name.to_s) if material_name
        group.locked = true if locked
        group
      end

      # 모서리를 둥글게(R) 만든 판 — W는 X, D는 Y(앞면 y=0), 두께는 Z.
      # radius: SU Length. corners: 둥글게 할 모서리 ['fl','fr','bl','br'] (앞왼/앞오/뒤왼/뒤오).
      # 반경은 판의 짧은 변 절반을 넘지 않게 줄인다. 반경이 0이거나 corners가 비면 Builder.box와 동일.
      ROUND_SEGMENTS = 10

      def self.rounded_box(parent_entities, width, depth, thickness, transform, radius:, corners:,
                           role: nil, label: nil, material_name: nil, locked: false, attrs: {})
        corners = Array(corners).map(&:to_s) & %w[fl fr bl br]
        r = [radius.to_f, [width.to_f, depth.to_f].min / 2.0].min
        return box(parent_entities, width, depth, thickness, transform, role: role, label: label,
                   material_name: material_name, locked: locked, attrs: attrs) if r <= 0 || corners.empty?

        group = parent_entities.add_group
        w = width.to_f
        d = depth.to_f
        # 반시계 방향으로 4모서리를 돌며 (코너 중심, 시작각)을 잡는다
        spec = [['fl', r, r, Math::PI], ['fr', w - r, r, 1.5 * Math::PI],
                ['br', w - r, d - r, 0.0], ['bl', r, d - r, 0.5 * Math::PI]]
        pts = []
        spec.each do |name, cx, cy, a0|
          if corners.include?(name)
            (0..ROUND_SEGMENTS).each do |i|
              a = a0 + (Math::PI / 2.0) * i / ROUND_SEGMENTS
              pts << ::Geom::Point3d.new(cx + r * Math.cos(a), cy + r * Math.sin(a), 0)
            end
          else
            sx = name.end_with?('l') ? 0 : w
            sy = name.start_with?('f') ? 0 : d
            pts << ::Geom::Point3d.new(sx, sy, 0)
          end
        end
        face = group.entities.add_face(pts)
        face.reverse! if face.normal.z < 0
        face.pushpull(thickness)

        group.transformation = transform if transform
        if role
          Kabinet::Persistence::Attributes.set_role(group, role,
                                                    width: width.to_f, depth: depth.to_f, thickness: thickness.to_f)
        end
        attrs.each { |k, v| Kabinet::Persistence::Attributes.set(group, k, v) }
        group.name = label if label
        Kabinet::Persistence::Attributes.set(group, 'material_hint', material_name.to_s) if material_name
        group.locked = true if locked
        group
      end

      # Build a rod (cylinder) along an axis. axis: :x | :y | :z
      # 측판 — 앞면(Y=0)에서 notch_d 깊이로, 각 notch 의 [z0, z1] 구간을 따낸 판.
      # YZ 단면을 그려 +X 로 width 만큼 밀어낸다. notches: [[z0, z1], ...] (SU Length, 오름차순·겹침 없음)
      def self.notched_side(parent_entities, width, depth, height, notch_d, notches, transform,
                            role: nil, label: nil, material_name: nil)
        group = parent_entities.add_group
        yz = [[0, 0]]
        notches.sort_by(&:first).each do |z0, z1|
          z1 = [z1, height].min
          yz << [0, z0] << [notch_d, z0] << [notch_d, z1]
          yz << [0, z1] if z1 < height
        end
        yz << [0, height] unless yz.last[1] >= height
        yz << [depth, height] << [depth, 0]
        face = group.entities.add_face(yz.map { |y, z| ::Geom::Point3d.new(0, y, z) })
        face.reverse! if face.normal.x < 0
        face.pushpull(width)
        group.transformation = transform if transform
        if role
          Kabinet::Persistence::Attributes.set_role(group, role,
                                                    width: width.to_f, depth: depth.to_f, thickness: height.to_f)
        end
        group.name = label if label
        Kabinet::Persistence::Attributes.set(group, 'material_hint', material_name.to_s) if material_name
        group
      end

      def self.rod(parent_entities, length, diameter, transform, axis: :y, role: nil, label: nil)
        group = parent_entities.add_group
        ents  = group.entities
        radius = diameter / 2.0
        center = ::Geom::Point3d.new(0, 0, 0)

        normal = case axis
                 when :x then ::Geom::Vector3d.new(1, 0, 0)
                 when :y then ::Geom::Vector3d.new(0, 1, 0)
                 when :z then ::Geom::Vector3d.new(0, 0, 1)
                 end

        circle_edges = ents.add_circle(center, normal, radius, 24)
        face = ents.add_face(circle_edges)
        face.reverse! if face.normal.dot(normal) < 0
        face.pushpull(length)

        group.transformation = transform if transform
        Kabinet::Persistence::Attributes.set_role(group, role) if role
        group.name = label if label
        group
      end

      def self.lookup_or_create_material(name)
        model = Sketchup.active_model
        return nil unless model
        mat = model.materials[name]
        return mat if mat
        mat = model.materials.add(name)
        case name.to_s.downcase
        when /door/  then mat.color = ::Sketchup::Color.new(245, 235, 220)
        when /ep/    then mat.color = ::Sketchup::Color.new(180, 140, 100)
        when /back/  then mat.color = ::Sketchup::Color.new(150, 120, 90)
        when /shelf/ then mat.color = ::Sketchup::Color.new(220, 200, 170)
        when /drawer_front/ then mat.color = ::Sketchup::Color.new(245, 235, 220)
        when /drawer_box/   then mat.color = ::Sketchup::Color.new(200, 180, 150)
        when /top/   then mat.color = ::Sketchup::Color.new(230, 215, 180)
        when /rod/   then mat.color = ::Sketchup::Color.new(200, 200, 200)
        else              mat.color = ::Sketchup::Color.new(220, 200, 170)
        end
        mat
      end
    end
  end
end
