module Kabinet
  module Output
    module Dimensions
      OFFSET = 150.mm   # how far dimension lines sit from the model face

      module_function

      # 뷰별 치수 태그 이름 (예: Kabinet_Dimensions_front)
      # 뷰마다 별도 태그를 써야 씬(페이지)별로 해당 뷰의 치수만 보인다.
      # (기존 버그: 태그 1개에 전 뷰 치수를 모두 그려 정면도에 측면 치수가
      #  겹쳐 보이고 zoom_extents 범위도 왜곡됐음)
      def tag_name_for(view_name)
        "#{Kabinet::Constants::DIMENSION_TAG_NAME}_#{view_name}"
      end

      def ensure_tag(model, name = Kabinet::Constants::DIMENSION_TAG_NAME)
        tag = model.layers[name]
        unless tag
          tag = model.layers.add(name)
          tag.color = Sketchup::Color.new(255, 0, 0) rescue nil
        end
        tag
      end

      # Draw overall W / H / D dimension lines for an assembly group.
      # view_name: :front | :right | :left | :top | :section
      def draw_for_assembly(assembly_group, view_name, model: Sketchup.active_model)
        tag   = ensure_tag(model, tag_name_for(view_name))
        bb    = assembly_group.bounds
        min_p = bb.min
        max_p = bb.max

        ents = model.entities

        case view_name
        when :front, :section
          # 정면도 / 단면도: 폭(X) + 높이(Z)
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(max_p.x, min_p.y, min_p.z),
                     ::Geom::Vector3d.new(0, -OFFSET, 0))
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, min_p.y, max_p.z),
                     ::Geom::Vector3d.new(-OFFSET, 0, 0))
        when :right, :left, :side
          # 측면도: 깊이(Y) + 높이(Z)
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, max_p.y, min_p.z),
                     ::Geom::Vector3d.new(0, 0, -OFFSET))
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, max_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, max_p.y, max_p.z),
                     ::Geom::Vector3d.new(0, OFFSET, 0))
        when :top
          # 평면도: 폭(X) + 깊이(Y)
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, max_p.z),
                     ::Geom::Point3d.new(max_p.x, min_p.y, max_p.z),
                     ::Geom::Vector3d.new(0, -OFFSET, 0))
          add_linear(ents, tag,
                     ::Geom::Point3d.new(max_p.x, min_p.y, max_p.z),
                     ::Geom::Point3d.new(max_p.x, max_p.y, max_p.z),
                     ::Geom::Vector3d.new(OFFSET, 0, 0))
        end
      end

      def add_linear(entities, tag, pt_start, pt_end, offset_vec)
        dim = entities.add_dimension_linear(pt_start, pt_end, offset_vec)
        dim.layer = tag if dim
        dim
      rescue StandardError => e
        puts "Kabinet Dimension error: #{e.message}"
        nil
      end

      # Kabinet 치수 태그(전 뷰)에 속한 모든 엔티티 제거 — 중복 방지.
      def clear_kabinet_dimensions(model)
        prefix = Kabinet::Constants::DIMENSION_TAG_NAME
        tags = model.layers.select { |l| l.name.start_with?(prefix) }
        return if tags.empty?
        to_erase = model.entities.select do |e|
          e.respond_to?(:layer) && tags.include?(e.layer)
        rescue StandardError
          false
        end
        model.entities.erase_entities(to_erase) unless to_erase.empty?
      rescue StandardError
        nil
      end

      # 특정 뷰 태그만 켜고 나머지 Kabinet 치수 태그는 끈다.
      # 반드시 page.update(레이어 플래그 포함) 직전에 호출.
      def show_only(model, view_name)
        prefix = Kabinet::Constants::DIMENSION_TAG_NAME
        target = tag_name_for(view_name)
        model.layers.each do |l|
          next unless l.name.start_with?(prefix)
          l.visible = (l.name == target)
        end
      rescue StandardError
        nil
      end

      def hide_all(model)
        prefix = Kabinet::Constants::DIMENSION_TAG_NAME
        model.layers.each do |l|
          l.visible = false if l.name.start_with?(prefix)
        end
      rescue StandardError
        nil
      end
    end
  end
end
