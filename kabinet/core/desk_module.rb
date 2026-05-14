module Kabinet
  module Core
    # 책상 (Desk) 모듈
    #
    # 구성:
    #   상판 (top panel)
    #   다리 — leg_type: 'box'(사각, 기본) | 'round'(원형 12면 근사)
    #   페데스탈 — 지지 서랍장 (다리 대신 한쪽을 서랍장이 지지)
    #   상판 하부 서랍 유닛 — 상판 밑에 매달리는 소형 서랍
    #   가림판 (모데스티 패널) — 뒤쪽 하단 케이블/다리 가림
    #
    # JSON 스키마 (mm 단위):
    #   { kind: 'desk_module',
    #     width: 1400, depth: 700, height: 750,
    #     top_thickness: 25,
    #     leg_type: 'box',    # 'box' | 'round'
    #     leg_w: 60, leg_d: 60,
    #     leg_inset_x: 30, leg_inset_y: 30,
    #     has_modesty_panel: false,
    #     pedestal: {
    #       enabled: true, position: 'right',   # 'left' | 'right'
    #       width: 450, depth: 650, drawer_count: 3,
    #       drawer_type: 'undermount'
    #     },
    #     under_unit: {
    #       enabled: true, position: 'right',   # 'left' | 'right' | 'center'
    #       width: 400, height: 130, drawer_count: 1,
    #       drawer_type: 'undermount'
    #     }
    #   }
    #
    # 모든 dimension은 SU Length (from_hash에서 .mm 변환).
    class DeskModule
      attr_reader :width, :depth, :height, :top_thickness,
                  :leg_type, :leg_w, :leg_d, :leg_inset_x, :leg_inset_y,
                  :has_modesty_panel, :pedestal, :under_unit

      def initialize(width:, depth:, height:,
                     top_thickness: 25.mm,
                     leg_type: 'box',
                     leg_w: 60.mm, leg_d: 60.mm,
                     leg_inset_x: 30.mm, leg_inset_y: 30.mm,
                     has_modesty_panel: false,
                     pedestal: nil, under_unit: nil)
        @width            = width
        @depth            = depth
        @height           = height
        @top_thickness    = top_thickness
        @leg_type         = leg_type.to_s
        @leg_w            = leg_w
        @leg_d            = leg_d
        @leg_inset_x      = leg_inset_x
        @leg_inset_y      = leg_inset_y
        @has_modesty_panel = has_modesty_panel
        @pedestal         = pedestal   # Hash with string keys, or nil
        @under_unit       = under_unit # Hash with string keys, or nil
      end

      # suppress_bottom는 책상에 미적용(다리가 바닥을 대신하므로).
      def build(parent_entities, parent_transform, role: 'desk_module', suppress_bottom: false)
        group = parent_entities.add_group
        group.transformation = parent_transform
        Kabinet::Persistence::Attributes.set_role(group, role,
          width: @width.to_f, depth: @depth.to_f, height: @height.to_f)

        leg_h = @height - @top_thickness  # 다리(+페데스탈) 높이

        # ── 상판 ─────────────────────────────────────────────────────────
        top_local = ::Geom::Transformation.new(::Geom::Point3d.new(0, 0, leg_h))
        Kabinet::Geometry::Builder.box(group.entities, @width, @depth, @top_thickness,
                                       top_local, role: 'desk_top',
                                       label: '책상_상판', material_name: 'top')

        # ── 가림판 (모데스티 패널) ─────────────────────────────────────
        if @has_modesty_panel
          mp_t  = 18.mm
          mp_h  = (leg_h * 0.6).to_f   # 다리 높이의 60%
          mp_y  = @depth - mp_t
          mp_z  = leg_h - mp_h
          mp_local = ::Geom::Transformation.new(::Geom::Point3d.new(0, mp_y, mp_z))
          Kabinet::Geometry::Builder.box(group.entities, @width, mp_t, mp_h,
                                         mp_local, role: 'modesty_panel',
                                         label: '가림판', material_name: 'body')
        end

        # ── 페데스탈 (지지 서랍장) ────────────────────────────────────
        ped_covers_left  = false
        ped_covers_right = false

        if active?(pedestal)
          p         = @pedestal
          ped_w     = (p['width']         || 450).mm
          ped_d     = (p['depth']         || @depth.to_f).mm
          ped_h     = leg_h                           # 상판 밑까지
          ped_dc    = (p['drawer_count']  || 3).to_i
          ped_dt    = p['drawer_type']   || 'undermount'
          ped_bkt   = 18.mm

          case (p['position'] || 'right').to_s
          when 'left'
            ped_x = 0
            ped_covers_left = true
          else
            ped_x = @width - ped_w
            ped_covers_right = true
          end

          ped_local = ::Geom::Transformation.new(::Geom::Point3d.new(ped_x, 0, 0))
          ped_mod   = DrawerModule.new(
            width:          ped_w,
            depth:          ped_d,
            height:         ped_h,
            body_thickness: ped_bkt,
            drawer_count:   ped_dc,
            drawer_type:    ped_dt,
            drawer_thickness: 18.mm
          )
          ped_mod.build(group.entities, ped_local, role: 'desk_pedestal')
        end

        # ── 다리 ─────────────────────────────────────────────────────
        build_legs(group.entities, leg_h, ped_covers_left, ped_covers_right)

        # ── 상판 하부 서랍 유닛 ───────────────────────────────────────
        build_under_unit(group.entities, leg_h) if active?(under_unit)

        group
      end

      def self.from_hash(h)
        new(
          width:             h['width'].mm,
          depth:             h['depth'].mm,
          height:            h['height'].mm,
          top_thickness:     (h['top_thickness']   || 25).mm,
          leg_type:          (h['leg_type']         || 'box'),
          leg_w:             (h['leg_w']            || 60).mm,
          leg_d:             (h['leg_d']            || 60).mm,
          leg_inset_x:       (h['leg_inset_x']      || 30).mm,
          leg_inset_y:       (h['leg_inset_y']      || 30).mm,
          has_modesty_panel: (h['has_modesty_panel'] == true),
          pedestal:          h['pedestal'],
          under_unit:        h['under_unit']
        )
      end

      private

      # Hash가 enabled: false 가 아닌 경우 활성으로 판단
      def active?(h)
        h.is_a?(Hash) && h['enabled'] != false
      end

      # ── 다리 배치 ────────────────────────────────────────────────────
      # 페데스탈이 있는 쪽의 다리 생략.
      # 사각 다리: box 프리미티브. 원형 다리: 12면 프리즘.
      def build_legs(entities, leg_h, skip_left, skip_right)
        lw  = @leg_w
        ld  = @leg_d
        ix  = @leg_inset_x
        iy  = @leg_inset_y
        w   = @width
        d   = @depth

        # [x_origin, y_origin, skip?, label_suffix]
        corners = [
          [ix,       iy,       skip_left,  'FL'],   # 앞좌
          [w-ix-lw,  iy,       skip_right, 'FR'],   # 앞우
          [ix,       d-iy-ld,  skip_left,  'BL'],   # 뒤좌
          [w-ix-lw,  d-iy-ld,  skip_right, 'BR'],   # 뒤우
        ]

        corners.each_with_index do |(lx, ly, skip, suffix), idx|
          next if skip
          local = ::Geom::Transformation.new(::Geom::Point3d.new(lx, ly, 0))
          if @leg_type == 'round'
            cx = lx + lw / 2.0
            cy = ly + ld / 2.0
            build_round_leg(entities, cx, cy, leg_h, lw / 2.0, suffix)
          else
            Kabinet::Geometry::Builder.box(
              entities, lw, ld, leg_h, local,
              role:          "desk_leg_#{suffix}",
              label:         "책상다리_#{suffix}",
              material_name: 'body'
            )
          end
        end
      end

      # 12면 원기둥 근사 다리
      def build_round_leg(entities, cx, cy, h, radius, suffix)
        g = entities.add_group
        g.transformation = ::Geom::Transformation.new(::Geom::Point3d.new(cx, cy, 0))
        segs = 12
        pts  = segs.times.map do |s|
          ang = s * 2.0 * Math::PI / segs
          ::Geom::Point3d.new(radius * Math.cos(ang), radius * Math.sin(ang), 0)
        end
        face = g.entities.add_face(pts)
        return unless face
        face.pushpull(face.normal.z > 0 ? h : -h, true)
        Kabinet::Persistence::Attributes.set_role(g, "desk_leg_#{suffix}",
                                                  label: "책상다리_#{suffix}")
      rescue StandardError
        nil
      end

      # ── 상판 하부 서랍 유닛 ─────────────────────────────────────────
      # 상판 아랫면에 붙어서 매달리는 소형 서랍.
      # 바닥에 닿지 않음.
      def build_under_unit(entities, leg_h)
        u     = @under_unit
        uu_w  = (u['width']        || 400).mm
        uu_h  = (u['height']       || 130).mm
        uu_dc = (u['drawer_count'] || 1).to_i
        uu_dt = u['drawer_type']  || 'undermount'
        uu_bt = 18.mm

        case (u['position'] || 'right').to_s
        when 'left'
          uu_x = uu_bt  # 왼쪽 다리/벽에서 한 몸통두께 안쪽
        when 'center'
          uu_x = (@width - uu_w) / 2.0
        else
          uu_x = @width - uu_w - uu_bt
        end

        uu_z  = leg_h - uu_h  # 상판 아랫면에 붙음
        uu_d  = @depth - 80.mm  # 앞뒤 각 40mm 여백

        uu_local = ::Geom::Transformation.new(::Geom::Point3d.new(uu_x, 40.mm, uu_z))
        DrawerModule.new(
          width:          uu_w,
          depth:          uu_d,
          height:         uu_h,
          body_thickness: uu_bt,
          drawer_count:   uu_dc,
          drawer_type:    uu_dt,
          drawer_thickness: 18.mm
        ).build(entities, uu_local, role: 'desk_under_unit')
      end
    end
  end
end
