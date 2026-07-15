# 2D 발주도면 투영 엔진 — 순수 루비, SketchUp API 불필요.
#
# 정규화된 spec 해시(mm Float)에서 정면도/측면도/평면도의 2D 지오메트리를
# 생성한다. 치수 공식은 Core::Fitting을 사용하므로 3D 모델·커트리스트와
# 항상 일치한다.
#
# 뷰 좌표계 (mm):
#   정면도(front): X = 가구 폭 방향, Y = 높이 (아래 0)
#   측면도(side):  X = 깊이 방향 (앞면 0), Y = 높이
#   평면도(top):   X = 가구 폭 방향, Y = 깊이 (앞면 0 → 위가 뒷면)
#
# 반환 형식 (뷰별):
#   { name:, label:, width:, height:,
#     lines:  [{ x1:, y1:, x2:, y2:, layer: }, ...],
#     rects:  [{ x:, y:, w:, h:, layer: }, ...],       # 외곽 사각
#     dims:   [{ x1:, y1:, x2:, y2:, offset:, text:, dir: :h|:v }, ...],
#     texts:  [{ x:, y:, text:, height:, layer: }, ...] }
#
# 레이어 의미:
#   OUTLINE — 외곽/부재 실선,  HIDDEN — 은선(내부 구조),
#   FRONTS  — 도어/서랍 전판,  DIM — 치수, TEXT — 문자
module Kabinet
  module Output
    module Drawing2D
      module_function

      C   = Kabinet::Constants
      FIT = Kabinet::Core::Fitting

      # spec: Schema.normalize 결과. 반환: [front_view, side_view, top_view]
      def views(spec)
        g = geometry_params(spec)
        [front_view(spec, g), side_view(spec, g), top_view(spec, g)]
      end

      # ── 공통 파라미터 (Assembly와 동일 계산) ────────────────────────────
      def geometry_params(spec)
        run    = spec['run_mode'] ? true : false
        ep     = spec['ep'] || {}
        ep_l   = ep['left']  ? true : false
        ep_r   = ep['right'] ? true : false
        ep_t   = (ep['thickness'] || 18).to_f
        ep_top_t = ep['top'] ? ep_t : 0.0
        top_t  = spec['top_panel'] ? spec['top_panel']['thickness'].to_f : 0.0
        base_h = (spec['base_height'] || 0).to_f
        max_d  = spec['max_depth'].to_f

        mods = spec['modules'] || []
        if run
          carcase_w = mods.sum { |m| m['width'].to_f }
          content_h = spec['run_height'].to_f
        else
          carcase_w = spec['width'].to_f - (ep_l ? ep_t : 0) - (ep_r ? ep_t : 0)
          content_h = mods.reject { |m| m['kind'] == 'bed_gap' }
                          .sum { |m| m['height'].to_f }
        end

        total_w = (ep_l ? ep_t : 0) + carcase_w + (ep_r ? ep_t : 0)
        total_h = base_h + content_h + top_t + ep_top_t
        prot    = ep.fetch('cover_fronts', true) ? FIT.front_protrusion_mm(mods) : 0.0

        { run: run, ep_l: ep_l, ep_r: ep_r, ep_t: ep_t, ep_top_t: ep_top_t,
          top_t: top_t, base_h: base_h, max_d: max_d,
          carcase_w: carcase_w, content_h: content_h,
          total_w: total_w, total_h: total_h, prot: prot }
      end

      # ── 정면도 ───────────────────────────────────────────────────────────
      def front_view(spec, g)
        v = new_view('front', '정면도  FRONT', g[:total_w], g[:total_h])
        x_car   = g[:ep_l] ? g[:ep_t] : 0.0
        has_gap = g[:run] && (spec['modules'] || []).any? { |m| m['kind'] == 'bed_gap' }
        cap     = g[:total_h] - g[:ep_top_t]   # 상부 EP 아랫면 (없으면 total_h)

        if has_gap
          # bed_gap 존재: 외곽/상판/받침을 침대 공간 제외 구간별로 그림
          run_segments(spec['modules']).each do |seg_x, seg_w|
            sx = x_car + seg_x
            rect(v, sx, g[:base_h], seg_w, g[:content_h], 'OUTLINE')
            if g[:top_t] > 0
              rect(v, sx, g[:base_h] + g[:content_h], seg_w, g[:top_t], 'OUTLINE')
            end
            rect(v, sx, 0, seg_w, g[:base_h], 'HIDDEN') if g[:base_h] > 0
          end
          # EP는 양끝 독립 기둥
          rect(v, 0, g[:base_h], g[:ep_t], cap - g[:base_h], 'OUTLINE') if g[:ep_l]
          rect(v, g[:total_w] - g[:ep_t], g[:base_h], g[:ep_t],
               cap - g[:base_h], 'OUTLINE') if g[:ep_r]
          # 상부 EP 밴드 (전체 폭)
          rect(v, 0, cap, g[:total_w], g[:ep_top_t], 'OUTLINE') if g[:ep_top_t] > 0
        else
          # 외곽
          rect(v, 0, g[:base_h], g[:total_w], cap - g[:base_h], 'OUTLINE')
          # 상부 EP 밴드 (전체 폭)
          rect(v, 0, cap, g[:total_w], g[:ep_top_t], 'OUTLINE') if g[:ep_top_t] > 0

          # 받침(걸레받이) — 후퇴되어 은선 처리
          if g[:base_h] > 0
            rect(v, x_car, 0, g[:carcase_w], g[:base_h], 'HIDDEN')
            line(v, 0, g[:base_h], g[:total_w], g[:base_h], 'OUTLINE')
          end

          # EP 경계선
          line(v, x_car, g[:base_h], x_car, cap, 'OUTLINE') if g[:ep_l]
          if g[:ep_r]
            xr = x_car + g[:carcase_w]
            line(v, xr, g[:base_h], xr, cap, 'OUTLINE')
          end

          # 상판 경계선
          if g[:top_t] > 0
            line(v, x_car, cap - g[:top_t],
                 x_car + g[:carcase_w], cap - g[:top_t], 'OUTLINE')
          end
        end

        # 모듈 배치 + 내부 구성
        each_module_frame(spec, g) do |m, mx, mz, mw, mh|
          front_module(v, spec, g, m, x_car + mx, g[:base_h] + mz, mw, mh)
        end

        # ── 치수: 전체 폭(하단), 전체 높이(좌측) ──
        dim(v, 0, 0, g[:total_w], 0, -dim_off(g), "#{fmt(g[:total_w])}", :h)
        dim(v, 0, 0, 0, g[:total_h], -dim_off(g), "#{fmt(g[:total_h])}", :v)

        # 분할 치수 (2단계): stack → 모듈 높이, run → 섹션 폭
        if g[:run]
          x = x_car
          (spec['modules'] || []).each do |m|
            w = m['width'].to_f
            dim(v, x, g[:total_h], x + w, g[:total_h], dim_off(g) * 0.6, fmt(w), :h)
            x += w
          end
        else
          z = g[:base_h]
          (spec['modules'] || []).each do |m|
            next if m['kind'] == 'bed_gap'
            h = m['height'].to_f
            dim(v, g[:total_w], z, g[:total_w], z + h, dim_off(g) * 0.6, fmt(h), :v)
            z += h
          end
          if g[:base_h] > 0
            dim(v, g[:total_w], 0, g[:total_w], g[:base_h], dim_off(g) * 0.6, fmt(g[:base_h]), :v)
          end
        end
        v
      end

      # 모듈 프레임 순회: yield(m, x, z, w, h) — 카케이스 좌하단 기준 mm
      def each_module_frame(spec, g)
        mods = spec['modules'] || []
        if g[:run]
          x = 0.0
          mods.each do |m|
            w = m['width'].to_f
            yield(m, x, 0.0, w, g[:content_h]) unless m['kind'] == 'bed_gap'
            x += w
          end
        else
          z = 0.0
          mods.each do |m|
            next if m['kind'] == 'bed_gap'
            h = m['height'].to_f
            yield(m, 0.0, z, g[:carcase_w], h)
            z += h
          end
        end
      end

      # 정면도의 모듈 1개: 도어/전판(실선) 또는 내부 구조(은선)
      def front_module(v, _spec, _g, m, x, z, w, h)
        case m['kind']
        when 'drawer_module'
          fronts = FIT.drawer_fronts(w, h, (m['drawer_count'] || 1).to_i,
                                     side_gap:   C::DRAWER_FRONT_GAP_MM.to_f,
                                     top_gap:    C::DOOR_GAP_TOP_MM.to_f,
                                     bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                                     reveal:     C::DRAWER_REVEAL_BETWEEN_MM.to_f)
          fronts.each { |f| rect(v, x + f[:x], z + f[:z], f[:w], f[:h], 'FRONTS') }
        when 'desk_module'
          front_desk(v, m, x, z, w, h)
        when 'shelf_module'
          bt = m['body_thickness'].to_f
          # 몸통 내부 경계 (은선)
          rect(v, x + bt, z + bt, w - 2 * bt, h - 2 * bt, 'HIDDEN')

          # 내부 구조: 분할판/선반/셀 (은선)
          inner_w = w - 2 * bt
          (m['vertical_dividers'] || []).each do |d|
            dx = x + bt + d['x'].to_f
            dt = (d['thickness'] || 18).to_f
            rect(v, dx, z + bt, dt, h - 2 * bt, 'HIDDEN')
          end
          (m['shelves'] || []).each do |s|
            sz = z + (s['height_from_bottom'] || 0).to_f
            line(v, x + bt, sz, x + bt + inner_w, sz, 'HIDDEN')
            line(v, x + bt, sz + (s['thickness'] || 18).to_f,
                 x + bt + inner_w, sz + (s['thickness'] || 18).to_f, 'HIDDEN')
          end
          cell_edges = cell_edges_for(m, inner_w)
          (m['cell_shelves'] || []).each do |cs|
            rng = cell_edges[(cs['cell'] || 0).to_i]
            next unless rng
            # 셀 선반 높이는 모듈 바닥 기준 (3D 지오메트리와 동일)
            sz = z + (cs['height_from_bottom'] || 0).to_f
            line(v, x + bt + rng[0], sz, x + bt + rng[1], sz, 'HIDDEN')
          end

          # 도어/셀서랍 전판 (실선)
          front_doors(v, m, x, z, w, h)
          front_cell_drawers(v, m, x, z, w, h, cell_edges, bt)
        end
      end

      def front_doors(v, m, x, z, w, h)
        dc = m['door_config'] || 'none'
        return if dc == 'none'
        mount    = m['door_mount'] || 'overlay'
        side_gap = (m['door_side_gap_mm'] || C::DOOR_GAP_OUTSIDE_MM).to_f
        bt       = m['body_thickness'].to_f

        doors =
          case m['door_type']
          when 'sliding'
            base_w = mount == 'inset' ? w - 2 * bt : w
            base_h = mount == 'inset' ? h - 2 * bt : h
            FIT.sliding_doors(base_w, base_h, dc,
                              overlap:    C::SLIDING_DOOR_OVERLAP_MM.to_f,
                              top_gap:    C::SLIDING_DOOR_TOP_GAP_MM.to_f,
                              bottom_gap: C::SLIDING_DOOR_BOTTOM_GAP_MM.to_f)
          when 'folding'
            FIT.folding_doors(w, h, dc,
                              side_gap: side_gap,
                              top_gap: C::DOOR_GAP_TOP_MM.to_f,
                              bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                              center_gap: C::DOOR_REVEAL_BETWEEN_MM.to_f)
          when 'lift_up'
            base_w = mount == 'inset' ? w - 2 * bt : w
            base_h = mount == 'inset' ? h - 2 * bt : h
            FIT.lift_up_door(base_w, base_h, gap: C::LIFT_UP_DOOR_GAP_MM.to_f)
          else
            if mount == 'inset'
              FIT.inset_doors(w - 2 * bt, h - 2 * bt, dc,
                              gap: C::INSET_DOOR_GAP_MM.to_f,
                              center_gap: C::DOOR_REVEAL_BETWEEN_MM.to_f)
            else
              FIT.swing_doors(w, h, dc,
                              side_gap: side_gap,
                              top_gap: C::DOOR_GAP_TOP_MM.to_f,
                              bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                              center_gap: C::DOOR_REVEAL_BETWEEN_MM.to_f)
            end
          end

        off = mount == 'inset' ? bt : 0.0
        doors.each do |d|
          rect(v, x + off + d[:x], z + off + d[:z], d[:w], d[:h], 'FRONTS')
          # 여닫이 개폐 방향 표시 (실무 관행: 힌지 반대쪽에 사선)
          if (m['door_type'] || 'swing') == 'swing'
            hinge_left = d[:role].to_s.include?('right') ? false : true
            swing_mark(v, x + off + d[:x], z + off + d[:z], d[:w], d[:h], hinge_left)
          end
        end
      end

      # 여닫이 개폐 표시: 힌지측 상/하 꼭짓점 → 손잡이측 중앙 (V자 사선)
      def swing_mark(v, x, z, w, h, hinge_left)
        if hinge_left
          line(v, x, z, x + w, z + h / 2.0, 'SYMBOL')
          line(v, x, z + h, x + w, z + h / 2.0, 'SYMBOL')
        else
          line(v, x + w, z, x, z + h / 2.0, 'SYMBOL')
          line(v, x + w, z + h, x, z + h / 2.0, 'SYMBOL')
        end
      end

      def front_cell_drawers(v, m, x, z, w, h, cell_edges, bt)
        int_h = h - 2 * bt
        (m['cell_drawers'] || []).each do |cd|
          rng = cell_edges[(cd['cell'] || 0).to_i]
          next unless rng
          fronts = FIT.drawer_fronts(rng[1] - rng[0], int_h, (cd['count'] || 2).to_i,
                                     side_gap:   C::DOOR_GAP_OUTSIDE_MM.to_f,
                                     top_gap:    C::DOOR_GAP_TOP_MM.to_f,
                                     bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                                     reveal:     C::DRAWER_REVEAL_BETWEEN_MM.to_f)
          fronts.each do |f|
            rect(v, x + bt + rng[0] + f[:x], z + bt + f[:z], f[:w], f[:h], 'FRONTS')
          end
        end
        _ = w
      end

      def front_desk(v, m, x, z, w, h)
        top_t = (m['top_thickness'] || 25).to_f
        leg_h = h - top_t
        rect(v, x, z + leg_h, w, top_t, 'OUTLINE')                   # 상판
        lw = (m['leg_w'] || 60).to_f
        ix = (m['leg_inset_x'] || 30).to_f
        ped = m['pedestal']
        ped_on  = ped.is_a?(Hash) && ped['enabled'] != false
        ped_pos = ped_on ? (ped['position'] || 'right').to_s : ''
        # 다리
        rect(v, x + ix, z, lw, leg_h, 'OUTLINE')          unless ped_pos == 'left'
        rect(v, x + w - ix - lw, z, lw, leg_h, 'OUTLINE') unless ped_pos == 'right'
        # 페데스탈
        if ped_on
          pw = (ped['width'] || 450).to_f
          px = ped_pos == 'left' ? x : x + w - pw
          rect(v, px, z, pw, leg_h, 'OUTLINE')
          fronts = FIT.drawer_fronts(pw, leg_h, (ped['drawer_count'] || 3).to_i,
                                     side_gap:   C::DRAWER_FRONT_GAP_MM.to_f,
                                     top_gap:    C::DOOR_GAP_TOP_MM.to_f,
                                     bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                                     reveal:     C::DRAWER_REVEAL_BETWEEN_MM.to_f)
          fronts.each { |f| rect(v, px + f[:x], z + f[:z], f[:w], f[:h], 'FRONTS') }
        end
      end

      # ── 측면도 (우측면) ─────────────────────────────────────────────────
      # X = 깊이 (0 = 앞면), Y = 높이
      def side_view(spec, g)
        depth_total = g[:max_d] + g[:prot]
        v = new_view('side', '측면도  SIDE', depth_total, g[:total_h])
        x0  = g[:prot]   # 카케이스 앞면 위치 (도어 돌출량만큼 밀림)
        cap = g[:total_h] - g[:ep_top_t]   # 상부 EP 아랫면

        # 카케이스 외곽
        rect(v, x0, g[:base_h], g[:max_d], cap - g[:base_h], 'OUTLINE')

        # 상부 EP 밴드 (도어 전면 커버 포함 전체 깊이)
        rect(v, 0, cap, depth_total, g[:ep_top_t], 'OUTLINE') if g[:ep_top_t] > 0

        # 받침
        if g[:base_h] > 0
          kick_x = x0 + C::TOE_KICK_SETBACK_MM
          rect(v, kick_x, 0, C::TOE_KICK_BOARD_THICK_MM, g[:base_h], 'OUTLINE')
        end

        # 상판
        if g[:top_t] > 0
          line(v, x0, cap - g[:top_t], x0 + g[:max_d], cap - g[:top_t], 'OUTLINE')
        end

        # 뒷판 (은선): 뒷면에서 recess 후퇴
        first = (spec['modules'] || []).find { |m| %w[shelf_module drawer_module].include?(m['kind']) }
        if first && first.fetch('has_back', true)
          bkt    = first['back_thickness'].to_f
          back_x = x0 + g[:max_d] - C::BACK_RECESS_MM - bkt
          line(v, back_x, g[:base_h], back_x, cap - g[:top_t], 'HIDDEN')
          line(v, back_x + bkt, g[:base_h], back_x + bkt, cap - g[:top_t], 'HIDDEN')
        end

        # 도어/전판 (돌출부 실선) + 모듈 경계/선반 (은선)
        each_module_frame(spec, g) do |m, _mx, mz, _mw, mh|
          z = g[:base_h] + mz
          # 모듈 경계선
          line(v, x0, z, x0 + g[:max_d], z, 'HIDDEN') if mz > 0
          t = front_thickness_of(m)
          if t > 0
            rect(v, x0 - t - C::DOOR_FRONT_OFFSET_MM, z + C::DOOR_GAP_BOTTOM_MM,
                 t, mh - C::DOOR_GAP_TOP_MM - C::DOOR_GAP_BOTTOM_MM, 'FRONTS')
          end
          bt = (m['body_thickness'] || 18).to_f
          (m['shelves'] || []).each do |s|
            sz = z + (s['height_from_bottom'] || 0).to_f
            line(v, x0 + bt, sz, x0 + g[:max_d] - C::BACK_RECESS_MM, sz, 'HIDDEN')
          end
        end

        # 치수: 깊이(하단) — 카케이스 깊이와 총 깊이(도어 포함)
        dim(v, x0, 0, x0 + g[:max_d], 0, -dim_off(g), fmt(g[:max_d]), :h)
        if g[:prot] > 0
          dim(v, 0, g[:total_h], depth_total, g[:total_h], dim_off(g) * 0.6,
              "#{fmt(depth_total)} (도어 포함)", :h)
        end
        dim(v, depth_total, 0, depth_total, g[:total_h], dim_off(g), fmt(g[:total_h]), :v)
        v
      end

      # 모듈 전면(도어/전판) 두께 — 측면도 돌출 표현용
      def front_thickness_of(m)
        case m['kind']
        when 'drawer_module'
          (m['drawer_thickness'] || 18).to_f
        when 'shelf_module'
          has_door = (m['door_config'] || 'none') != 'none' && m['door_mount'] != 'inset'
          has_cell = !(m['cell_drawers'] || []).empty?
          (has_door || has_cell) ? (m['door_thickness'] || 18).to_f : 0.0
        else
          0.0
        end
      end

      # ── 평면도 ───────────────────────────────────────────────────────────
      # X = 폭, Y = 깊이 (0 = 앞면 → 도면상 아래가 앞)
      def top_view(spec, g)
        depth_total = g[:max_d] + g[:prot]
        v = new_view('top', '평면도  TOP', g[:total_w], depth_total)
        y0    = g[:prot]
        x_car = g[:ep_l] ? g[:ep_t] : 0.0
        has_gap = g[:run] && (spec['modules'] || []).any? { |m| m['kind'] == 'bed_gap' }

        # 카케이스 외곽 (bed_gap 있으면 침대 공간 제외 구간별)
        if has_gap
          run_segments(spec['modules']).each do |seg_x, seg_w|
            rect(v, x_car + seg_x, y0, seg_w, g[:max_d], 'OUTLINE')
          end
        else
          rect(v, x_car, y0, g[:carcase_w], g[:max_d], 'OUTLINE')
        end

        # EP (도어 전면까지 연장)
        rect(v, 0, 0, g[:ep_t], depth_total, 'OUTLINE') if g[:ep_l]
        rect(v, g[:total_w] - g[:ep_t], 0, g[:ep_t], depth_total, 'OUTLINE') if g[:ep_r]

        # 상부 EP: 평면도에서 전체 외곽을 덮는 덮개
        rect(v, 0, 0, g[:total_w], depth_total, 'OUTLINE') if g[:ep_top_t] > 0

        # 도어/전판 라인 (실선)
        each_module_frame(spec, g) do |m, mx, _mz, mw, _mh|
          t = front_thickness_of(m)
          next unless t > 0
          rect(v, x_car + mx, y0 - t - C::DOOR_FRONT_OFFSET_MM, mw, t, 'FRONTS')
        end

        # run 모드: 섹션 경계 (은선) / stack: 측판 (은선)
        if g[:run]
          x = x_car
          mods_arr = spec['modules'] || []
          mods_arr.each_with_index do |m, i|
            x += m['width'].to_f
            next if i >= mods_arr.size - 1
            # bed_gap 양옆 경계는 구간 외곽선이 이미 그림 — 은선 생략
            next if m['kind'] == 'bed_gap' || mods_arr[i + 1]['kind'] == 'bed_gap'
            line(v, x, y0, x, y0 + g[:max_d], 'HIDDEN')
          end
        else
          first = (spec['modules'] || []).find { |m| %w[shelf_module drawer_module].include?(m['kind']) }
          bt = first ? first['body_thickness'].to_f : 18.0
          line(v, x_car + bt, y0, x_car + bt, y0 + g[:max_d], 'HIDDEN')
          line(v, x_car + g[:carcase_w] - bt, y0, x_car + g[:carcase_w] - bt, y0 + g[:max_d], 'HIDDEN')
        end

        # 치수: 폭(하단=앞면 쪽), 깊이(우측)
        dim(v, 0, 0, g[:total_w], 0, -dim_off(g), fmt(g[:total_w]), :h)
        dim(v, g[:total_w], y0, g[:total_w], y0 + g[:max_d], dim_off(g), fmt(g[:max_d]), :v)
        v
      end

      # 런 모드: bed_gap 제외 연속 구간 — Fitting.run_segments (단일 소스) 위임.
      def run_segments(modules)
        FIT.run_segments(modules)
      end

      # ── 뷰/프리미티브 헬퍼 ──────────────────────────────────────────────
      def new_view(name, label, w, h)
        { name: name, label: label, width: w.to_f, height: h.to_f,
          lines: [], rects: [], dims: [], texts: [] }
      end

      def line(v, x1, y1, x2, y2, layer)
        v[:lines] << { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f, layer: layer }
      end

      def rect(v, x, y, w, h, layer)
        v[:rects] << { x: x.to_f, y: y.to_f, w: w.to_f, h: h.to_f, layer: layer }
      end

      def dim(v, x1, y1, x2, y2, offset, text, dir)
        v[:dims] << { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f,
                      offset: offset.to_f, text: text.to_s, dir: dir }
      end

      def cell_edges_for(m, inner_w)
        FIT.cell_ranges(m['vertical_dividers'], inner_w)
      end

      # 치수선 이격량 — 가구 크기에 비례 (도면 가독성)
      def dim_off(g)
        [[g[:total_h], g[:total_w]].max * 0.06, 80.0].max.round(0)
      end

      def fmt(val)
        v = val.to_f.round(1)
        v == v.to_i ? v.to_i.to_s : v.to_s
      end
    end
  end
end
