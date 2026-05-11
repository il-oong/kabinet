module Kabinet
  module Output
    module Views
      VIEW_DEFS = {
        front:   { name: '정면도', eye_dir: [0, -1, 0], up: [0, 0, 1] },
        right:   { name: '우측면도', eye_dir: [1, 0, 0],  up: [0, 0, 1] },
        left:    { name: '좌측면도', eye_dir: [-1, 0, 0], up: [0, 0, 1] },
        top:     { name: '평면도',  eye_dir: [0, 0, -1], up: [0, 1, 0] },
        section: { name: '단면도',  eye_dir: [0, -1, 0], up: [0, 0, 1] }
      }.freeze

      module_function

      # Generate SU pages for the listed views, optionally drawing dimensions.
      # views: array of symbols from VIEW_DEFS keys (default all except section needs separate call)
      # Returns array of page names created.
      def generate(assembly_group, views: %i[front right top], draw_dimensions: true,
                   model: Sketchup.active_model)
        bb = assembly_group.bounds
        center = bb.center
        span = [bb.width, bb.depth, bb.height].max * 2.0

        created = []
        model.start_operation('Kabinet — 도면 장면 생성', true)
        begin
          views.each do |view_key|
            defn = VIEW_DEFS[view_key]
            next unless defn

            page = find_or_create_page(model, "[Kabinet] #{defn[:name]}")

            setup_camera(model.active_view, center, span, defn)
            model.active_view.invalidate

            if view_key == :section
              add_section_plane(assembly_group, model)
            else
              deactivate_section_planes(model)
            end

            if draw_dimensions
              Output::Dimensions.show_dimension_tag(model)
              Output::Dimensions.draw_for_assembly(assembly_group, view_key, model: model)
            end

            model.pages.selected_page = page
            page.update(1 | 2 | 4 | 8 | 16 | 32 | 64 | 128)   # all flags
            created << page.name
          end
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          raise
        end

        # Hide dimension tag when done so it doesn't clutter the working view
        Output::Dimensions.hide_dimension_tag(model) if draw_dimensions

        created
      end

      def setup_camera(view, center, span, defn)
        eye_dir = ::Geom::Vector3d.new(*defn[:eye_dir])
        up_vec  = ::Geom::Vector3d.new(*defn[:up])
        eye     = center.offset(eye_dir, span)
        cam = Sketchup::Camera.new(eye, center, up_vec)
        cam.perspective = false
        view.camera = cam
        view.zoom_extents
      end

      def find_or_create_page(model, name)
        page = model.pages.find { |p| p.name == name }
        page || model.pages.add(name)
      end

      def add_section_plane(assembly_group, model)
        deactivate_section_planes(model)
        bb = assembly_group.bounds
        mid_y = (bb.min.y + bb.max.y) / 2.0
        plane_origin = ::Geom::Point3d.new(bb.center.x, mid_y, bb.center.z)
        normal = ::Geom::Vector3d.new(0, 1, 0)
        t = ::Geom::Transformation.rotation(plane_origin, ::Geom::Vector3d.new(1, 0, 0), 0)
        sp = model.entities.add_section_plane(
          ::Geom::Transformation.new(plane_origin) * t
        )
        sp.activate if sp
        sp
      rescue StandardError
        nil
      end

      def deactivate_section_planes(model)
        model.entities.grep(Sketchup::SectionPlane).each do |sp|
          sp.deactivate rescue nil
        end
      end
    end
  end
end
