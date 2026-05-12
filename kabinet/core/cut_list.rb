# Pure-Ruby cut list generator — no SketchUp API required.
# Input : normalized spec hash (all dimensions in mm Float, from Schema.normalize).
# Output: Array of panel Hashes, CSV string, or both.
#
# Each row hash keys:
#   :no, :part_name, :length_mm, :width_mm, :thickness_mm,
#   :qty, :material, :grain_dir, :note
module Kabinet
  module Core
    module CutList
      module_function

      # Shorthand constants (all mm)
      GAP_TOP    = Kabinet::Constants::DOOR_GAP_TOP_MM.to_f
      GAP_BOTTOM = Kabinet::Constants::DOOR_GAP_BOTTOM_MM.to_f
      GAP_SIDE   = Kabinet::Constants::DOOR_GAP_OUTSIDE_MM.to_f
      GAP_CTR    = Kabinet::Constants::DOOR_REVEAL_BETWEEN_MM.to_f
      OVERLAY    = Kabinet::Constants::DOOR_OVERLAY_MM.to_f
      BACK_REC   = Kabinet::Constants::BACK_RECESS_MM.to_f

      # ── Public API ──────────────────────────────────────────────────────

      # Generate cut list rows from a normalized spec hash.
      def generate(spec)
        rows  = []
        ep_left  = spec.dig('ep', 'left')  ? true : false
        ep_right = spec.dig('ep', 'right') ? true : false
        ep_t     = (spec.dig('ep', 'thickness') || 18).to_f
        ep_mat   = spec.dig('ep', 'material')  || '합판'

        total_w  = spec['width'].to_f
        max_d    = spec['max_depth'].to_f
        mods_h   = spec['modules'].sum { |m| m['height'].to_f }
        top_t_v  = spec.dig('top_panel', 'thickness')
        top_t    = top_t_v ? top_t_v.to_f : 0.0
        base_h   = (spec['base_height'] || 0).to_f
        total_h  = base_h + mods_h + top_t

        spec['modules'].each_with_index do |m, idx|
          prefix = "M#{idx + 1}"
          mw = m['width'].to_f
          md = m['depth'].to_f
          mh = m['height'].to_f
          bt = m['body_thickness'].to_f
          bkt= m['back_thickness'].to_f
          mat     = m['material']  || 'LPM'
          mat_drw = m['door_material'] || mat

          inner_w = mw - 2.0 * bt

          # ── 몸통 (carcase) ─────────────────────────────────────────────
          rows << mkrow("#{prefix}-측판", md, mh, bt, 2, mat, '세로결', '좌우 측판')
          rows << mkrow("#{prefix}-하판",  inner_w, md, bt, 1, mat, '가로결', '하판')
          rows << mkrow("#{prefix}-상판",  inner_w, md, bt, 1, mat, '가로결', '상판')
          if m.fetch('has_back', true)
            rows << mkrow("#{prefix}-뒷판", inner_w, mh - 2.0 * bt, bkt, 1, '합판', '세로결', '뒷판')
          end

          case m['kind']
          when 'shelf_module'
            rows.concat(shelf_rows(m, prefix, inner_w, md, mh, bt, bkt, mat, mat_drw))

          when 'drawer_module'
            rows.concat(drawer_rows(m, prefix, inner_w, md, mh, bt, bkt, mat, mat_drw))
          end
        end

        # ── 상판 ────────────────────────────────────────────────────────
        if top_t > 0
          top_mat = spec.dig('top_panel', 'material') || 'LPM'
          rows << mkrow('상판', total_w, max_d, top_t, 1, top_mat, '가로결', '최상단 상판')
        end

        # ── EP 측면 마감판 ───────────────────────────────────────────────
        rows << mkrow('EP-좌', max_d, total_h, ep_t, 1, ep_mat, '세로결', '좌측 마감판') if ep_left
        rows << mkrow('EP-우', max_d, total_h, ep_t, 1, ep_mat, '세로결', '우측 마감판') if ep_right

        # 번호 부여
        rows.each_with_index { |r, i| r[:no] = i + 1 }
        rows
      end

      # Convert rows to a CSV string (UTF-8 with BOM for Excel compatibility).
      def to_csv(rows)
        header = %w[번호 부재명 가로mm 세로mm 두께mm 수량 소재 결방향 비고]
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
            csv_escape(r[:note])
          ]
          lines << cells.join(',')
        end
        lines.join("\r\n")
      end

      # ── Private helpers ─────────────────────────────────────────────────

      def shelf_rows(m, prefix, inner_w, _md, mh, _bt, bkt, mat, mat_drw)
        rows = []
        dc = m['door_config'] || 'none'
        dt = (m['door_thickness'] || 18).to_f
        door_type_note = m['door_type'] || 'swing'

        case dc
        when 'single'
          dh = mh - GAP_TOP - GAP_BOTTOM
          dw = inner_w + 2.0 * OVERLAY - 2.0 * GAP_SIDE
          rows << mkrow("#{prefix}-도어", dw, dh, dt, 1, mat_drw, '세로결', "단문(#{door_type_note})")
        when 'pair'
          dh = mh - GAP_TOP - GAP_BOTTOM
          dw = (inner_w + 2.0 * OVERLAY - 2.0 * GAP_SIDE - GAP_CTR) / 2.0
          rows << mkrow("#{prefix}-도어L", dw, dh, dt, 1, mat_drw, '세로결', "양개-좌(#{door_type_note})")
          rows << mkrow("#{prefix}-도어R", dw, dh, dt, 1, mat_drw, '세로결', "양개-우(#{door_type_note})")
        end

        (m['shelves'] || []).each_with_index do |s, si|
          st    = (s['thickness']     || 18).to_f
          inset = (s['depth_inset']   || 20).to_f
          mod_d = _md
          sd    = mod_d - inset - bkt - BACK_REC
          rows << mkrow("#{prefix}-선반#{si + 1}", inner_w, sd, st, 1, mat, '가로결', '가동선반')
        end
        rows
      end

      def drawer_rows(m, prefix, inner_w, md, mh, bt, bkt, mat, mat_drw)
        rows  = []
        dc    = (m['drawer_count'] || 1).to_i
        df_t  = (m['drawer_thickness'] || 18).to_f
        slide = m['drawer_type'] || 'undermount'

        # 전판 (drawer front)
        open_h    = mh - 2.0 * bt
        gap_top   = Kabinet::Constants::DRAWER_FRONT_GAP_MM.to_f
        gap_bet   = Kabinet::Constants::DRAWER_REVEAL_BETWEEN_MM.to_f
        front_h   = ((open_h - gap_top * 2.0 - gap_bet * (dc - 1)) / dc).round(1)
        front_w   = (inner_w - 2.0 * GAP_SIDE).round(1)
        rows << mkrow("#{prefix}-전판", front_w, front_h, df_t, dc, mat_drw, '세로결', "서랍 전판 ×#{dc}")

        # 서랍통
        side_cl = (slide == 'undermount' ?
                   Kabinet::Constants::UNDERMOUNT_SIDE_CLEARANCE_MM :
                   Kabinet::Constants::SIDEMOUNT_SIDE_CLEARANCE_MM).to_f
        box_w   = (inner_w - 2.0 * side_cl).round(1)
        box_d   = (md - bkt - BACK_REC - 30.0).round(1)   # 30mm 앞쪽 여유
        box_h   = (front_h - Kabinet::Constants::UNDERMOUNT_HEIGHT_OFFSET_MM).round(1)
        bw      = Kabinet::Constants::DRAWER_BOX_WALL_MM.to_f
        bb      = Kabinet::Constants::DRAWER_BOX_BOTTOM_MM.to_f
        rows << mkrow("#{prefix}-서랍옆판", box_d, box_h, bw, dc * 2, '합판', '가로결', "서랍통 좌우 ×#{dc}")
        rows << mkrow("#{prefix}-서랍뒤판", box_w - 2.0 * bw, box_h, bw, dc, '합판', '가로결', "서랍통 뒷판 ×#{dc}")
        rows << mkrow("#{prefix}-서랍바닥", box_w - 2.0 * bw, box_d - bw, bb, dc, '합판', '가로결', "서랍통 바닥 ×#{dc}")
        rows
      end

      def mkrow(name, l, w, t, qty, mat, grain, note = '')
        l = l.to_f.round(1)
        w = w.to_f.round(1)
        l, w = w, l if w > l   # 가로 >= 세로 보장
        { no: nil, part_name: name,
          length_mm: l, width_mm: w, thickness_mm: t.to_f.round(1),
          qty: qty, material: mat.to_s, grain_dir: grain, note: note }
      end

      def csv_escape(str)
        s = str.to_s
        s.include?(',') ? "\"#{s.gsub('"', '""')}\"" : s
      end
    end
  end
end
