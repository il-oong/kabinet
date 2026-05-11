module Kabinet
  module Core
    # The vertical stack of modules + optional top panel + optional EP side panels.
    # All inputs in MILLIMETERS at the API boundary; we convert to SU Length internally.
    class Assembly
      attr_reader :name, :width, :max_depth, :base_height, :ep, :top_panel, :modules

      # ep: { left: bool, right: bool, thickness: mm }
      # top_panel: nil | { thickness: mm }
      # modules: ordered bottom→top, array of { kind:, ...mm dimensions... }
      def initialize(name:, width:, max_depth:, ep:, top_panel:, modules:, base_height: 0)
        @name = name
        @width = width
        @max_depth = max_depth
        @base_height = base_height
        @ep = ep
        @top_panel = top_panel
        @modules = modules
      end

      def self.from_hash(h)
        new(name: h['name'], width: h['width'], max_depth: h['max_depth'],
            base_height: h['base_height'] || 0, ep: h['ep'], top_panel: h['top_panel'],
            modules: h['modules'])
      end

      # Build into model.entities at world origin (or specified parent).
      # Returns the root assembly Group with `kabinet_assembly` AttributeDictionary stamped.
      def build(parent_entities, origin_transform = Kabinet::Geometry::Transforms::IDENTITY,
                spec_for_persistence: nil)
        ep_left  = @ep && @ep['left']
        ep_right = @ep && @ep['right']
        ep_t     = (@ep['thickness'] || Kabinet::Constants::DEFAULT_EP_THICKNESS_MM).mm

        ep_left_offset = ep_left ? ep_t : 0
        carcase_inner_w = @width.mm
        total_w = ep_left_offset + carcase_inner_w + (ep_right ? ep_t : 0)

        modules_height_mm = @modules.sum { |m| m['height'].to_f }
        top_t_mm = @top_panel ? @top_panel['thickness'].to_f : 0
        total_h = (@base_height + modules_height_mm + top_t_mm).mm
        max_d   = @max_depth.mm

        root = parent_entities.add_group
        root.transformation = origin_transform
        root.name = @name
        Kabinet::Persistence::Attributes.set_role(root, 'assembly',
                                                  width_mm: @width.to_f, depth_mm: @max_depth.to_f,
                                                  height_mm: (modules_height_mm + top_t_mm + @base_height).to_f)

        # Stack modules bottom→top. Align rear faces (depth differences extend forward).
        current_z = @base_height.mm
        @modules.each_with_index do |m, idx|
          mod_depth = m['depth'].mm
          # rear-align: y_offset = max_d - mod_depth (so the back face matches the deepest)
          y_offset = max_d - mod_depth
          x_offset = ep_left_offset
          local = ::Geom::Transformation.new(::Geom::Point3d.new(x_offset, y_offset, current_z))
          mod_obj = build_module(m)
          mod_group = mod_obj.build(root.entities, local, role: "#{m['kind']}_#{idx}")
          Kabinet::Persistence::Attributes.set(mod_group, 'module_index', idx)
          current_z += m['height'].mm
        end

        # Top panel (full inner width × max depth, 20mm typical)
        if @top_panel && top_t_mm > 0
          top_local = ::Geom::Transformation.new(::Geom::Point3d.new(ep_left_offset, 0, current_z))
          Kabinet::Geometry::Builder.box(root.entities, carcase_inner_w, max_d, top_t_mm.mm,
                                         top_local,
                                         role: 'top_panel', label: 'top_panel', material_name: 'top')
        end

        # EPs span full assembly height (base + modules + top panel)
        if ep_left
          ep = EpFinishPanel.new(side: :left, thickness: ep_t, height: total_h, depth: max_d)
          ep.build(root.entities, Kabinet::Geometry::Transforms::IDENTITY, x_origin: 0)
        end
        if ep_right
          ep = EpFinishPanel.new(side: :right, thickness: ep_t, height: total_h, depth: max_d)
          ep.build(root.entities, Kabinet::Geometry::Transforms::IDENTITY,
                   x_origin: ep_left_offset + carcase_inner_w)
        end

        # Stamp full spec for later regenerate
        if spec_for_persistence
          Kabinet::Persistence::Attributes.write_assembly_spec(root, spec_for_persistence)
        end

        root
      end

      # Replace contents of an existing assembly group while preserving the root.
      def build_into(root_group, spec_for_persistence: nil)
        root_group.entities.clear!
        ep_left  = @ep && @ep['left']
        ep_right = @ep && @ep['right']
        ep_t     = (@ep['thickness'] || Kabinet::Constants::DEFAULT_EP_THICKNESS_MM).mm

        ep_left_offset = ep_left ? ep_t : 0
        carcase_inner_w = @width.mm
        max_d   = @max_depth.mm
        modules_height_mm = @modules.sum { |m| m['height'].to_f }
        top_t_mm = @top_panel ? @top_panel['thickness'].to_f : 0
        total_h = (@base_height + modules_height_mm + top_t_mm).mm

        current_z = @base_height.mm
        @modules.each_with_index do |m, idx|
          mod_depth = m['depth'].mm
          y_offset = max_d - mod_depth
          x_offset = ep_left_offset
          local = ::Geom::Transformation.new(::Geom::Point3d.new(x_offset, y_offset, current_z))
          mod_obj = build_module(m)
          mod_group = mod_obj.build(root_group.entities, local, role: "#{m['kind']}_#{idx}")
          Kabinet::Persistence::Attributes.set(mod_group, 'module_index', idx)
          current_z += m['height'].mm
        end

        if @top_panel && top_t_mm > 0
          top_local = ::Geom::Transformation.new(::Geom::Point3d.new(ep_left_offset, 0, current_z))
          Kabinet::Geometry::Builder.box(root_group.entities, carcase_inner_w, max_d, top_t_mm.mm,
                                         top_local,
                                         role: 'top_panel', label: 'top_panel', material_name: 'top')
        end

        if ep_left
          ep = EpFinishPanel.new(side: :left, thickness: ep_t, height: total_h, depth: max_d)
          ep.build(root_group.entities, Kabinet::Geometry::Transforms::IDENTITY, x_origin: 0)
        end
        if ep_right
          ep = EpFinishPanel.new(side: :right, thickness: ep_t, height: total_h, depth: max_d)
          ep.build(root_group.entities, Kabinet::Geometry::Transforms::IDENTITY,
                   x_origin: ep_left_offset + carcase_inner_w)
        end

        if spec_for_persistence
          Kabinet::Persistence::Attributes.write_assembly_spec(root_group, spec_for_persistence)
        end

        root_group
      end

      private

      def build_module(m)
        case m['kind']
        when 'shelf_module'  then ShelfModule.from_hash(m)
        when 'drawer_module' then DrawerModule.from_hash(m)
        else
          raise ArgumentError, "unknown module kind: #{m['kind']}"
        end
      end
    end
  end
end
