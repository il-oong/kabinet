module Kabinet
  module Core
    # The assembly of modules.
    #
    # Stack mode (run_mode: false — default):
    #   Modules are stacked bottom→top along Z.  All modules share the same X width.
    #   Back faces are aligned; narrower modules protrude to the front.
    #
    # Run mode (run_mode: true):
    #   Modules (= sections) are placed side-by-side along X.
    #   All sections share run_height.  Good for kitchen runs, wardrobe runs, etc.
    #
    # All numeric inputs are in MILLIMETERS at the public API boundary.
    # Conversion to SketchUp Length happens inside this class.
    class Assembly
      attr_reader :name, :width, :max_depth, :base_height, :ep, :top_panel, :modules,
                  :run_mode, :run_height, :has_kickboard, :ep_top_flush

      def initialize(name:, width:, max_depth:, ep:, top_panel:, modules:,
                     base_height: 0, run_mode: false, run_height: 740,
                     has_kickboard: true, ep_top_flush: false)
        @name          = name
        @width         = width
        @max_depth     = max_depth
        @base_height   = base_height
        @ep            = ep
        @top_panel     = top_panel
        @modules       = modules
        @run_mode      = run_mode
        @run_height    = run_height
        @has_kickboard = has_kickboard
        @ep_top_flush  = ep_top_flush ? true : false
      end

      def self.from_hash(h)
        new(
          name:          h['name'],
          width:         h['width'],
          max_depth:     h['max_depth'],
          base_height:   h['base_height'] || 0,
          ep:            h['ep'],
          top_panel:     h['top_panel'],
          modules:       h['modules'],
          run_mode:      h['run_mode']      || false,
          run_height:    h['run_height']    || 740,
          has_kickboard: h.fetch('has_kickboard', true) ? true : false,
          ep_top_flush:  h.fetch('ep_top_flush',  false) ? true : false
        )
      end

      # Build at world origin (or specified transform). Returns the new root group.
      def build(parent_entities, origin_transform = Kabinet::Geometry::Transforms::IDENTITY,
                spec_for_persistence: nil)
        root = parent_entities.add_group
        root.transformation = origin_transform
        root.name = @name

        # Stamp assembly role + overall dimensions on the root group
        top_t     = @top_panel ? @top_panel['thickness'].to_f : 0
        if @run_mode
          total_w_mm = @modules.sum { |m| m['width'].to_f }
          total_h_mm = @base_height + @run_height.to_f + top_t
        else
          total_w_mm = @width.to_f
          total_h_mm = @base_height + @modules.sum { |m| m['height'].to_f } + top_t
        end
        Kabinet::Persistence::Attributes.set_role(root, 'assembly',
          width_mm: total_w_mm, depth_mm: @max_depth.to_f, height_mm: total_h_mm)

        if @run_mode
          do_run(root.entities)
        else
          do_stack(root.entities)
        end

        Kabinet::Persistence::Attributes.write_assembly_spec(root, spec_for_persistence) if spec_for_persistence
        root
      end

      # Replace contents of an existing root group (for Regenerate).
      def build_into(root_group, spec_for_persistence: nil)
        root_group.entities.clear!
        if @run_mode
          do_run(root_group.entities)
        else
          do_stack(root_group.entities)
        end
        Kabinet::Persistence::Attributes.write_assembly_spec(root_group, spec_for_persistence) if spec_for_persistence
        root_group
      end

      private

      # ── Shared geometry helpers ──────────────────────────────────────────

      def ep_params
        ep_left  = @ep && @ep['left']
        ep_right = @ep && @ep['right']
        ep_t     = (@ep['thickness'] || Kabinet::Constants::DEFAULT_EP_THICKNESS_MM).mm
        [ep_left, ep_right, ep_t]
      end

      def top_t_mm
        @top_panel ? @top_panel['thickness'].to_f : 0
      end

      def add_top_panel(entities, x_origin, depth, width_su, top_z)
        tt = top_t_mm
        return unless @top_panel && tt > 0
        top_local = ::Geom::Transformation.new(::Geom::Point3d.new(x_origin, 0, top_z))
        Kabinet::Geometry::Builder.box(entities, width_su, depth, tt.mm,
                                       top_local,
                                       role: 'top_panel', label: 'top_panel',
                                       material_name: 'top')
      end

      def add_ep_panels(entities, ep_left, ep_right, ep_t, x_left, x_right, total_h, depth)
        if ep_left
          ep = EpFinishPanel.new(side: :left, thickness: ep_t, height: total_h, depth: depth)
          ep.build(entities, Kabinet::Geometry::Transforms::IDENTITY, x_origin: x_left)
        end
        if ep_right
          ep = EpFinishPanel.new(side: :right, thickness: ep_t, height: total_h, depth: depth)
          ep.build(entities, Kabinet::Geometry::Transforms::IDENTITY, x_origin: x_right)
        end
      end

      def add_kickboard(entities, base_height_mm:, carcase_w:, total_w:,
                        ep_left:, ep_right:, ep_left_offset:)
        return if base_height_mm <= 0

        setback = Kabinet::Constants::TOE_KICK_SETBACK_MM.mm
        board_t = Kabinet::Constants::TOE_KICK_BOARD_THICK_MM.mm

        if ep_left || ep_right
          kick_x = ep_left_offset
          kick_w = carcase_w
        else
          kick_x = 0
          kick_w = total_w
        end

        kick_local = ::Geom::Transformation.new(::Geom::Point3d.new(kick_x, setback, 0))
        Kabinet::Geometry::Builder.box(
          entities, kick_w, board_t, base_height_mm,
          kick_local,
          role: 'kickboard', label: '걸레받이', material_name: 'body'
        )
      end

      # ── STACK MODE (modules bottom → top along Z) ────────────────────────

      def do_stack(entities)
        ep_left, ep_right, ep_t = ep_params
        ep_t_mm         = (@ep['thickness'] || Kabinet::Constants::DEFAULT_EP_THICKNESS_MM).to_f
        ep_left_offset  = ep_left  ? ep_t : 0   # SU Length
        ep_right_offset = ep_right ? ep_t : 0   # SU Length

        # @width = 가구 전체 폭 (EP 포함 외부 치수 mm)
        # 카케이스 내부 폭 = 전체 폭 − 좌EP − 우EP
        total_w            = @width.mm
        carcase_inner_w_mm = @width.to_f \
                             - (ep_left  ? ep_t_mm : 0.0) \
                             - (ep_right ? ep_t_mm : 0.0)
        carcase_inner_w    = carcase_inner_w_mm.mm   # SU Length

        modules_h_mm = @modules.sum { |m| m['height'].to_f }
        top_t        = top_t_mm
        total_h      = (@base_height + modules_h_mm + top_t).mm
        max_d        = @max_depth.mm

        current_z = @base_height.mm
        @modules.each_with_index do |m, idx|
          mod_depth = m['depth'].mm
          y_offset  = max_d - mod_depth
          local = ::Geom::Transformation.new(
            ::Geom::Point3d.new(ep_left_offset, y_offset, current_z)
          )
          # 모듈 폭을 카케이스 내부 폭으로 강제 지정 (spec의 width 값 무관)
          m_actual  = m.merge('width' => carcase_inner_w_mm)
          mod_group = build_module(m_actual).build(entities, local,
                                                   role: "#{m['kind']}_#{idx}",
                                                   suppress_bottom: idx > 0)
          Kabinet::Persistence::Attributes.set(mod_group, 'module_index', idx)
          current_z += m['height'].mm
        end

        add_top_panel(entities, ep_left_offset, max_d, carcase_inner_w, current_z)

        # ep_top_flush: true → EP 높이를 상판 두께 제외 (상판이 EP 위에 얹힘)
        ep_h = @ep_top_flush ? (@base_height + modules_h_mm).mm : total_h
        add_ep_panels(entities, ep_left, ep_right, ep_t,
                      0, ep_left_offset + carcase_inner_w,
                      ep_h, max_d)

        if @has_kickboard
          add_kickboard(entities, base_height_mm: @base_height.mm,
                        carcase_w: carcase_inner_w, total_w: total_w,
                        ep_left: ep_left, ep_right: ep_right,
                        ep_left_offset: ep_left_offset)
        end
      end

      # ── RUN MODE (modules/sections side-by-side along X) ─────────────────
      #
      # Each module = one vertical section of the run (independent carcase).
      # All sections share @run_height.
      # EP panels and toe kick span the full run.

      def do_run(entities)
        ep_left, ep_right, ep_t = ep_params
        ep_left_offset = ep_left ? ep_t : 0

        run_h   = @run_height.to_f          # mm float
        top_t   = top_t_mm                  # mm float
        total_h = (@base_height + run_h + top_t).mm
        max_d   = @max_depth.mm

        # Total carcase width = sum of all section widths
        carcase_inner_w_mm = @modules.sum { |m| m['width'].to_f }
        carcase_inner_w    = carcase_inner_w_mm.mm
        total_w = ep_left_offset + carcase_inner_w + (ep_right ? ep_t : 0)

        # Place each section side-by-side
        current_x = ep_left_offset
        @modules.each_with_index do |m, idx|
          mod_w     = m['width'].to_f.mm
          mod_depth = m.key?('depth') ? m['depth'].to_f.mm : max_d
          y_offset  = max_d - mod_depth
          # Override height with run_height (bed_gap has no height key — OK since no geometry)
          m_run   = m.merge('height' => run_h)
          mod_obj = build_module(m_run)
          if mod_obj
            local = ::Geom::Transformation.new(
              ::Geom::Point3d.new(current_x, y_offset, @base_height.mm))
            mod_group = mod_obj.build(entities, local, role: "#{m['kind']}_#{idx}")
            Kabinet::Persistence::Attributes.set(mod_group, 'module_index', idx)
          end
          current_x += mod_w   # bed_gap 포함 항상 폭 전진
        end

        # Top panel spans full carcase width
        top_z = (@base_height + run_h).mm
        add_top_panel(entities, ep_left_offset, max_d, carcase_inner_w, top_z)

        # EP panels span full run height
        # ep_top_flush: true → EP 높이를 상판 두께 제외 (상판이 EP 위에 얹힘)
        ep_h = @ep_top_flush ? (@base_height + run_h).mm : total_h
        add_ep_panels(entities, ep_left, ep_right, ep_t,
                      0, ep_left_offset + carcase_inner_w,
                      ep_h, max_d)

        # Kickboard spans full run
        if @has_kickboard
          add_kickboard(entities, base_height_mm: @base_height.mm,
                        carcase_w: carcase_inner_w, total_w: total_w,
                        ep_left: ep_left, ep_right: ep_right,
                        ep_left_offset: ep_left_offset)
        end
      end

      # ── Module factory ───────────────────────────────────────────────────

      def build_module(m)
        case m['kind']
        when 'shelf_module'  then ShelfModule.from_hash(m)
        when 'drawer_module' then DrawerModule.from_hash(m)
        when 'desk_module'   then DeskModule.from_hash(m)
        when 'bed_gap'       then nil   # 침대 공간 — 지오메트리 없음, 폭만 차지
        else
          raise ArgumentError, "unknown module kind: #{m['kind']}"
        end
      end
    end
  end
end
