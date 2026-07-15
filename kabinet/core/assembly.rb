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
      attr_reader :name, :width, :max_depth, :base_height, :base_type, :ep, :top_panel,
                  :modules, :run_mode, :run_height, :has_kickboard, :ep_top_flush

      def initialize(name:, width:, max_depth:, ep:, top_panel:, modules:,
                     base_height: 0, base_type: 'wood', run_mode: false, run_height: 740,
                     has_kickboard: true, ep_top_flush: false)
        @name          = name
        @width         = width
        @max_depth     = max_depth
        @base_height   = base_height
        @base_type     = base_type == 'steel' ? 'steel' : 'wood'
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
          base_type:     h['base_type']   || 'wood',
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
        total_h_mm += ep_top_t_mm
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

      def ep_top_t_mm
        @ep && @ep['top'] ? (@ep['thickness'] || Kabinet::Constants::DEFAULT_EP_THICKNESS_MM).to_f : 0.0
      end

      # 상부 EP: 가구 최상단을 덮는 마감판 — 전체 폭(측면 EP 포함), 측면 EP와
      # 같은 깊이(도어 전면 커버 포함), 측면 EP 위에 얹힘.
      def add_ep_top_panel(entities, total_w, top_z, depth)
        t = ep_top_t_mm
        return if t <= 0
        cover = @ep.nil? || @ep.fetch('cover_fronts', true) ? true : false
        prot  = cover ? Kabinet::Core::Fitting.front_protrusion_mm(@modules).mm : 0.mm
        local = ::Geom::Transformation.new(::Geom::Point3d.new(0, -prot, top_z))
        Kabinet::Geometry::Builder.box(entities, total_w, depth + prot, t.mm,
                                       local,
                                       role: 'ep_top', label: 'ep_top',
                                       material_name: 'ep')
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

      # EP는 도어/서랍 전판 전면까지 커버 (ep.cover_fronts, 기본 true).
      # 실무: 측면 마감판이 카케이스에서 끝나면 도어 옆면이 노출된다.
      def add_ep_panels(entities, ep_left, ep_right, ep_t, x_left, x_right, total_h, depth)
        cover = @ep.nil? || @ep.fetch('cover_fronts', true) ? true : false
        prot  = cover ? Kabinet::Core::Fitting.front_protrusion_mm(@modules).mm : 0.mm
        ep_d  = depth + prot
        if ep_left
          ep = EpFinishPanel.new(side: :left, thickness: ep_t, height: total_h, depth: ep_d)
          ep.build(entities, Kabinet::Geometry::Transforms::IDENTITY,
                   x_origin: x_left, y_origin: -prot)
        end
        if ep_right
          ep = EpFinishPanel.new(side: :right, thickness: ep_t, height: total_h, depth: ep_d)
          ep.build(entities, Kabinet::Geometry::Transforms::IDENTITY,
                   x_origin: x_right, y_origin: -prot)
        end
      end

      # 철제 각파이프 받침 프레임 — 50×50 각관 둘레 프레임 (실무: 레벨러 포함)
      # 걸레받이 대신 사용. 전면 50mm 인셋, 뒷면 벽선 정렬.
      def add_steel_base(entities, base_x:, base_w:, depth:, height:, index: nil)
        return if @base_height <= 0
        tube  = Kabinet::Constants::STEEL_BASE_TUBE_MM.mm
        inset = Kabinet::Constants::STEEL_BASE_INSET_MM.mm
        role  = index ? "steel_base_#{index}" : 'steel_base'
        # 전면 레일
        Kabinet::Geometry::Builder.box(
          entities, base_w, tube, height,
          ::Geom::Transformation.new(::Geom::Point3d.new(base_x, inset, 0)),
          role: "#{role}_front", label: '철제받침 전면', material_name: 'steel')
        # 후면 레일
        Kabinet::Geometry::Builder.box(
          entities, base_w, tube, height,
          ::Geom::Transformation.new(::Geom::Point3d.new(base_x, depth - tube, 0)),
          role: "#{role}_back", label: '철제받침 후면', material_name: 'steel')
        # 좌우 측면 레일 (전후 레일 사이)
        side_d = depth - inset - tube * 2
        [base_x, base_x + base_w - tube].each_with_index do |sx, si|
          Kabinet::Geometry::Builder.box(
            entities, tube, side_d, height,
            ::Geom::Transformation.new(::Geom::Point3d.new(sx, inset + tube, 0)),
            role: "#{role}_side#{si}", label: '철제받침 측면', material_name: 'steel')
        end
      end

      def add_kickboard(entities, base_height_mm:, kick_x:, kick_w:, index: nil)
        return if base_height_mm <= 0

        setback = Kabinet::Constants::TOE_KICK_SETBACK_MM.mm
        board_t = Kabinet::Constants::TOE_KICK_BOARD_THICK_MM.mm

        kick_local = ::Geom::Transformation.new(::Geom::Point3d.new(kick_x, setback, 0))
        Kabinet::Geometry::Builder.box(
          entities, kick_w, board_t, base_height_mm,
          kick_local,
          role: index ? "kickboard_#{index}" : 'kickboard',
          label: '걸레받이', material_name: 'body'
        )
      end

      # 걸레받이·상판은 침대 공간(bed_gap)을 가로지르면 안 되므로 구간별로
      # 생성한다. 실제 분할 로직은 Fitting.run_segments (단일 소스) 위임.
      def run_segments
        Kabinet::Core::Fitting.run_segments(@modules)
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
          # v_gap: 빈 수직 공간 (책상 위 개방부 등) — 높이만 차지, 지오메트리 없음
          if m['kind'] == 'v_gap'
            current_z += m['height'].mm
            next
          end
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

        add_ep_top_panel(entities, total_w, total_h, max_d)

        if @base_type == 'steel'
          add_steel_base(entities, base_x: ep_left_offset, base_w: carcase_inner_w,
                         depth: max_d, height: @base_height.mm)
        elsif @has_kickboard
          if ep_left || ep_right
            add_kickboard(entities, base_height_mm: @base_height.mm,
                          kick_x: ep_left_offset, kick_w: carcase_inner_w)
          else
            add_kickboard(entities, base_height_mm: @base_height.mm,
                          kick_x: 0, kick_w: total_w)
          end
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
          elsif m['kind'] == 'bed_gap' && m['storage']
            add_storage_bed(entities, m, idx, current_x, max_d)
          end
          current_x += mod_w   # bed_gap 포함 항상 폭 전진
        end

        # 상판·걸레받이: bed_gap 제외 연속 구간별 생성
        # (기존 버그: 침대 공간을 가로질러 통짜 상판/걸레받이가 생성됐음)
        top_z = (@base_height + run_h).mm
        run_segments.each_with_index do |(seg_x, seg_w), i|
          add_top_panel(entities, ep_left_offset + seg_x.mm, max_d, seg_w.mm, top_z)
          if @base_type == 'steel'
            add_steel_base(entities, base_x: ep_left_offset + seg_x.mm, base_w: seg_w.mm,
                           depth: max_d, height: @base_height.mm, index: i)
          elsif @has_kickboard
            add_kickboard(entities, base_height_mm: @base_height.mm,
                          kick_x: ep_left_offset + seg_x.mm, kick_w: seg_w.mm,
                          index: i)
          end
        end

        # EP panels span full run height
        # ep_top_flush: true → EP 높이를 상판 두께 제외 (상판이 EP 위에 얹힘)
        ep_h = @ep_top_flush ? (@base_height + run_h).mm : total_h
        add_ep_panels(entities, ep_left, ep_right, ep_t,
                      0, ep_left_offset + carcase_inner_w,
                      ep_h, max_d)

        add_ep_top_panel(entities, total_w, total_h, max_d)
      end

      # ── 수납침대 (침대 프레임 겸 서랍 플랫폼) ─────────────────────────────
      # run_height 무시, 자체 platform_height. 앞으로 돌출(bed_depth), 바닥부터.
      # drawer_side:
      #   foot        — 발치(앞면) 서랍, 세로 적층 (기본)
      #   left/right  — 측면 서랍: 침대 길이 방향으로 가로 분할된 유닛들을
      #                 90° 회전 배치. 각 유닛 1단 서랍.
      # lift_up_storage: 매트리스 받침 플레이트를 반으로 나눠 발치 쪽이
      #   가스쇼바로 열리는 수납 — 플레이트 2장(18T)을 플랫폼 위에 얹음.
      def add_storage_bed(entities, m, idx, current_x, max_d)
        gap_w = m['width'].to_f
        bed_d = m['bed_depth'].to_f
        ph    = m['platform_height'].to_f
        side  = m['drawer_side'] || 'foot'
        y0    = max_d - bed_d.mm   # 침대 뒷면 = 카케이스 뒷선 정렬

        case side
        when 'left', 'right'
          n      = [(m['drawer_count'] || 2).to_i, 1].max
          unit_w = bed_d / n
          angle  = side == 'left' ? -90.degrees : 90.degrees
          rot    = ::Geom::Transformation.rotation(
            ::Geom::Point3d.new(0, 0, 0), ::Geom::Vector3d.new(0, 0, 1), angle)
          n.times do |k|
            # ponytail: 유닛별 독립 카케이스 — 실물은 분할판 공유(측판 n−1장 과산출).
            # 커트리스트 정밀화 필요해지면 공유 분할판 모델로 교체.
            unit = Kabinet::Core::DrawerModule.from_hash(
              m.merge('kind' => 'drawer_module', 'width' => unit_w,
                      'height' => ph, 'depth' => gap_w, 'drawer_count' => 1))
            origin =
              if side == 'left'
                ::Geom::Point3d.new(current_x, max_d - (k * unit_w).mm, 0)
              else
                ::Geom::Point3d.new(current_x + gap_w.mm,
                                    max_d - bed_d.mm + (k * unit_w).mm, 0)
              end
            grp = unit.build(entities, ::Geom::Transformation.new(origin) * rot,
                             role: "bed_storage_#{idx}_#{k}")
            Kabinet::Persistence::Attributes.set(grp, 'module_index', idx)
          end
        else # foot
          bed = Kabinet::Core::DrawerModule.from_hash(
            m.merge('kind' => 'drawer_module',
                    'height' => ph, 'depth' => bed_d))
          grp = bed.build(entities,
                          ::Geom::Transformation.new(::Geom::Point3d.new(current_x, y0, 0)),
                          role: "bed_storage_#{idx}")
          Kabinet::Persistence::Attributes.set(grp, 'module_index', idx)
        end

        return unless m['lift_up_storage']
        plate_t = Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm
        half    = (bed_d / 2.0).mm
        # 발치(앞) 절반 — 리프트업 개폐부
        Kabinet::Geometry::Builder.box(
          entities, gap_w.mm, half, plate_t,
          ::Geom::Transformation.new(::Geom::Point3d.new(current_x, y0, ph.mm)),
          role: "bed_lift_lid_#{idx}", label: '리프트업 받침(발치)', material_name: 'top')
        # 헤드(뒤) 절반 — 고정
        Kabinet::Geometry::Builder.box(
          entities, gap_w.mm, half, plate_t,
          ::Geom::Transformation.new(::Geom::Point3d.new(current_x, y0 + half, ph.mm)),
          role: "bed_fixed_lid_#{idx}", label: '고정 받침(헤드)', material_name: 'top')
      end

      # ── Module factory ───────────────────────────────────────────────────

      def build_module(m)
        case m['kind']
        when 'shelf_module'  then Kabinet::Core::ShelfModule.from_hash(m)
        when 'drawer_module' then Kabinet::Core::DrawerModule.from_hash(m)
        when 'desk_module'   then Kabinet::Core::DeskModule.from_hash(m)
        when 'bed_gap'       then nil   # 침대 공간 — 지오메트리 없음, 폭만 차지
        when 'v_gap'         then nil   # 수직 개방 공간 — 높이만 차지
        else
          raise ArgumentError, "unknown module kind: #{m['kind']}"
        end
      end
    end
  end
end
