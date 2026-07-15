# 실무 검증(경고) — 순수 루비, SketchUp API 불필요.
# 치명 오류(ValidationError)가 아닌, 제작/시공 관점의 경고를 생성한다.
# 입력: Schema.normalize를 거친 spec 해시. 출력: 경고 문자열 배열.
module Kabinet
  module Core
    module Validation
      module_function

      def warnings(spec)
        warns    = []
        run_mode = spec['run_mode'] ? true : false
        max_d    = spec['max_depth'].to_f

        # 스택 모드: 지오메트리가 모듈 폭을 카케이스 폭으로 강제하므로
        # 검증도 같은 폭 기준으로 계산 (프리셋 원본 폭으로 계산하면 수치가 어긋남)
        ep = spec['ep'] || {}
        stack_w = spec['width'].to_f -
                  (ep['left']  ? (ep['thickness'] || 18).to_f : 0) -
                  (ep['right'] ? (ep['thickness'] || 18).to_f : 0)

        # 런 모드 + bed_gap + 상판: 상판은 침대 공간에서 분할 생성됨을 안내
        if run_mode && spec['top_panel'] &&
           spec['modules'].any? { |m| m['kind'] == 'bed_gap' }
          warns << '상판이 침대 공간(bed_gap)에서 분할됩니다. 침대 위를 잇는 브릿지 상부장은 별도 박스로 계획하세요.'
        end

        spec['modules'].each_with_index do |m, idx|
          next if m['kind'] == 'v_gap'
          if m['kind'] == 'bed_gap'
            warns.concat(bed_storage_warnings(m, "모듈#{idx + 1}")) if m['storage']
            next
          end
          prefix = "모듈#{idx + 1}"
          mh = run_mode ? spec['run_height'].to_f : m['height'].to_f
          mw = run_mode ? m['width'].to_f : stack_w
          md = (m['depth'] || max_d).to_f

          if md > max_d
            warns << "#{prefix}: 깊이 #{md.round}가 전체 최대깊이 #{max_d.round}보다 큽니다."
          end

          case m['kind']
          when 'shelf_module'
            warns.concat(door_warnings(m, prefix, mw, mh))
            warns.concat(shelf_warnings(m, prefix, mw))
            warns.concat(drawer_depth_warning(m, prefix, md, (m['cell_drawers'] || []).any?))
            warns.concat(rod_warnings(m, prefix, mw))
            if (m['shelves'] || []).any? && (m['vertical_dividers'] || []).any?
              warns << "#{prefix}: 전폭 선반과 세로 분할판을 함께 쓰면 선반이 분할판을 관통합니다. 셀 선반(cell_shelves)을 사용하세요."
            end
          when 'drawer_module'
            warns.concat(drawer_depth_warning(m, prefix, md, true))
            open_w = mw - 2.0 * m['body_thickness'].to_f
            if open_w > Kabinet::Constants::DRAWER_MAX_OPEN_W_MM
              warns << "#{prefix}: 서랍 개구폭 #{open_w.round}mm — #{Kabinet::Constants::DRAWER_MAX_OPEN_W_MM}mm 초과. " \
                       '레일 하중/전판 휨 위험. 세로 분할 + 셀 서랍 구성을 권장합니다.'
            end
          end

          warns.concat(sheet_warnings(m, prefix, mw, mh, md))
        end
        warns
      end

      # ── 수납침대(서랍 플랫폼) ────────────────────────────────────────────
      def bed_storage_warnings(m, prefix)
        warns   = []
        inner_d = m['bed_depth'].to_f - m['back_thickness'].to_f - Kabinet::Constants::BACK_RECESS_MM
        inner_d = [inner_d, m['box_depth_mm'].to_f].min if m['box_depth_mm']
        slide   = Kabinet::Core::Fitting.slide_length_mm(inner_d)
        if slide.nil?
          warns << "#{prefix}(수납침대): 서랍 박스 깊이 #{inner_d.round}mm — 최소 슬라이드 규격(250mm)이 들어가지 않습니다."
        end
        open_w = m['width'].to_f - 2.0 * m['body_thickness'].to_f
        if open_w > Kabinet::Constants::DRAWER_MAX_OPEN_W_MM
          warns << "#{prefix}(수납침대): 서랍 개구폭 #{open_w.round}mm — #{Kabinet::Constants::DRAWER_MAX_OPEN_W_MM}mm 초과. " \
                   '레일 하중/전판 휨 위험. 폭을 줄이거나 침대 폭을 나눠 서랍 유닛을 분리하세요.'
        end
        if m['platform_height'].to_f < 150
          warns << "#{prefix}(수납침대): 플랫폼 높이 #{m['platform_height'].round}mm — 서랍 인출에 필요한 최소 높이(150mm) 미달입니다."
        end
        warns
      end

      # ── 행거봉 스팬 ──────────────────────────────────────────────────────
      def rod_warnings(m, prefix, mw)
        rods = (m['accessories'] || []).select { |a| a['kind'] == 'hanging_rod' }
        return [] if rods.empty?
        span = mw - 2.0 * m['body_thickness'].to_f
        if span > Kabinet::Constants::ROD_SPAN_WARN_MM
          ["#{prefix}: 행거봉 스팬 #{span.round}mm — #{Kabinet::Constants::ROD_SPAN_WARN_MM}mm 초과 시 " \
           '봉 처짐이 발생합니다. 중간 지지 브라켓 또는 칸 분할을 권장합니다.']
        else
          []
        end
      end

      # ── 도어 ─────────────────────────────────────────────────────────────

      def door_warnings(m, prefix, mw, mh)
        warns = []
        dc = m['door_config'] || 'none'
        return warns if dc == 'none'

        door_type = m['door_type'] || 'swing'
        gaps_w    = 2.0 * Kabinet::Constants::DOOR_GAP_OUTSIDE_MM
        door_w    = dc == 'pair' ?
                    (mw - gaps_w - Kabinet::Constants::DOOR_REVEAL_BETWEEN_MM) / 2.0 :
                    mw - gaps_w
        door_h    = mh - Kabinet::Constants::DOOR_GAP_TOP_MM - Kabinet::Constants::DOOR_GAP_BOTTOM_MM

        if door_type == 'swing' || door_type == 'folding'
          if door_w > Kabinet::Constants::SWING_DOOR_MAX_W_MM
            warns << "#{prefix}: 여닫이 도어 폭 #{door_w.round}mm — #{Kabinet::Constants::SWING_DOOR_MAX_W_MM}mm 초과. " \
                     '힌지 하중/처짐 위험. 양개(pair) 또는 분할을 권장합니다.'
          end
          if door_h > Kabinet::Constants::SWING_DOOR_MAX_H_MM
            warns << "#{prefix}: 도어 높이 #{door_h.round}mm — #{Kabinet::Constants::SWING_DOOR_MAX_H_MM}mm 초과. " \
                     '상하 분할 도어를 권장합니다.'
          end
        end

        if door_type == 'sliding' && mw < 900
          warns << "#{prefix}: 폭 #{mw.round}mm 미닫이 — 도어 1짝 유효 개구가 매우 좁아집니다. 여닫이를 검토하세요."
        end
        warns
      end

      # ── 선반 처짐 ────────────────────────────────────────────────────────
      # 세로 분할판이 있으면 각 셀 선반의 실제 칸 폭으로 스팬을 계산한다.
      # (이전 버그: 분할판이 하나라도 있으면 실제 칸 폭과 무관하게 경고를
      #  통째로 억제 — 가장자리에 치우친 분할판이 만드는 거대한 칸을 놓쳤음)
      def shelf_warnings(m, prefix, mw)
        bt      = m['body_thickness'].to_f
        inner_w = mw - 2.0 * bt
        full    = m['shelves'] || []
        cells   = m['cell_shelves'] || []
        return [] if full.empty? && cells.empty?

        cell_spans = Kabinet::Core::Fitting.cell_ranges(m['vertical_dividers'], inner_w)
                                            .map { |s, e| e - s }

        worst = 0.0
        full.each { |s| worst = inner_w if thin_shelf?(s) && inner_w > worst }
        cells.each do |s|
          span = cell_spans[(s['cell'] || 0).to_i]
          next unless span
          worst = span if thin_shelf?(s) && span > worst
        end

        if worst > Kabinet::Constants::SHELF_SPAN_WARN_MM
          ["#{prefix}: 선반 스팬 #{worst.round}mm (18T) — #{Kabinet::Constants::SHELF_SPAN_WARN_MM}mm 초과 시 " \
           '처짐이 발생합니다. 25T 선반 또는 세로 분할판(셀 분할)을 권장합니다.']
        else
          []
        end
      end

      def thin_shelf?(s)
        (s['thickness'] || 18).to_f < 25.0
      end

      # ── 서랍 깊이/레일 규격 ──────────────────────────────────────────────

      def drawer_depth_warning(m, prefix, md, has_drawers)
        return [] unless has_drawers
        inner_d = md - m['back_thickness'].to_f - Kabinet::Constants::BACK_RECESS_MM
        slide   = Kabinet::Core::Fitting.slide_length_mm(inner_d)
        if slide.nil?
          ["#{prefix}: 내부 깊이 #{inner_d.round}mm — 최소 슬라이드 규격(250mm)이 들어가지 않습니다."]
        else
          []
        end
      end

      # ── 원장(시트) 규격 초과 ─────────────────────────────────────────────

      def sheet_warnings(m, prefix, mw, mh, md)
        warns = []
        long  = [mw, mh, md].max
        short = [mh, md].min
        if long > Kabinet::Constants::SHEET_LENGTH_MM
          warns << "#{prefix}: 부재 최대 길이 #{long.round}mm — 원장(#{Kabinet::Constants::SHEET_LENGTH_MM}×" \
                   "#{Kabinet::Constants::SHEET_WIDTH_MM}) 초과. 이음(조인트) 설계가 필요합니다."
        elsif short > Kabinet::Constants::SHEET_WIDTH_MM && long > Kabinet::Constants::SHEET_WIDTH_MM &&
              [mw, mh, md].sort[1] > Kabinet::Constants::SHEET_WIDTH_MM
          warns << "#{prefix}: 부재 단변이 원장 폭 #{Kabinet::Constants::SHEET_WIDTH_MM}mm를 초과할 수 있습니다. 재단 배치를 확인하세요."
        end
        warns
      end
    end
  end
end
