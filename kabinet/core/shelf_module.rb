module Kabinet
  module Core
    # A Carcase + optional doors + N interior shelves + accessories
    # + free-design interior: vertical dividers, per-cell shelves, per-cell drawers.
    #
    # vertical_dividers: [{x: mm_from_interior_left, thickness: 18}, ...]
    #   → 내부 세로 분할판. 칸(셀)을 나눔.
    #
    # cell_shelves: [{cell: 0, height_from_bottom: 200, thickness: 18, depth_inset: 0}, ...]
    #   → 특정 셀 안의 선반. cell 번호는 0-based, 좌→우.
    #
    # cell_drawers: [{cell: 1, count: 2, type: 'undermount', thickness: 18}, ...]
    #   → 특정 셀 전체를 채우는 서랍 컬럼. 서랍 전판은 오버레이.
    #
    # Lengths in SU Length.
    class ShelfModule
      attr_reader :width, :depth, :height, :body_thickness, :back_thickness,
                  :door_config, :door_thickness, :shelves, :accessories,
                  :vertical_dividers, :cell_shelves, :cell_drawers,
                  :handle_type, :handle_hole_mm, :door_mount,
                  :door_side_gap_mm, :suppress_left_side, :suppress_right_side,
                  :has_back

      def initialize(width:, depth:, height:,
                     body_thickness: Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness: Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     door_config: 'none', door_type: 'swing',
                     door_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.mm,
                     shelves: [], accessories: [],
                     vertical_dividers: [], cell_shelves: [], cell_drawers: [],
                     inner_drawers: nil,
                     handle_type: 'none', handle_hole_mm: 128,
                     door_mount: 'overlay',
                     door_side_gap_mm: Kabinet::Core::Gaps.outside,
                     suppress_left_side: false, suppress_right_side: false,
                     has_back: true)
        @width             = width
        @depth             = depth
        @height            = height
        @body_thickness    = body_thickness
        @back_thickness    = back_thickness
        @door_config       = door_config
        @door_type         = door_type.to_s
        @door_thickness    = door_thickness
        @shelves           = shelves
        @accessories       = accessories
        @vertical_dividers = vertical_dividers
        @cell_shelves      = cell_shelves
        @cell_drawers      = cell_drawers
        @inner_drawers     = inner_drawers
        @handle_type       = handle_type.to_s
        @handle_hole_mm    = handle_hole_mm.to_i
        @door_mount        = door_mount.to_s
        @door_side_gap_mm  = door_side_gap_mm.to_f
        @suppress_left_side  = suppress_left_side  ? true : false
        @suppress_right_side = suppress_right_side ? true : false
        @has_back            = has_back ? true : false
      end

      def carcase
        @carcase ||= Carcase.new(width: @width, depth: @depth, height: @height,
                                 body_thickness: @body_thickness, back_thickness: @back_thickness,
                                 has_back: @has_back,
                                 suppress_left_side: @suppress_left_side,
                                 suppress_right_side: @suppress_right_side)
      end

      def opening_width
        @width - 2 * @body_thickness
      end

      def opening_height
        @height - 2 * @body_thickness
      end

      def build(parent_entities, parent_transform, role: 'shelf_module', suppress_bottom: false)
        group = parent_entities.add_group
        group.transformation = parent_transform
        Kabinet::Persistence::Attributes.set_role(group, role,
                                                  width: @width.to_f, depth: @depth.to_f, height: @height.to_f)

        # ── 몸통 그룹 (카케이스 + 내부 구성 — 도어와 분리)
        body_grp = group.entities.add_group
        Kabinet::Persistence::Attributes.set_role(body_grp, 'body_group', label: '몸통')

        # ── 카케이스 (inline, suppress_bottom / suppress_sides 적용)
        c = Carcase.new(width: @width, depth: @depth, height: @height,
                        body_thickness: @body_thickness, back_thickness: @back_thickness,
                        has_back: @has_back,
                        suppress_bottom: suppress_bottom,
                        suppress_left_side: @suppress_left_side,
                        suppress_right_side: @suppress_right_side)
        c.build(body_grp.entities, Kabinet::Geometry::Transforms::IDENTITY, wrap_group: false)

        # ── 전체폭 선반 (좌우 끼임 여유 — 커트리스트와 동일) ──────────
        play = Kabinet::Constants::SHELF_SIDE_PLAY_MM.mm
        @shelves.each do |s|
          z      = (s['height_from_bottom'] || 0).mm
          t      = (s['thickness'] || 18).mm
          inset  = (s['depth_inset'] || 20).mm
          recess = Kabinet::Constants::BACK_RECESS_MM.mm
          shelf_d = @depth - inset - @back_thickness - recess
          local   = ::Geom::Transformation.new(
            ::Geom::Point3d.new(@body_thickness + play / 2.0, 0, z))
          Kabinet::Geometry::Builder.box(body_grp.entities, opening_width - play, shelf_d, t,
                                         local, role: 'shelf', label: 'shelf',
                                         material_name: 'shelf')
        end

        # ── 세로 분할판 ──────────────────────────────────────────────
        build_vertical_dividers(body_grp.entities)

        # ── 셀별 선반 ────────────────────────────────────────────────
        build_cell_shelves(body_grp.entities)

        # ── 셀별 서랍 컬럼 ───────────────────────────────────────────
        build_cell_drawers(body_grp.entities)

        # ── 내부 서랍 (도어 안쪽, 지정 높이에 쌓음) ──────────────────
        build_inner_drawers(body_grp.entities)

        # ── 액세서리 ─────────────────────────────────────────────────
        @accessories.each do |acc_hash|
          acc = Accessory.new(kind: acc_hash['kind'], **symbolize(acc_hash.reject { |k, _| k == 'kind' }))
          acc.build(body_grp.entities, Kabinet::Geometry::Transforms::IDENTITY, carcase: c)
        end

        # ── 도어 (group에 직접 → doors_grp 서브그룹이 생성됨)
        unless @door_config == 'none'
          if @door_mount == 'inset'
            # 인셋: 도어가 카케이스 내부 개구에 맞게 들어감
            inset_gap = Kabinet::Constants::INSET_DOOR_GAP_MM.mm
            door = DoorPanel.new(
              opening_width:  @width - 2 * @body_thickness,
              opening_height: @height - 2 * @body_thickness,
              thickness:      @door_thickness,
              config:         @door_config,
              door_type:      @door_type,
              gap_top:        inset_gap,
              gap_bottom:     inset_gap,
              gap_outside:    inset_gap,
              reveal_between: Kabinet::Core::Gaps.between.mm,
              mount_style:    'inset',
              x_origin:       @body_thickness,
              z_origin:       @body_thickness,
              inset_depth:    Kabinet::Constants::INSET_DOOR_DEPTH_MM.mm,
              handle_type:    @handle_type,
              handle_hole_mm: @handle_hole_mm
            )
          else
            # 오버레이: 도어가 카케이스 전면 측판을 덮음 (기본)
            # door_side_gap_mm = 0 → 측판 외면까지 딱 붙는 플러시 도어
            door = DoorPanel.new(
              opening_width:  @width,
              opening_height: @height,
              thickness:      @door_thickness,
              config:         @door_config,
              door_type:      @door_type,
              gap_top:        Kabinet::Core::Gaps.top.mm,
              gap_bottom:     Kabinet::Core::Gaps.bottom.mm,
              gap_outside:    @door_side_gap_mm.mm,
              mount_style:    'overlay',
              handle_type:    @handle_type,
              handle_hole_mm: @handle_hole_mm
            )
          end
          door.build(group.entities, Kabinet::Geometry::Transforms::IDENTITY)
        end

        group
      end

      def self.from_hash(h)
        bt = (h['body_thickness'] || Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM).mm
        new(width:             (h['width']  || 600).mm,
            depth:             (h['depth']  || 400).mm,
            height:            (h['height'] || 700).mm,
            body_thickness:    bt,
            back_thickness:    (h['back_thickness'] || Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM).mm,
            door_config:       h['door_config']    || 'none',
            door_type:         h['door_type']      || 'swing',
            door_thickness:    (h['door_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM).mm,
            shelves:           h['shelves']        || [],
            accessories:       h['accessories']    || [],
            vertical_dividers: h['vertical_dividers'] || [],
            cell_shelves:      h['cell_shelves']   || [],
            cell_drawers:      h['cell_drawers']   || [],
            inner_drawers:     h['inner_drawers'],
            handle_type:       h['handle_type']    || 'none',
            handle_hole_mm:    (h['handle_hole_mm'] || 128).to_i,
            door_mount:        h['door_mount']     || 'overlay',
            door_side_gap_mm:  (h['door_side_gap_mm'] || Kabinet::Core::Gaps.outside).to_f,
            suppress_left_side:  h.fetch('suppress_left_side',  false) ? true : false,
            suppress_right_side: h.fetch('suppress_right_side', false) ? true : false,
            has_back:            h.fetch('has_back', true) ? true : false)
      end

      private

      # ── 세로 분할판 ────────────────────────────────────────────────
      def build_vertical_dividers(entities)
        return if @vertical_dividers.empty?
        recess = Kabinet::Constants::BACK_RECESS_MM.mm
        div_d  = @depth - @back_thickness - recess
        div_h  = @height - 2 * @body_thickness

        @vertical_dividers.sort_by { |d| d['x'].to_f }.each_with_index do |div, idx|
          x     = @body_thickness + div['x'].mm
          div_t = (div['thickness'] || 18).mm
          local = ::Geom::Transformation.new(
            ::Geom::Point3d.new(x, 0, @body_thickness))
          Kabinet::Geometry::Builder.box(entities, div_t, div_d, div_h,
                                         local,
                                         role:          "divider_#{idx}",
                                         label:         "세로분할판_#{idx + 1}",
                                         material_name: 'body')
        end
      end

      # ── 셀 범위 계산 ──────────────────────────────────────────────
      # Returns array of { x_start:, x_end:, width: } in interior SU-Length coords.
      # Cell 0 is leftmost. 분할 로직은 Fitting.cell_ranges (단일 소스) 위임 —
      # 원본 divider 해시는 mm Float이므로 SU Length로 변환해 넘긴다.
      def cell_ranges
        inner_w = opening_width
        divs_su = (@vertical_dividers || []).map { |d|
          { 'x' => d['x'].to_f.mm, 'thickness' => (d['thickness'] || 18).to_f.mm }
        }
        Kabinet::Core::Fitting.cell_ranges(divs_su, inner_w).map { |s, e|
          { x_start: s, x_end: e, width: e - s }
        }
      end

      # ── 셀별 선반 ─────────────────────────────────────────────────
      def build_cell_shelves(entities)
        return if @cell_shelves.empty?
        recess = Kabinet::Constants::BACK_RECESS_MM.mm
        cells  = cell_ranges

        play = Kabinet::Constants::SHELF_SIDE_PLAY_MM.mm
        @cell_shelves.each do |cs|
          cell = cells[(cs['cell'] || 0).to_i]
          next unless cell && cell[:width] > 0

          z       = (cs['height_from_bottom'] || 0).mm
          t       = (cs['thickness'] || 18).mm
          inset   = (cs['depth_inset'] || 0).mm
          shelf_d = @depth - @back_thickness - recess - inset
          x_orig  = @body_thickness + cell[:x_start] + play / 2.0

          local = ::Geom::Transformation.new(::Geom::Point3d.new(x_orig, 0, z))
          Kabinet::Geometry::Builder.box(entities, cell[:width] - play, shelf_d, t,
                                         local,
                                         role:          "cell_shelf_#{cs['cell']}",
                                         label:         "셀선반_#{(cs['cell'] || 0) + 1}",
                                         material_name: 'shelf')
        end
      end

      # ── 셀별 서랍 컬럼 ────────────────────────────────────────────
      # 셀 내부 전 높이를 서랍으로 채움. 전판은 카케이스 전면 오버레이.
      # 치수는 Fitting 공식 사용 — 커트리스트와 동일.
      def build_cell_drawers(entities)
        return if @cell_drawers.empty?
        recess       = Kabinet::Constants::BACK_RECESS_MM.mm
        gap_t        = Kabinet::Core::Gaps.top.mm
        gap_b        = Kabinet::Core::Gaps.bottom.mm
        reveal       = Kabinet::Core::Gaps.drawer_between.mm
        front_offset = Kabinet::Core::Gaps.front_offset.mm
        wall_t       = Kabinet::Constants::DRAWER_BOX_WALL_MM.mm
        bot_t        = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.mm
        cells        = cell_ranges

        inner_depth_mm = Kabinet::Core::Fitting.len_mm(
          @depth - @back_thickness - recess)

        @cell_drawers.each do |cd|
          cell_idx = (cd['cell'] || 0).to_i
          cell     = cells[cell_idx]
          next unless cell && cell[:width] > 0

          dc  = (cd['count'] || 2).to_i
          dt  = cd['type'] || 'undermount'
          dth = (cd['thickness'] || 18).mm

          # 내부 Z 범위 (하판 위 ~ 상판 아래)
          z_int_start = @body_thickness
          int_h       = @height - 2 * @body_thickness
          cell_x      = @body_thickness + cell[:x_start]
          cell_w      = cell[:width]

          # 전판 레이아웃 (셀 내부 기준 → cell_x / z_int_start 오프셋)
          fronts = Kabinet::Core::Fitting.drawer_fronts(
            cell_w, int_h, dc,
            side_gap:   Kabinet::Core::Gaps.outside.mm,
            top_gap:    gap_t, bottom_gap: gap_b, reveal: reveal)

          compartment_h = (int_h - gap_t - gap_b - reveal * (dc - 1)) / dc.to_f
          box = Kabinet::Core::Fitting.drawer_box_mm(
            open_w_mm:      Kabinet::Core::Fitting.len_mm(cell_w),
            comp_h_mm:      Kabinet::Core::Fitting.len_mm(compartment_h),
            inner_depth_mm: inner_depth_mm,
            type:           dt)
          box_w = box[:w].mm
          box_d = box[:d].mm
          box_h = box[:h].mm
          box_x = cell_x + (cell_w - box_w) / 2.0

          dc.times do |i|
            # 서랍 전판
            f  = fronts[i]
            fl = ::Geom::Transformation.new(
              ::Geom::Point3d.new(cell_x + f[:x],
                                   -(dth + front_offset),
                                   z_int_start + f[:z]))
            Kabinet::Geometry::Builder.box(entities, f[:w], dth, f[:h], fl,
                                           role:          "cell_dfr_#{cell_idx}_#{i}",
                                           label:         "셀서랍전판_c#{cell_idx}_#{i + 1}",
                                           material_name: 'drawer_front')

            # 서랍 박스
            z_box = z_int_start + gap_b + i * (compartment_h + reveal) + box[:z_off].mm
            bl    = ::Geom::Transformation.new(::Geom::Point3d.new(box_x, 0, z_box))
            bgrp  = entities.add_group
            bgrp.transformation = bl
            Kabinet::Persistence::Attributes.set_role(bgrp, "cell_dbox_#{cell_idx}_#{i}")

            # 바닥판
            Kabinet::Geometry::Builder.box(bgrp.entities, box_w, box_d, bot_t,
                                           Kabinet::Geometry::Transforms::IDENTITY,
                                           role: 'drawer_bottom', material_name: 'drawer_box')
            # 좌측판
            Kabinet::Geometry::Builder.box(bgrp.entities, wall_t, box_d, box_h,
                                           ::Geom::Transformation.new(::Geom::Point3d.new(0, 0, 0)),
                                           role: 'drawer_side_left', material_name: 'drawer_box')
            # 우측판
            Kabinet::Geometry::Builder.box(bgrp.entities, wall_t, box_d, box_h,
                                           ::Geom::Transformation.new(::Geom::Point3d.new(box_w - wall_t, 0, 0)),
                                           role: 'drawer_side_right', material_name: 'drawer_box')
            # 뒤판
            Kabinet::Geometry::Builder.box(bgrp.entities, box_w - 2 * wall_t, wall_t, box_h,
                                           ::Geom::Transformation.new(::Geom::Point3d.new(wall_t, box_d - wall_t, 0)),
                                           role: 'drawer_back', material_name: 'drawer_box')
          end
        end
      end

      # 내부 서랍: inner_drawers = { 'bottom' => 서랍 묶음 아래 높이(모듈 바닥 기준 mm),
      #   'count' => 단수, 'height' => 전판 1장 높이, 'gap' => 전판 사이, 'setback' => 몸통 앞면에서 들임,
      #   'cover' => 맨 위 덮개 선반 여부 }. 도어가 닫히도록 전판을 몸통 안쪽으로 들여 만든다.
      def build_inner_drawers(entities)
        d = @inner_drawers
        return unless d.is_a?(Hash) && d['count'].to_i > 0
        n       = d['count'].to_i
        fh      = d['height'].to_f.mm
        gap     = (d['gap'] || 3).to_f.mm
        setback = (d['setback'] || 25).to_f.mm
        dth     = Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm
        side    = 2.mm
        z0      = [d['bottom'].to_f.mm, @body_thickness].max
        open_w  = opening_width
        x0      = @body_thickness
        recess  = Kabinet::Constants::BACK_RECESS_MM.mm
        inner_depth_mm = Kabinet::Core::Fitting.len_mm(@depth - @back_thickness - recess - setback - dth)
        box = Kabinet::Core::Fitting.drawer_box_mm(
          open_w_mm: Kabinet::Core::Fitting.len_mm(open_w), comp_h_mm: Kabinet::Core::Fitting.len_mm(fh),
          inner_depth_mm: inner_depth_mm, type: (d['type'] || 'undermount'))
        wall_t = Kabinet::Constants::DRAWER_BOX_WALL_MM.mm
        bot_t  = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.mm
        box_w, box_d, box_h = box[:w].mm, box[:d].mm, box[:h].mm
        n.times do |i|
          z = z0 + i * (fh + gap)
          Kabinet::Geometry::Builder.box(entities, open_w - 2 * side, dth, fh,
                                         ::Geom::Transformation.new(::Geom::Point3d.new(x0 + side, setback, z)),
                                         role: "inner_dfr_#{i}", label: "내부서랍전판_#{i + 1}",
                                         material_name: 'drawer_front')
          bgrp = entities.add_group
          bgrp.transformation = ::Geom::Transformation.new(
            ::Geom::Point3d.new(x0 + (open_w - box_w) / 2.0, setback + dth, z + box[:z_off].mm))
          Kabinet::Persistence::Attributes.set_role(bgrp, "inner_dbox_#{i}")
          Kabinet::Geometry::Builder.box(bgrp.entities, box_w, box_d, bot_t, Kabinet::Geometry::Transforms::IDENTITY,
                                         role: 'drawer_bottom', material_name: 'drawer_box')
          Kabinet::Geometry::Builder.box(bgrp.entities, wall_t, box_d, box_h, Kabinet::Geometry::Transforms::IDENTITY,
                                         role: 'drawer_side_left', material_name: 'drawer_box')
          Kabinet::Geometry::Builder.box(bgrp.entities, wall_t, box_d, box_h,
                                         ::Geom::Transformation.new(::Geom::Point3d.new(box_w - wall_t, 0, 0)),
                                         role: 'drawer_side_right', material_name: 'drawer_box')
          Kabinet::Geometry::Builder.box(bgrp.entities, box_w - 2 * wall_t, wall_t, box_h,
                                         ::Geom::Transformation.new(::Geom::Point3d.new(wall_t, box_d - wall_t, 0)),
                                         role: 'drawer_back', material_name: 'drawer_box')
        end
        return unless d.fetch('cover', true)

        # 덮개 선반: 서랍 묶음 바로 위
        top_z = z0 + n * fh + (n - 1) * gap + gap
        play  = Kabinet::Constants::SHELF_SIDE_PLAY_MM.mm
        Kabinet::Geometry::Builder.box(entities, open_w - play, @depth - @back_thickness - recess, @body_thickness,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(x0 + play / 2.0, 0, top_z)),
                                       role: 'shelf', label: '서랍 덮개 선반', material_name: 'shelf')
      end

      def symbolize(hash)
        hash.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
      end
    end
  end
end
