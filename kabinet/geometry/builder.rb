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

      # Build a rod (cylinder) along an axis. axis: :x | :y | :z
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
