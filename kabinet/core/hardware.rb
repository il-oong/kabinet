# 하드웨어(철물) 수량 산출 — 순수 루비, SketchUp API 불필요.
# 입력: Schema.normalize를 거친 spec 해시 (mm Float).
# 출력: [{ name:, spec:, qty:, unit:, note: }, ...]
#
# 실무 기준:
#   힌지    — 도어 높이별 수량표 (Constants::HINGE_COUNT_THRESHOLDS)
#   레일    — 서랍당 1세트(좌우), 공칭 길이는 Fitting.slide_length_mm 스냅값
#   선반핀  — 가동선반 1장당 4개
#   행거봉  — 봉 + 브라켓 2개
#   레벨러  — 하부 받침(걸레받이) 있을 때 600mm당 1개 + 1
module Kabinet
  module Core
    module Hardware
      module_function

      def generate(spec)
        rows     = []
        run_mode = spec['run_mode'] ? true : false

        spec['modules'].each_with_index do |m, idx|
          if m['kind'] == 'bed_gap'
            next unless m['storage']
            # 수납침대 → 서랍 모듈 하드웨어 (레일/손잡이)
            m = m.merge('kind' => 'drawer_module',
                        'height' => m['platform_height'], 'depth' => m['bed_depth'])
          end
          prefix = "M#{idx + 1}"
          mh     = run_mode ? spec['run_height'].to_f : m['height'].to_f

          case m['kind']
          when 'shelf_module'
            rows.concat(door_hardware(m, prefix, mh))
            rows.concat(shelf_pins(m, prefix))
            rows.concat(accessory_hardware(m, prefix))
            rows.concat(cell_drawer_hardware(m, prefix, mh))
          when 'drawer_module'
            rows.concat(drawer_slides(m, prefix, mh))
            rows.concat(handles(m, prefix, (m['drawer_count'] || 1).to_i))
          when 'desk_module'
            rows.concat(desk_hardware(m, prefix))
          end
        end

        if (spec['base_height'] || 0).to_f > 0
          # 런 모드: 걸레받이가 bed_gap 제외 구간별로 독립 생성되므로
          # (Fitting.run_segments) 레벨러도 구간마다 따로 세야 한다.
          # 구간을 합쳐서 하나로 계산하면 침대 공간 폭까지 포함되거나
          # 실제로는 분리된 받침대를 하나로 세어 과소/과다 산출된다.
          qty =
            if run_mode
              Kabinet::Core::Fitting.run_segments(spec['modules'])
                                     .sum { |_x, w| (w / 600.0).ceil + 1 }
            else
              (spec['width'].to_f / 600.0).ceil + 1
            end
          rows << row('조절 레벨러', "H#{spec['base_height'].to_f.round}", qty * 2, '개',
                      '하부 받침대 전/후 2열')
        end

        rows
      end

      # ── 내부 헬퍼 ────────────────────────────────────────────────────────

      def door_hardware(m, prefix, mh)
        rows = []
        dc   = m['door_config'] || 'none'
        return rows if dc == 'none'

        door_type = m['door_type'] || 'swing'
        gap_t     = Kabinet::Constants::DOOR_GAP_TOP_MM.to_f
        gap_b     = Kabinet::Constants::DOOR_GAP_BOTTOM_MM.to_f
        door_h    = mh - gap_t - gap_b
        n_doors   = dc == 'pair' ? 2 : 1

        case door_type
        when 'swing'
          per = Kabinet::Constants.hinge_count_for_height(door_h)
          rows << row("#{prefix}-힌지", '오버레이 Ø35', per * n_doors, '개',
                      "도어 #{n_doors}짝 × #{per}개")
        when 'folding'
          per = Kabinet::Constants.hinge_count_for_height(door_h)
          rows << row("#{prefix}-힌지", '오버레이 Ø35', per * n_doors, '개', '벽측 힌지')
          rows << row("#{prefix}-연동 힌지", '바이폴드 중간', per * n_doors, '개', '패널 연결부')
          rows << row("#{prefix}-폴딩 가이드", '상부 트랙 세트', n_doors, '세트', '')
        when 'sliding'
          rows << row("#{prefix}-슬라이딩 레일", "상하 세트 L#{m['width'].to_f.round}", 1, '세트', '현수식 2레일')
          rows << row("#{prefix}-행잉 롤러", '', 2 * [n_doors, 2].max / 1, '개', '도어당 2개')
        when 'lift_up'
          rows << row("#{prefix}-리프트업 스테이", '가스쇼바/에어로', 2, '개', '')
        end

        rows.concat(handles(m, prefix, n_doors)) unless door_type == 'sliding'
        rows
      end

      def handles(m, prefix, count)
        ht = (m['handle_type'] || 'none').to_s
        return [] if %w[none push_open channel].include?(ht)
        spec = ht == 'bar' ? "홀간 #{m['handle_hole_mm'] || 128}mm" : ''
        [row("#{prefix}-손잡이(#{ht})", spec, count, '개', '')]
      end

      def shelf_pins(m, prefix)
        n = (m['shelves'] || []).size + (m['cell_shelves'] || []).size
        return [] if n.zero?
        [row("#{prefix}-선반핀", "Ø#{Kabinet::Constants::SHELF_PIN_DIAMETER_MM}", n * 4, '개',
             "가동선반 #{n}장 × 4")]
      end

      def accessory_hardware(m, prefix)
        rows = []
        (m['accessories'] || []).each do |a|
          case a['kind']
          when 'hanging_rod'
            rows << row("#{prefix}-행거봉", "Ø#{(a['diameter'] || 32).to_f.round}", 1, '개', '')
            rows << row("#{prefix}-봉 브라켓", '', 2, '개', '')
          when 'system_hanger'
            rows << row("#{prefix}-시스템 레일", '', 1, '개', '')
          end
        end
        rows
      end

      def drawer_slides(m, prefix, mh)
        dc = (m['drawer_count'] || 1).to_i
        bt = m['body_thickness'].to_f
        inner_d = m['depth'].to_f - m['back_thickness'].to_f - Kabinet::Constants::BACK_RECESS_MM
        # 박스 깊이 상한 (수납침대 — 레일도 박스 깊이 기준)
        inner_d = [inner_d, m['box_depth_mm'].to_f].min if m['box_depth_mm']
        slide   = Kabinet::Core::Fitting.slide_length_mm(inner_d)
        label   = m['drawer_type'] == 'side_mount' ? '사이드 볼레일' : '언더마운트'
        len     = slide ? "L#{slide.round}" : '규격 미달(주문 확인)'
        _ = bt; _ = mh
        [row("#{prefix}-서랍 레일", "#{label} #{len}", dc, '세트', '좌우 1세트/서랍')]
      end

      def cell_drawer_hardware(m, prefix, _mh)
        rows = []
        (m['cell_drawers'] || []).each do |cd|
          dc = (cd['count'] || 2).to_i
          inner_d = m['depth'].to_f - m['back_thickness'].to_f - Kabinet::Constants::BACK_RECESS_MM
          slide   = Kabinet::Core::Fitting.slide_length_mm(inner_d)
          label   = cd['type'] == 'side_mount' ? '사이드 볼레일' : '언더마운트'
          len     = slide ? "L#{slide.round}" : '규격 미달(주문 확인)'
          rows << row("#{prefix}-셀서랍 레일", "#{label} #{len}", dc, '세트', "칸#{(cd['cell'] || 0) + 1}")
        end
        rows
      end

      def desk_hardware(m, prefix)
        rows = []
        ped = m['pedestal']
        if ped.is_a?(Hash) && ped['enabled'] != false
          dc = (ped['drawer_count'] || 3).to_i
          rows << row("#{prefix}-페데스탈 레일", '언더마운트', dc, '세트', '')
        end
        uu = m['under_unit']
        if uu.is_a?(Hash) && uu['enabled'] != false
          dc = (uu['drawer_count'] || 1).to_i
          rows << row("#{prefix}-하부유닛 레일", '언더마운트', dc, '세트', '')
        end
        rows
      end

      def row(name, spec, qty, unit, note)
        { name: name, spec: spec.to_s, qty: qty, unit: unit, note: note.to_s }
      end
    end
  end
end
