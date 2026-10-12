module Kabinet
  module Core
    # Carcase + N stacked drawers (front + 5-sided box).
    # All inputs in SU Length.
    #
    # handle_type: 'none' | 'bar' | 'knob' | 'cup_pull' | 'channel' | 'push_open'
    #   각 서랍 전판에 손잡이 geometry 추가.
    #   'bar' 선택 시 handle_hole_mm(홀간거리)로 봉 길이 결정.
    #
    # 그룹 구조:
    #   module_group
    #   ├── body_grp     ← 카케이스 패널 (독립 선택 가능)
    #   └── drawers_grp  ← 서랍 전판 + 박스 (독립 선택 가능)
    #       ├── front_grp_0  (전판 + 손잡이)
    #       ├── drawer_box_0
    #       └── ...
    class DrawerModule
      attr_reader :width, :depth, :height, :body_thickness, :back_thickness,
                  :drawer_count, :drawer_type, :drawer_thickness,
                  :handle_type, :handle_hole_mm, :handle_pos, :has_back

      def initialize(width:, depth:, height:,
                     body_thickness:  Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM.mm,
                     back_thickness:  Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM.mm,
                     drawer_count:    1,
                     drawer_type:     'undermount',
                     drawer_thickness: Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM.mm,
                     handle_type:     'none',
                     handle_hole_mm:  128,
                     handle_pos:      'auto',
                     handle_rot:      'auto',
                     door_drop_mm:    0,
                     has_back:        true,
                     box_depth_mm:    nil, open_top: false, inner_drawer: false, drawer_ratios: nil, door_over_ep_mm: 0)
        @width            = width
        @depth            = depth
        @height           = height
        @body_thickness   = body_thickness
        @back_thickness   = back_thickness
        @drawer_count     = drawer_count
        @drawer_type      = drawer_type.to_s
        @drawer_thickness = drawer_thickness
        @handle_type      = handle_type.to_s
        @handle_hole_mm   = handle_hole_mm.to_i
        @handle_pos       = handle_pos.to_s
        @handle_rot       = handle_rot.to_s
        @door_drop_mm     = door_drop_mm.to_f   # 맨 아래 전판 하부 내림
        @has_back         = has_back ? true : false
        @open_top         = open_top ? true : false
        @inner_drawer     = inner_drawer ? true : false   # 맨 위 서랍 안 속서랍
        @drawer_ratios    = drawer_ratios                 # 서랍별 높이 비율 (아래 → 위)
        @door_over_ep_mm  = door_over_ep_mm.to_f          # 전판이 좌우 EP 를 덮는 양 (도어와 끝선 맞춤)
        # 서랍 박스 깊이 상한 (수납침대 등 깊은 카케이스에서 실물 서랍 깊이 제한)
        @box_depth_mm     = box_depth_mm ? box_depth_mm.to_f : nil
      end

      def carcase
        @carcase ||= Carcase.new(width: @width, depth: @depth, height: @height,
                                 body_thickness: @body_thickness, back_thickness: @back_thickness,
                                 has_back: @has_back, channel_top: channel?, open_top: @open_top)
      end

      def channel?
        @handle_type == 'channel'
      end

      def opening_width
        @width - 2 * @body_thickness
      end

      def opening_height
        @height - 2 * @body_thickness
      end

      def build(parent_entities, parent_transform, role: 'drawer_module', suppress_bottom: false)
        group = parent_entities.add_group
        group.transformation = parent_transform
        Kabinet::Persistence::Attributes.set_role(group, role,
                                                  width: @width.to_f, depth: @depth.to_f, height: @height.to_f,
                                                  drawer_count: @drawer_count, drawer_type: @drawer_type)

        # ── 몸통 그룹 (카케이스 패널 — 몸통과 서랍을 분리)
        body_grp = group.entities.add_group
        Kabinet::Persistence::Attributes.set_role(body_grp, 'body_group', label: '몸통')

        # 찬넬: 전판 위·전판 사이 = 손 넣는 틈(전판 내림). 각 틈 뒤에 ㄴ자 찬넬.
        drop         = Kabinet::Constants::CHANNEL_FRONT_DROP_MM.mm
        reveal       = channel? ? drop : Kabinet::Core::Gaps.drawer_between.mm
        front_offset = Kabinet::Core::Gaps.front_offset.mm
        wall_t       = Kabinet::Constants::DRAWER_BOX_WALL_MM.mm
        bot_t        = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.mm

        # ── 전판 레이아웃: Fitting 공식 (커트리스트와 동일) ──────────────
        fronts = Kabinet::Core::Fitting.drawer_fronts(
          @width, @height, @drawer_count,
          side_gap:   (Kabinet::Core::Gaps.drawer_gap - @door_over_ep_mm).mm,
          top_gap:    channel? ? drop : Kabinet::Core::Gaps.top.mm,
          bottom_gap: (@door_drop_mm > 0 ? -@door_drop_mm : Kabinet::Core::Gaps.bottom).mm,
          reveal:     reveal, ratios: @drawer_ratios)

        # 서랍 사이 찬넬 윗선 = 위 서랍 전판 아랫선 (맨 위 서랍 것은 카케이스 상단 — Joinery channel_top)
        mid_tops = channel? ? (0...(@drawer_count - 1)).map { |i| fronts[i][:z] + fronts[i][:h] + drop } : []

        c = Carcase.new(width: @width, depth: @depth, height: @height,
                        body_thickness: @body_thickness, back_thickness: @back_thickness,
                        has_back: @has_back, suppress_bottom: suppress_bottom, channel_top: channel?, open_top: @open_top,
                        channel_tops: mid_tops)
        c.build(body_grp.entities, Kabinet::Geometry::Transforms::IDENTITY, wrap_group: false)


        # 서랍 사이 찬넬 — 모듈 전체 폭 (측판은 그 자리가 따여 있음)
        mid_tops.each do |z_top|
          Kabinet::Geometry::Joinery.channel_rail(@width, 0, z_top, @body_thickness)
                                    .each { |ps| Panel.from_joinery(ps).build(body_grp.entities) }
        end

        # ── 서랍통 치수: 슬라이드 규격 스냅 (mm 계산 후 SU Length 변환) ──
        inner_depth_mm = Kabinet::Core::Fitting.len_mm(@depth - @back_thickness -
                                                       Kabinet::Constants::BACK_RECESS_MM.mm)
        inner_depth_mm = [inner_depth_mm, @box_depth_mm].min if @box_depth_mm
        # 칸 높이: 전판과 같은 비율로 개구 높이를 나눈다 (칸마다 서랍통 높이가 다를 수 있음)
        comp_hs = Kabinet::Core::Fitting.split_by_ratio(
          opening_height - reveal * (@drawer_count - 1), @drawer_count, @drawer_ratios)
        mm = Kabinet::Core::Fitting.method(:len_mm)
        clears = Kabinet::Core::Fitting.channel_box_clears_mm(
          channel?, fronts.map { |f| { z: mm.call(f[:z]), h: mm.call(f[:h]) } },
          comp_hs.map { |ch| mm.call(ch) }, mm.call(@body_thickness), mm.call(reveal))
        boxes = comp_hs.each_with_index.map do |ch, i|
          Kabinet::Core::Fitting.drawer_box_mm(
            open_w_mm:      mm.call(opening_width),
            comp_h_mm:      mm.call(ch) - clears[i],
            inner_depth_mm: inner_depth_mm,
            type:           @drawer_type)
        end
        box = boxes.first
        side_clear = (opening_width - box[:w].mm) / 2.0

        # ── 서랍 그룹 (전판 + 박스)
        # 빈 그룹은 SketchUp 이 다른 지오메트리 추가 때 지워 버리므로, 내용 넣기 직전에 만든다.
        drawers_grp = group.entities.add_group
        Kabinet::Persistence::Attributes.set_role(drawers_grp, 'drawers_group', label: '서랍')

        @drawer_count.times do |i|
          f = fronts[i]

          # ── 전판 서브그룹 (손잡이 포함, 개별 선택 가능)
          front_grp = drawers_grp.entities.add_group
          front_grp.transformation = ::Geom::Transformation.new(
            ::Geom::Point3d.new(f[:x], -(@drawer_thickness + front_offset), f[:z]))
          Kabinet::Persistence::Attributes.set_role(front_grp,
                                                    "drawer_front_#{i}", label: "서랍전판_#{i + 1}")

          Kabinet::Geometry::Builder.box(
            front_grp.entities, f[:w], @drawer_thickness, f[:h],
            Kabinet::Geometry::Transforms::IDENTITY,
            role: "drawer_front_#{i}", label: "drawer_front_#{i}",
            material_name: 'drawer_front')

          # 손잡이 geometry (전판 로컬 좌표: Y=0 전면) — 찬넬·푸시·없음은 만들지 않음
          Kabinet::Geometry::HandleBuilder.build(
            front_grp.entities, f[:w], @drawer_thickness, f[:h],
            @handle_type, hole_mm: @handle_hole_mm, panel_role: :drawer, pos: @handle_pos, rot: @handle_rot)

          # ── 서랍 박스 (5-sided box)
          box   = boxes[i]
          z_box = @body_thickness + comp_hs.first(i).sum + i * reveal + box[:z_off].mm
          # 속서랍: 맨 위 칸만 — 본 서랍통을 낮추고 그 위에 낮은 서랍통을 하나 더
          split = (@inner_drawer && i == @drawer_count - 1) ?
                  Kabinet::Core::Fitting.inner_drawer_split_mm(box[:h]) : nil
          main_h = split ? split[0] : box[:h]
          build_drawer_box(drawers_grp.entities,
                           x: @body_thickness + side_clear, y: 0, z: z_box,
                           w: box[:w].mm, d: box[:d].mm, h: main_h.mm,
                           wall_t: wall_t, bot_t: bot_t,
                           index: i)
          if split
            build_drawer_box(drawers_grp.entities,
                             x: @body_thickness + side_clear, y: 0,
                             z: z_box + (main_h + Kabinet::Constants::INNER_DRAWER_GAP_MM).mm,
                             w: box[:w].mm, d: box[:d].mm, h: split[1].mm,
                             wall_t: wall_t, bot_t: bot_t,
                             index: "#{i}_inner")
          end
        end

        group
      end

      def self.from_hash(h)
        new(width:            (h['width']  || 600).mm,
            depth:            (h['depth']  || 400).mm,
            height:           (h['height'] || 200).mm,
            body_thickness:   (h['body_thickness'] || Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM).mm,
            back_thickness:   (h['back_thickness'] || Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM).mm,
            drawer_count:     (h['drawer_count'] || 1).to_i,
            drawer_type:      h['drawer_type'] || 'undermount',
            drawer_thickness: (h['drawer_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM).mm,
            handle_type:      h['handle_type']     || 'none',
            handle_hole_mm:   (h['handle_hole_mm'] || 128).to_i,
            handle_pos:       h['handle_pos']      || 'auto',
            handle_rot:       h['handle_rot']      || 'auto',
            door_drop_mm:     h['door_drop_mm'].to_f,
            has_back:         h.fetch('has_back', true) ? true : false,
            box_depth_mm:     h['box_depth_mm'],
            open_top:         h['open_top'],
            inner_drawer:     h['inner_drawer'],
            drawer_ratios:    h['drawer_ratios'],
            door_over_ep_mm:  h['door_over_ep_mm'])
      end

      private

      def build_drawer_box(parent_entities, x:, y:, z:, w:, d:, h:, wall_t:, bot_t:, index:)
        wrap = parent_entities.add_group
        wrap.transformation = ::Geom::Transformation.new(::Geom::Point3d.new(x, y, z))
        Kabinet::Persistence::Attributes.set_role(wrap, "drawer_box_#{index}")

        # Bottom
        Kabinet::Geometry::Builder.box(wrap.entities, w, d, bot_t,
                                       Kabinet::Geometry::Transforms::IDENTITY,
                                       role: 'drawer_bottom', material_name: 'drawer_box')
        # Side L
        Kabinet::Geometry::Builder.box(wrap.entities, wall_t, d, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(0, 0, 0)),
                                       role: 'drawer_side_left', material_name: 'drawer_box')
        # Side R
        Kabinet::Geometry::Builder.box(wrap.entities, wall_t, d, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(w - wall_t, 0, 0)),
                                       role: 'drawer_side_right', material_name: 'drawer_box')
        # Front (inner front wall)
        Kabinet::Geometry::Builder.box(wrap.entities, w - 2 * wall_t, wall_t, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(wall_t, 0, 0)),
                                       role: 'drawer_inner_front', material_name: 'drawer_box')
        # Back
        Kabinet::Geometry::Builder.box(wrap.entities, w - 2 * wall_t, wall_t, h,
                                       ::Geom::Transformation.new(::Geom::Point3d.new(wall_t, d - wall_t, 0)),
                                       role: 'drawer_back', material_name: 'drawer_box')
      end
    end
  end
end
