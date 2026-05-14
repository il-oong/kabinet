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
                  :door_side_gap_mm, :suppress_left_side, :suppress_right_side

      def initialize(width:, depth:, height:,
                     body_thickness: Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness: Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     door_config: 'none', door_type: 'swing',
                     door_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.mm,
                     shelves: [], accessories: [],
                     vertical_dividers: [], cell_shelves: [], cell_drawers: [],
                     handle_type: 'none', handle_hole_mm: 128,
                     door_mount: 'overlay',
                     door_side_gap_mm: 0,
                     suppress_left_side: false, suppress_right_side: false)
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
        @handle_type       = handle_type.to_s
        @handle_hole_mm    = handle_hole_mm.to_i
        @door_mount        = door_mount.to_s
        @door_side_gap_mm  = door_side_gap_mm.to_f
        @suppress_left_side  = suppress_left_side  ? true : false
        @suppress_right_side = suppress_right_side ? true : false
      end

      def carcase
        @carcase ||= Carcase.new(width: @width, depth: @depth, height: @height,
                                 body_thickness: @body_thickness, back_thickness: @back_thickness,
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
                        suppress_bottom: suppress_bottom,
                        suppress_left_side: @suppress_left_side,
                        suppress_right_side: @suppress_right_side)
        c.build(body_grp.entities, Kabinet::Geometry::Transforms::IDENTITY, wrap_group: false)

        # ── 전체폭 선반 ──────────────────────────────────────────────
        @shelves.each do |s|
          z      = s['height_from_bottom'].mm
          t      = s['thickness'].mm
          inset  = s['depth_inset'].mm
          recess = Kabinet::Constants::BACK_RECESS_MM.mm
          shelf_d = @depth - inset - @back_thickness - recess
          local   = ::Geom::Transformation.new(::Geom::Point3d.new(@body_thickness, 0, z))
          Kabinet::Geometry::Builder.box(body_grp.entities, opening_width, shelf_d, t,
                                         local, role: 'shelf', label: 'shelf',
                                         material_name: 'shelf')
        end

        # ── 세로 분할판 ──────────────────────────────────────────────
        build_vertical_dividers(body_grp.entities)

        # ── 셀별 선반 ────────────────────────────────────────────────
        build_cell_shelves(body_grp.entities)

        # ── 셀별 서랍 컬럼 ───────────────────────────────────────────
        build_cell_drawers(body_grp.entities)

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
              reveal_between: Kabinet::Constants::DOOR_REVEAL_BETWEEN_MM.mm,
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
              gap_top:        Kabinet::Constants::DOOR_GAP_TOP_MM.mm,
              gap_bottom:     Kabinet::Constants::DOOR_GAP_BOTTOM_MM.mm,
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
            handle_type:       h['handle_type']    || 'none',
            handle_hole_mm:    (h['handle_hole_mm'] || 128).to_i,
            door_mount:        h['door_mount']     || 'overlay',
            door_side_gap_mm:  (h['door_side_gap_mm'] || 0).to_f,
            suppress_left_side:  h.fetch('suppress_left_side',  false) ? true : false,
            suppress_right_side: h.fetch('suppress_right_side', false) ? true : false)
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
      # Cell 0 is leftmost.
      def cell_ranges
        inner_w   = opening_width
        sorted    = (@vertical_dividers || []).sort_by { |d| d['x'].to_f }
        prev_edge = 0.mm
        cells     = []

        sorted.each do |div|
          x  = div['x'].to_f.mm
          dt = (div['thickness'] || 18).mm
          cells << { x_start: prev_edge, x_end: x, width: x - prev_edge }
          prev_edge = x + dt
        end
        cells << { x_start: prev_edge, x_end: inner_w, width: inner_w - prev_edge }
        cells
      end

      # ── 셀별 선반 ─────────────────────────────────────────────────
      def build_cell_shelves(entities)
        return if @cell_shelves.empty?
        recess = Kabinet::Constants::BACK_RECESS_MM.mm
        cells  = cell_ranges

        @cell_shelves.each do |cs|
          cell = cells[(cs['cell'] || 0).to_i]
          next unless cell && cell[:width] > 0

          z       = cs['height_from_bottom'].mm
          t       = (cs['thickness'] || 18).mm
          inset   = (cs['depth_inset'] || 0).mm
          shelf_d = @depth - @back_thickness - recess - inset
          x_orig  = @body_thickness + cell[:x_start]

          local = ::Geom::Transformation.new(::Geom::Point3d.new(x_orig, 0, z))
          Kabinet::Geometry::Builder.box(entities, cell[:width], shelf_d, t,
                                         local,
                                         role:          "cell_shelf_#{cs['cell']}",
                                         label:         "셀선반_#{(cs['cell'] || 0) + 1}",
                                         material_name: 'shelf')
        end
      end

      # ── 셀별 서랍 컬럼 ────────────────────────────────────────────
      # 셀 내부 전 높이를 서랍으로 채움. 전판은 카케이스 전면 오버레이.
      def build_cell_drawers(entities)
        return if @cell_drawers.empty?
        recess       = Kabinet::Constants::BACK_RECESS_MM.mm
        gap_o        = Kabinet::Constants::DOOR_GAP_OUTSIDE_MM.mm
        gap_t        = Kabinet::Constants::DOOR_GAP_TOP_MM.mm
        gap_b        = Kabinet::Constants::DOOR_GAP_BOTTOM_MM.mm
        reveal       = Kabinet::Constants::DRAWER_REVEAL_BETWEEN_MM.mm
        front_offset = Kabinet::Constants::DOOR_FRONT_OFFSET_MM.mm
        wall_t       = Kabinet::Constants::DRAWER_BOX_WALL_MM.mm
        bot_t        = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.mm
        cells        = cell_ranges

        @cell_drawers.each do |cd|
          cell_idx = (cd['cell'] || 0).to_i
          cell     = cells[cell_idx]
          next unless cell && cell[:width] > 0

          dc  = (cd['count'] || 2).to_i
          dt  = cd['type'] || 'undermount'
          dth = (cd['thickness'] || 18).mm

          # 서랍 슬라이드별 클리어런스
          sc = (dt == 'undermount' ?
                Kabinet::Constants::UNDERMOUNT_SIDE_CLEARANCE_MM :
                Kabinet::Constants::SIDEMOUNT_SIDE_CLEARANCE_MM).mm
          ho = (dt == 'undermount' ?
                Kabinet::Constants::UNDERMOUNT_HEIGHT_OFFSET_MM :
                Kabinet::Constants::SIDEMOUNT_HEIGHT_OFFSET_MM).mm

          # 내부 Z 범위 (하판 위 ~ 상판 아래)
          z_int_start = @body_thickness
          z_int_end   = @height - @body_thickness
          int_h       = z_int_end - z_int_start

          avail_h     = int_h - gap_t - gap_b - (reveal * (dc - 1))
          front_h     = avail_h / dc.to_f
          compartment_h = avail_h / dc.to_f

          cell_x      = @body_thickness + cell[:x_start]
          cell_w      = cell[:width]
          front_w     = cell_w - 2 * gap_o
          box_d       = @depth - @back_thickness - recess - 30.mm
          box_w       = cell_w - 2 * sc
          box_x       = cell_x + sc

          dc.times do |i|
            # 서랍 전판
            z_front = z_int_start + gap_b + i * (front_h + reveal)
            fl = ::Geom::Transformation.new(
              ::Geom::Point3d.new(cell_x + gap_o,
                                   -(dth + front_offset),
                                   z_front))
            Kabinet::Geometry::Builder.box(entities, front_w, dth, front_h, fl,
                                           role:          "cell_dfr_#{cell_idx}_#{i}",
                                           label:         "셀서랍전판_c#{cell_idx}_#{i + 1}",
                                           material_name: 'drawer_front')

            # 서랍 박스
            z_box = z_int_start + gap_b + i * (compartment_h + reveal) + ho / 2.0
            box_h = compartment_h - ho
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

      def symbolize(hash)
        hash.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
      end
    end
  end
end
