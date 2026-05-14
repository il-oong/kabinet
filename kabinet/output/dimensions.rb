module Kabinet
  module Output
    module Dimensions
      OFFSET = 150.mm   # how far dimension lines sit from the model face

      module_function

      # Ensure the dimension tag exists and is visible.
      def ensure_tag(model)
        tag_name = Kabinet::Constants::DIMENSION_TAG_NAME
        tag = model.layers[tag_name]
        unless tag
          tag = model.layers.add(tag_name)
          tag.color = Sketchup::Color.new(255, 0, 0)
        end
        tag
      end

      # Draw overall W / H / D dimension lines for an assembly group.
      # view_name: :front | :side | :top
      def draw_for_assembly(assembly_group, view_name, model: Sketchup.active_model)
        tag   = ensure_tag(model)
        bb    = assembly_group.bounds
        w     = bb.width    # X extent
        d     = bb.depth    # Y extent
        h     = bb.height   # Z extent
        min_p = bb.min
        max_p = bb.max

        ents  = model.entities

        case view_name
        when :front, :section
          # 정면도 / 단면도: 폭(X) + 높이(Z)
          # 폭 — 하단
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(max_p.x, min_p.y, min_p.z),
                     ::Geom::Vector3d.new(0, -OFFSET, 0))
          # 높이 — 좌측
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, min_p.y, max_p.z),
                     ::Geom::Vector3d.new(-OFFSET, 0, 0))
        when :right, :left, :side
          # 측면도: 깊이(Y) + 높이(Z)
          # 깊이 — 하단
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, max_p.y, min_p.z),
                     ::Geom::Vector3d.new(0, 0, -OFFSET))
          # 높이 — 뒷면
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, max_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, max_p.y, max_p.z),
                     ::Geom::Vector3d.new(0, OFFSET, 0))
        when :top
          # 평면도: 폭(X) + 깊이(Y)
          # 폭 — 전면
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, max_p.z),
                     ::Geom::Point3d.new(max_p.x, min_p.y, max_p.z),
                     ::Geom::Vector3d.new(0, -OFFSET, 0))
          # 깊이 — 우측
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
        SKETCHUP_CONSOLE.puts("Kabinet Dimension error: #{e.message}") if defined?(SKETCHUP_CONSOLE)
        nil
      end

      # Kabinet 치수선 태그에 속한 모든 엔티티를 모델에서 제거.
      # Views.generate 호출 전에 실행해 중복 치수선을 방지.
      def clear_kabinet_dimensions(model)
        tag_name = Kabinet::Constants::DIMENSION_TAG_NAME
        tag = model.layers[tag_name]
        return unless tag
        to_erase = model.entities.select do |e|
          e.respond_to?(:layer) && e.layer == tag
        rescue StandardError
          false
        end
        model.entities.erase_entities(to_erase) unless to_erase.empty?
      rescue StandardError
        nil
      end

      def hide_dimension_tag(model)
        tag = model.layers[Kabinet::Constants::DIMENSION_TAG_NAME]
        tag.visible = false if tag
      end

      def show_dimension_tag(model)
        tag = model.layers[Kabinet::Constants::DIMENSION_TAG_NAME]
        tag.visible = true if tag
      end
    end
  end
end
