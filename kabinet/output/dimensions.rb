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
        when :front
          # Width along bottom
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(max_p.x, min_p.y, min_p.z),
                     ::Geom::Vector3d.new(0, -OFFSET, 0))
          # Height along left side
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, min_p.y, max_p.z),
                     ::Geom::Vector3d.new(-OFFSET, 0, 0))
        when :side
          # Depth along bottom
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, max_p.y, min_p.z),
                     ::Geom::Vector3d.new(0, 0, -OFFSET))
          # Height
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, max_p.y, min_p.z),
                     ::Geom::Point3d.new(min_p.x, max_p.y, max_p.z),
                     ::Geom::Vector3d.new(0, OFFSET, 0))
        when :top
          # Width
          add_linear(ents, tag,
                     ::Geom::Point3d.new(min_p.x, min_p.y, max_p.z),
                     ::Geom::Point3d.new(max_p.x, min_p.y, max_p.z),
                     ::Geom::Vector3d.new(0, -OFFSET, 0))
          # Depth
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
