# Pure-Ruby cut list generator — no SketchUp API required.
# Input : normalized spec hash (all dimensions in mm Float, from Schema.normalize).
# Output: Array of panel Hashes, CSV string, or both.
#
# 설계 원칙: 모든 도어/전판/서랍통 치수는 Kabinet::Core::Fitting 공식을 사용한다.
# 3D 지오메트리도 같은 공식을 쓰므로 도면과 재단 목록이 항상 일치한다.
#
# Each row hash keys:
#   :no, :part_name, :length_mm(가로), :width_mm(세로), :thickness_mm,
#   :qty, :material, :grain_dir, :edge, :note
#
# 주의: 가로/세로는 제작 방향 그대로 기록한다 (자동 스왑 없음 — 결방향 보존).
module Kabinet
  module Core
    module CutList
      module_function

      C   = Kabinet::Constants
      FIT = Kabinet::Core::Fitting

      # ── Public API ──────────────────────────────────────────────────────

      # 부재 + 하드웨어 + 경고를 한 번에 생성.
      def generate_full(spec)
        {
          rows:     generate(spec),
          hardware: Kabinet::Core::Hardware.generate(spec),
          warnings: Kabinet::Core::Validation.warnings(spec)
        }
      end

      # Generate cut list rows from a normalized spec hash.
      def generate(spec)
        rows     = []
        run_mode = spec['run_mode'] ? true : false
        ep_left  = spec.dig('ep', 'left')  ? true : false
        ep_right = spec.dig('ep', 'right') ? true : false
        ep_t     = (spec.dig('ep', 'thickness') || 18).to_f
        ep_mat   = spec.dig('ep', 'material') || '합판'

        max_d   = spec['max_depth'].to_f
        base_h  = (spec['base_height'] || 0).to_f
        top_t_v = spec.dig('top_panel', 'thickness')
        top_t   = top_t_v ? top_t_v.to_f : 0.0

        # ── 카케이스 폭/높이: 지오메트리(Assembly)와 동일한 계산 ─────────
        if run_mode
          carcase_w = spec['modules'].sum { |m| m['width'].to_f }
          content_h = spec['run_height'].to_f
        else
          carcase_w = spec['width'].to_f -
                      (ep_left ? ep_t : 0.0) - (ep_right ? ep_t : 0.0)
          content_h = spec['modules'].sum { |m| m['height'].to_f }
        end
        total_h = base_h + content_h + top_t

        # ── 모듈별 부재 ─────────────────────────────────────────────────
        spec['modules'].each_with_index do |m, idx|
          is_bed = false
          if m['kind'] == 'bed_gap'
            next unless m['storage']
            # 수납침대: 서랍 모듈로 변환 — run_height 대신 플랫폼 자체 치수
            is_bed = true
            m = m.merge('kind' => 'drawer_module',
                        'height' => m['platform_height'], 'depth' => m['bed_depth'])
          end
          prefix = is_bed ? "M#{idx + 1}(침대)" : "M#{idx + 1}"

          if m['kind'] == 'desk_module'
            # 런 모드: Assembly#do_run이 모든 모듈 높이를 run_height로
            # 덮어쓰고 3D를 만든다(m.merge('height' => run_h)). 여기서도
            # 같은 덮어쓰기를 해야 다리/가림판/하부유닛 치수가 실물과 일치한다.
            m_desk = run_mode ? m.merge('height' => spec['run_height']) : m
            rows.concat(desk_rows(m_desk, prefix))
            next
          end

          # 지오메트리와 동일: stack 모드는 폭 강제, run 모드는 높이 강제
          # (수납침대는 run_height 무시 — 플랫폼 자체 높이)
          mw = run_mode ? m['width'].to_f : carcase_w
          mh = is_bed ? m['height'].to_f : (run_mode ? spec['run_height'].to_f : m['height'].to_f)
          md = (m['depth'] || max_d).to_f
          bt  = m['body_thickness'].to_f
          bkt = m['back_thickness'].to_f
          mat     = m['material'] || 'LPM'
          mat_drw = m['door_material'] || mat

          suppress_l = m['suppress_left_side']  ? true : false
          suppress_r = m['suppress_right_side'] ? true : false
          n_sides    = 2 - (suppress_l ? 1 : 0) - (suppress_r ? 1 : 0)
          inner_w    = mw - (suppress_l ? 0 : bt) - (suppress_r ? 0 : bt)
          # stack 적층 시 아래 모듈 상판을 하판으로 공유 (지오메트리와 동일)
          shared_bottom = !run_mode && idx > 0

          # ── 몸통 (carcase) ───────────────────────────────────────────
          if n_sides > 0
            rows << mkrow("#{prefix}-측판", md, mh, bt, n_sides, mat, '세로결',
                          edge: '앞면', note: '좌우 측판')
          end
          unless shared_bottom
            rows << mkrow("#{prefix}-하판", inner_w, md, bt, 1, mat, '가로결',
                          edge: '앞면', note: '하판')
          end
          rows << mkrow("#{prefix}-상판", inner_w, md, bt, 1, mat, '가로결',
                        edge: '앞면', note: shared_bottom ? '상판(아래 모듈과 공유)' : '상판')
          if m.fetch('has_back', true)
            rows << mkrow("#{prefix}-뒷판", inner_w, mh - 2.0 * bt, bkt, 1, '합판', '세로결',
                          edge: '-', note: "끼움식(전면 #{C::BACK_RECESS_MM}mm 후퇴)")
          end

          case m['kind']
          when 'shelf_module'
            rows.concat(door_rows(m, prefix, mw, mh, bt, mat_drw))
            rows.concat(shelf_rows(m, prefix, inner_w, md, bkt, mat))
            rows.concat(divider_rows(m, prefix, md, mh, bt, bkt, mat))
            rows.concat(cell_shelf_rows(m, prefix, inner_w, md, bkt, mat))
            rows.concat(cell_drawer_rows(m, prefix, inner_w, md, mh, bt, bkt, mat_drw))
          when 'drawer_module'
            rows.concat(drawer_rows(m, prefix, mw, mh, md, bt, bkt, mat_drw))
          end
        end

        # ── 최상단 상판 (지오메트리: EP 사이 카케이스 폭) ─────────────────
        # 런 모드에서 bed_gap이 있으면 침대 공간 제외 구간별로 분할 (지오메트리 동일)
        if top_t > 0
          top_mat  = spec.dig('top_panel', 'material') || 'LPM'
          segments = run_mode ? run_segments(spec['modules']) : [[0.0, carcase_w]]
          segments.each_with_index do |(_x, w), i|
            label = segments.size > 1 ? "상판-#{i + 1}" : '상판'
            rows << mkrow(label, w, max_d, top_t, 1, top_mat, '가로결',
                          edge: '앞면', note: '최상단 상판')
          end
        end

        # ── EP 측면 마감판 — 도어 전면까지 커버 ──────────────────────────
        if ep_left || ep_right
          cover = spec['ep'].fetch('cover_fronts', true) ? true : false
          prot  = cover ? FIT.front_protrusion_mm(spec['modules']) : 0.0
          ep_d  = max_d + prot
          ep_h  = spec['ep_top_flush'] ? (total_h - top_t) : total_h
          note  = prot > 0 ? "도어 전면 커버 (+#{prot.round(1)}mm)" : '측면 마감판'
          rows << mkrow('EP-좌', ep_d, ep_h, ep_t, 1, ep_mat, '세로결', edge: '앞면', note: note) if ep_left
          rows << mkrow('EP-우', ep_d, ep_h, ep_t, 1, ep_mat, '세로결', edge: '앞면', note: note) if ep_right
        end

        # ── 상부 EP — 가구 최상단 덮개 (전체 폭, 측면 EP 위에 얹힘) ───────
        if spec.dig('ep', 'top')
          cover = spec['ep'].fetch('cover_fronts', true) ? true : false
          prot  = cover ? FIT.front_protrusion_mm(spec['modules']) : 0.0
          ep_w  = (ep_left ? ep_t : 0.0) + carcase_w + (ep_right ? ep_t : 0.0)
          rows << mkrow('EP-상', ep_w, max_d + prot, ep_t, 1, ep_mat, '가로결',
                        edge: '앞면', note: '상부 마감판 (측면 EP 위에 얹힘)')
        end

        # ── 걸레받이 (런 모드: bed_gap 제외 구간별) ──────────────────────
        if base_h > 0 && spec.fetch('has_kickboard', true)
          segments =
            if run_mode
              run_segments(spec['modules'])
            else
              [[0.0, (ep_left || ep_right) ? carcase_w : spec['width'].to_f]]
            end
          segments.each_with_index do |(_x, w), i|
            label = segments.size > 1 ? "걸레받이-#{i + 1}" : '걸레받이'
            rows << mkrow(label, w, base_h, C::TOE_KICK_BOARD_THICK_MM, 1,
                          spec['material'] || 'LPM', '가로결', edge: '상면',
                          note: "전면 #{C::TOE_KICK_SETBACK_MM}mm 후퇴")
          end
        end

        # 번호 부여
        rows.each_with_index { |r, i| r[:no] = i + 1 }
        rows
      end

      # Convert rows to a CSV string (UTF-8 with BOM for Excel compatibility).
      def to_csv(rows)
        header = %w[번호 부재명 가로mm 세로mm 두께mm 수량 소재 결방향 엣지 비고]
        lines  = ["\xEF\xBB\xBF" + header.join(',')]   # BOM + header
        rows.each do |r|
          cells = [
            r[:no],
            csv_escape(r[:part_name]),
            r[:length_mm].round(1),
            r[:width_mm].round(1),
            r[:thickness_mm].round(1),
            r[:qty],
            csv_escape(r[:material]),
            csv_escape(r[:grain_dir]),
            csv_escape(r[:edge] || '-'),
            csv_escape(r[:note])
          ]
          lines << cells.join(',')
        end
        lines.join("\r\n")
      end

      # 부재 + 하드웨어 + 경고를 하나의 CSV로.
      def full_csv(result)
        out = [to_csv(result[:rows])]

        hw = result[:hardware] || []
        unless hw.empty?
          out << ''
          out << '하드웨어 목록'
          out << %w[품명 규격 수량 단위 비고].join(',')
          hw.each do |h|
            out << [csv_escape(h[:name]), csv_escape(h[:spec]), h[:qty],
                    csv_escape(h[:unit]), csv_escape(h[:note])].join(',')
          end
        end

        warns = result[:warnings] || []
        unless warns.empty?
          out << ''
          out << '경고'
          warns.each { |w| out << csv_escape("⚠ #{w}") }
        end
        out.join("\r\n")
      end

      # ── Private helpers ─────────────────────────────────────────────────

      # 도어 — Fitting 공식 사용 (3D와 동일)
      def door_rows(m, prefix, mw, mh, bt, mat_drw)
        rows = []
        dc = m['door_config'] || 'none'
        return rows if dc == 'none'

        dt        = (m['door_thickness'] || 18).to_f
        door_type = m['door_type'] || 'swing'
        mount     = m['door_mount'] || 'overlay'
        side_gap  = (m['door_side_gap_mm'] || C::DOOR_GAP_OUTSIDE_MM).to_f

        doors =
          case door_type
          when 'sliding'
            base_w = mount == 'inset' ? mw - 2.0 * bt : mw
            base_h = mount == 'inset' ? mh - 2.0 * bt : mh
            FIT.sliding_doors(base_w, base_h, dc,
                              overlap:    C::SLIDING_DOOR_OVERLAP_MM.to_f,
                              top_gap:    C::SLIDING_DOOR_TOP_GAP_MM.to_f,
                              bottom_gap: C::SLIDING_DOOR_BOTTOM_GAP_MM.to_f)
          when 'folding'
            # 인셋: 3D(shelf_module.rb)가 내부 개구(width-2bt)와 INSET_DOOR_GAP_MM을
            # 쓰므로 여기도 동일하게 전환해야 함 (sliding/lift_up/swing은 이미 처리됨).
            if mount == 'inset'
              FIT.folding_doors(mw - 2.0 * bt, mh - 2.0 * bt, dc,
                                side_gap:   C::INSET_DOOR_GAP_MM.to_f,
                                top_gap:    C::INSET_DOOR_GAP_MM.to_f,
                                bottom_gap: C::INSET_DOOR_GAP_MM.to_f,
                                center_gap: C::DOOR_REVEAL_BETWEEN_MM.to_f)
            else
              FIT.folding_doors(mw, mh, dc,
                                side_gap:   side_gap,
                                top_gap:    C::DOOR_GAP_TOP_MM.to_f,
                                bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                                center_gap: C::DOOR_REVEAL_BETWEEN_MM.to_f)
            end
          when 'lift_up'
            base_w = mount == 'inset' ? mw - 2.0 * bt : mw
            base_h = mount == 'inset' ? mh - 2.0 * bt : mh
            FIT.lift_up_door(base_w, base_h, gap: C::LIFT_UP_DOOR_GAP_MM.to_f)
          else # swing
            if mount == 'inset'
              FIT.inset_doors(mw - 2.0 * bt, mh - 2.0 * bt, dc,
                              gap:        C::INSET_DOOR_GAP_MM.to_f,
                              center_gap: C::DOOR_REVEAL_BETWEEN_MM.to_f)
            else
              FIT.swing_doors(mw, mh, dc,
                              side_gap:   side_gap,
                              top_gap:    C::DOOR_GAP_TOP_MM.to_f,
                              bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                              center_gap: C::DOOR_REVEAL_BETWEEN_MM.to_f)
            end
          end

        # 동일 치수 도어는 수량으로 합침
        doors.group_by { |d| [d[:w].round(1), d[:h].round(1)] }.each do |(w, h), grp|
          note = "#{door_type}/#{mount}#{grp.size > 1 ? " ×#{grp.size}" : ''}"
          rows << mkrow("#{prefix}-도어", w, h, dt, grp.size, mat_drw, '세로결',
                        edge: '4면', note: note)
        end
        rows
      end

      def shelf_rows(m, prefix, inner_w, md, bkt, mat)
        rows = []
        (m['shelves'] || []).each_with_index do |s, si|
          st    = (s['thickness']   || 18).to_f
          inset = (s['depth_inset'] || 20).to_f
          sw    = inner_w - C::SHELF_SIDE_PLAY_MM   # 끼임 방지 여유 (3D와 동일)
          sd    = md - inset - bkt - C::BACK_RECESS_MM
          rows << mkrow("#{prefix}-선반#{si + 1}", sw, sd, st, 1, mat, '가로결',
                        edge: '앞면', note: '가동선반')
        end
        rows
      end

      def divider_rows(m, prefix, md, mh, bt, bkt, mat)
        rows = []
        (m['vertical_dividers'] || []).each_with_index do |d, di|
          dt_   = (d['thickness'] || bt).to_f
          div_d = md - bkt - C::BACK_RECESS_MM
          div_h = mh - 2.0 * bt
          rows << mkrow("#{prefix}-세로분할판#{di + 1}", div_d, div_h, dt_, 1, mat, '세로결',
                        edge: '앞면', note: '세로 분할판')
        end
        rows
      end

      def cell_shelf_rows(m, prefix, inner_w, md, bkt, mat)
        rows  = []
        cells = cell_widths(m, inner_w)
        (m['cell_shelves'] || []).each do |cs|
          cw = cells[(cs['cell'] || 0).to_i]
          next unless cw && cw > 0
          st    = (cs['thickness']   || 18).to_f
          inset = (cs['depth_inset'] || 0).to_f
          sw    = cw - C::SHELF_SIDE_PLAY_MM
          sd    = md - bkt - C::BACK_RECESS_MM - inset
          rows << mkrow("#{prefix}-셀선반(칸#{(cs['cell'] || 0) + 1})", sw, sd, st, 1, mat,
                        '가로결', edge: '앞면', note: '셀 가동선반')
        end
        rows
      end

      def cell_drawer_rows(m, prefix, inner_w, md, mh, bt, bkt, mat_drw)
        rows  = []
        cells = cell_widths(m, inner_w)
        inner_depth = md - bkt - C::BACK_RECESS_MM
        int_h       = mh - 2.0 * bt

        (m['cell_drawers'] || []).each do |cd|
          cell_idx = (cd['cell'] || 0).to_i
          cw       = cells[cell_idx]
          next unless cw && cw > 0
          dc  = (cd['count'] || 2).to_i
          dth = (cd['thickness'] || 18).to_f

          fronts = FIT.drawer_fronts(cw, int_h, dc,
                                     side_gap:   C::DOOR_GAP_OUTSIDE_MM.to_f,
                                     top_gap:    C::DOOR_GAP_TOP_MM.to_f,
                                     bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                                     reveal:     C::DRAWER_REVEAL_BETWEEN_MM.to_f)
          f = fronts.first
          rows << mkrow("#{prefix}-셀서랍전판(칸#{cell_idx + 1})", f[:w], f[:h], dth, dc,
                        mat_drw, '세로결', edge: '4면', note: "서랍 전판 ×#{dc}")

          comp_h = (int_h - C::DOOR_GAP_TOP_MM - C::DOOR_GAP_BOTTOM_MM -
                    C::DRAWER_REVEAL_BETWEEN_MM * (dc - 1)) / dc
          box = FIT.drawer_box_mm(open_w_mm: cw, comp_h_mm: comp_h,
                                  inner_depth_mm: inner_depth,
                                  type: cd['type'] || 'undermount')
          rows.concat(box_rows("#{prefix}-셀서랍(칸#{cell_idx + 1})", box, dc, walls: 3))
        end
        rows
      end

      # 서랍 모듈 — 전판은 풀 오버레이 (3D와 동일)
      def drawer_rows(m, prefix, mw, mh, md, bt, bkt, mat_drw)
        rows = []
        dc   = (m['drawer_count'] || 1).to_i
        df_t = (m['drawer_thickness'] || 18).to_f

        fronts = FIT.drawer_fronts(mw, mh, dc,
                                   side_gap:   C::DRAWER_FRONT_GAP_MM.to_f,
                                   top_gap:    C::DOOR_GAP_TOP_MM.to_f,
                                   bottom_gap: C::DOOR_GAP_BOTTOM_MM.to_f,
                                   reveal:     C::DRAWER_REVEAL_BETWEEN_MM.to_f)
        f = fronts.first
        rows << mkrow("#{prefix}-전판", f[:w], f[:h], df_t, dc, mat_drw, '세로결',
                      edge: '4면', note: "서랍 전판 ×#{dc} (오버레이)")

        open_w      = mw - 2.0 * bt
        open_h      = mh - 2.0 * bt
        inner_depth = md - bkt - C::BACK_RECESS_MM
        # 박스 깊이 상한 (수납침대 — 지오메트리와 동일)
        inner_depth = [inner_depth, m['box_depth_mm'].to_f].min if m['box_depth_mm']
        comp_h      = (open_h - C::DRAWER_REVEAL_BETWEEN_MM * (dc - 1)) / dc
        box = FIT.drawer_box_mm(open_w_mm: open_w, comp_h_mm: comp_h,
                                inner_depth_mm: inner_depth,
                                type: m['drawer_type'] || 'undermount')
        rows.concat(box_rows("#{prefix}-서랍", box, dc, walls: 4))
        rows
      end

      # 서랍통 부재. walls: 4 = 옆판2+앞막이+뒷판, 3 = 옆판2+뒷판
      def box_rows(name, box, qty, walls: 4)
        bw   = C::DRAWER_BOX_WALL_MM.to_f
        bb   = C::DRAWER_BOX_BOTTOM_MM.to_f
        note = box[:slide_len] ? "레일 L#{box[:slide_len].round}" : '레일 규격 미달 — 깊이 확인'
        rows = []
        rows << mkrow("#{name}-옆판", box[:d], box[:h], bw, qty * 2, '합판', '가로결',
                      edge: '상면', note: "#{note} ×#{qty}")
        n_cross = walls - 2
        rows << mkrow("#{name}-앞뒤막이", box[:w] - 2.0 * bw, box[:h], bw, qty * n_cross,
                      '합판', '가로결', edge: '상면', note: "서랍통 막이 ×#{qty * n_cross}")
        rows << mkrow("#{name}-바닥", box[:w], box[:d], bb, qty, '합판', '가로결',
                      edge: '-', note: "서랍통 바닥 ×#{qty}")
        rows
      end

      # 책상 모듈 부재
      def desk_rows(m, prefix)
        rows  = []
        mw    = m['width'].to_f
        md    = m['depth'].to_f
        mh    = m['height'].to_f
        top_t = (m['top_thickness'] || 25).to_f
        leg_h = mh - top_t
        mat   = m['material'] || 'LPM'

        rows << mkrow("#{prefix}-책상상판", mw, md, top_t, 1, mat, '가로결',
                      edge: '4면', note: '책상 상판')

        ped = m['pedestal']
        ped_on = ped.is_a?(Hash) && ped['enabled'] != false
        if ped_on
          pw = (ped['width'] || 450).to_f
          pd = (ped['depth'] || md).to_f
          pdc = (ped['drawer_count'] || 3).to_i
          pm = { 'width' => pw, 'height' => leg_h, 'depth' => pd,
                 'body_thickness' => 18.0, 'back_thickness' => 9.0,
                 'drawer_count' => pdc, 'drawer_thickness' => 18.0,
                 'drawer_type' => ped['drawer_type'] || 'undermount',
                 'door_material' => mat }
          rows << mkrow("#{prefix}-페데스탈측판", pd, leg_h, 18, 2, mat, '세로결', edge: '앞면')
          rows << mkrow("#{prefix}-페데스탈상하판", pw - 36, pd, 18, 2, mat, '가로결', edge: '앞면')
          rows << mkrow("#{prefix}-페데스탈뒷판", pw - 36, leg_h - 36, 9, 1, '합판', '세로결', edge: '-')
          rows.concat(drawer_rows(pm, "#{prefix}-페데스탈", pw, leg_h, pd, 18.0, 9.0, mat))
        end

        # 다리 (페데스탈 반대편 + 나머지 코너)
        n_legs = ped_on ? 2 : 4
        lw = (m['leg_w'] || 60).to_f
        ld = (m['leg_d'] || 60).to_f
        rows << mkrow("#{prefix}-다리", lw, leg_h, ld, n_legs,
                      m['leg_type'] == 'round' ? '원형각재' : '집성각재', '세로결',
                      edge: '-', note: "#{lw.round}×#{ld.round} 각재")

        if m['has_modesty_panel']
          mp_h = (leg_h * 0.6).round(1)
          rows << mkrow("#{prefix}-가림판", mw, mp_h, 18, 1, mat, '가로결', edge: '하면')
        end

        uu = m['under_unit']
        if uu.is_a?(Hash) && uu['enabled'] != false
          uw  = (uu['width'] || 400).to_f
          uh  = (uu['height'] || 130).to_f
          ud  = md - 80.0
          udc = (uu['drawer_count'] || 1).to_i
          um  = { 'body_thickness' => 18.0, 'back_thickness' => 9.0,
                  'drawer_count' => udc, 'drawer_thickness' => 18.0,
                  'drawer_type' => uu['drawer_type'] || 'undermount',
                  'door_material' => mat }
          rows << mkrow("#{prefix}-하부유닛측판", ud, uh, 18, 2, mat, '세로결', edge: '앞면')
          rows << mkrow("#{prefix}-하부유닛상하판", uw - 36, ud, 18, 2, mat, '가로결', edge: '앞면')
          rows.concat(drawer_rows(um, "#{prefix}-하부유닛", uw, uh, ud, 18.0, 9.0, mat))
        end
        rows
      end

      # 런 모드: bed_gap 제외 연속 구간 — Fitting.run_segments (단일 소스) 위임.
      def run_segments(modules)
        FIT.run_segments(modules)
      end

      # 세로 분할판 기준 각 칸의 내폭 — Fitting.cell_ranges (단일 소스) 위임.
      def cell_widths(m, inner_w)
        FIT.cell_ranges(m['vertical_dividers'], inner_w).map { |s, e| e - s }
      end

      def mkrow(name, l, w, t, qty, mat, grain = '무결', edge: '-', note: '')
        { no: nil, part_name: name,
          length_mm: l.to_f.round(1), width_mm: w.to_f.round(1),
          thickness_mm: t.to_f.round(1),
          qty: qty, material: mat.to_s, grain_dir: grain,
          edge: edge, note: note.to_s }
      end

      def csv_escape(str)
        s = str.to_s
        s.include?(',') ? "\"#{s.gsub('"', '""')}\"" : s
      end
    end
  end
end
