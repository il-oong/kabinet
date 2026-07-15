module Kabinet
  module Core
    # ── 부재 치수 산출 단일 소스 (Single Source of Truth) ──────────────────
    #
    # 3D 지오메트리(door_panel / drawer_module / shelf_module)와
    # 커트리스트(cut_list)가 모두 이 모듈의 공식을 사용한다.
    # 도면과 재단 목록이 서로 다른 치수를 내는 것을 구조적으로 차단한다.
    #
    # 레이아웃 함수(swing_doors 등)는 단위 불문(unit-agnostic):
    # 순수 사칙연산만 사용하므로 SU Length를 넣으면 SU Length가,
    # mm Float을 넣으면 mm Float이 나온다. 단, 갭 등 부가 치수도
    # 호출자가 같은 단위로 넘겨야 한다.
    #
    # *_mm 함수는 mm Float 전용 (규격표 스냅 등 절대값 비교가 필요한 계산).
    module Fitting
      module_function

      # ── 서랍 슬라이드 공칭 규격 (mm) ─────────────────────────────────────
      # 국내 유통 표준: 250~600, 50mm 단위. 서랍통 깊이는 이 규격에
      # 스냅해야 하드웨어 발주가 가능하다.
      SLIDE_LENGTHS_MM    = [250.0, 300.0, 350.0, 400.0, 450.0, 500.0, 550.0, 600.0].freeze
      SLIDE_REAR_CLEAR_MM = 10.0   # 레일 후단 ~ 뒷판 최소 여유

      # SU Length(내부 인치) → mm Float 변환.
      # 1.mm(= 1mm에 해당하는 내부값)으로 나누므로 Length 연산 결과가
      # Float(인치)로 강등돼도 안전하다. SketchUp 밖(순수 루비 테스트)에서
      # Numeric#mm이 항등으로 스텁되면 mm Float이 그대로 통과한다.
      def len_mm(v)
        v.to_f / 1.mm.to_f
      end

      # ── 여닫이 (오버레이) ────────────────────────────────────────────────
      # mod_w/mod_h = 모듈 외곽 폭/높이. 반환 좌표는 모듈 외곽 좌하단 기준.
      # returns [{ x:, z:, w:, h:, role: }, ...]
      def swing_doors(mod_w, mod_h, config, side_gap:, top_gap:, bottom_gap:, center_gap:)
        h  = mod_h - top_gap - bottom_gap
        z  = bottom_gap
        case config.to_s
        when 'single'
          [{ x: side_gap, z: z, w: mod_w - 2 * side_gap, h: h, role: 'door_single' }]
        when 'pair'
          w = (mod_w - 2 * side_gap - center_gap) / 2.0
          [{ x: side_gap,                  z: z, w: w, h: h, role: 'door_pair_left' },
           { x: side_gap + w + center_gap, z: z, w: w, h: h, role: 'door_pair_right' }]
        else
          []
        end
      end

      # ── 인셋 도어 ────────────────────────────────────────────────────────
      # open_w/open_h = 카케이스 내부 개구. 좌표는 개구 좌하단 기준.
      def inset_doors(open_w, open_h, config, gap:, center_gap:)
        h = open_h - 2 * gap
        case config.to_s
        when 'single'
          [{ x: gap, z: gap, w: open_w - 2 * gap, h: h, role: 'door_single' }]
        when 'pair'
          w = (open_w - 2 * gap - center_gap) / 2.0
          [{ x: gap,                  z: gap, w: w, h: h, role: 'door_pair_left' },
           { x: gap + w + center_gap, z: gap, w: w, h: h, role: 'door_pair_right' }]
        else
          []
        end
      end

      # ── 접이식 (바이폴드) — 여닫이 레이아웃을 반폭 2장으로 분할 ─────────
      def folding_doors(mod_w, mod_h, config, side_gap:, top_gap:, bottom_gap:, center_gap:)
        swing_doors(mod_w, mod_h, config,
                    side_gap: side_gap, top_gap: top_gap,
                    bottom_gap: bottom_gap, center_gap: center_gap)
          .flat_map.with_index do |d, i|
            half = d[:w] / 2.0
            [{ x: d[:x],        z: d[:z], w: half, h: d[:h], role: "door_fold_#{i}a" },
             { x: d[:x] + half, z: d[:z], w: half, h: d[:h], role: "door_fold_#{i}b" }]
          end
      end

      # ── 미닫이 (슬라이딩) — 전/후 레일 2장, 중앙 겹침 ────────────────────
      # lane: 0 = 전면 레일, 1 = 후면 레일
      def sliding_doors(mod_w, mod_h, config, overlap:, top_gap:, bottom_gap:)
        h = mod_h - top_gap - bottom_gap
        z = bottom_gap
        case config.to_s
        when 'single'
          [{ x: 0, z: z, w: mod_w, h: h, lane: 0, role: 'door_sliding_single' }]
        else # pair
          w = (mod_w + overlap) / 2.0
          [{ x: 0,         z: z, w: w, h: h, lane: 0, role: 'door_sliding_front' },
           { x: mod_w - w, z: z, w: w, h: h, lane: 1, role: 'door_sliding_back' }]
        end
      end

      # ── 리프트업 ─────────────────────────────────────────────────────────
      def lift_up_door(mod_w, mod_h, gap:)
        [{ x: gap, z: gap, w: mod_w - 2 * gap, h: mod_h - 2 * gap, role: 'door_lift_up' }]
      end

      # ── 서랍 전판 스택 (풀 오버레이) ─────────────────────────────────────
      # 모듈 외곽 기준. 반환: [{ x:, z:, w:, h: }, ...] 아래→위 순.
      def drawer_fronts(mod_w, mod_h, count, side_gap:, top_gap:, bottom_gap:, reveal:)
        n       = [count.to_i, 1].max
        avail   = mod_h - top_gap - bottom_gap - reveal * (n - 1)
        front_h = avail / n
        front_w = mod_w - 2 * side_gap
        n.times.map do |i|
          { x: side_gap, z: bottom_gap + i * (front_h + reveal), w: front_w, h: front_h }
        end
      end

      # ── 슬라이드 공칭 길이 선택 (mm 전용) ────────────────────────────────
      # 내부 유효 깊이에 들어가는 최대 규격을 반환. 250 미만이면 nil.
      def slide_length_mm(inner_depth_mm, _type = 'undermount')
        usable = inner_depth_mm.to_f - SLIDE_REAR_CLEAR_MM
        SLIDE_LENGTHS_MM.select { |l| l <= usable }.max
      end

      # ── 서랍통 치수 (mm 전용) ────────────────────────────────────────────
      # open_w_mm:      서랍이 들어가는 개구(칸) 내폭
      # comp_h_mm:      해당 서랍 1단이 차지하는 내부 높이
      # inner_depth_mm: 카케이스 내부 유효 깊이 (뒷판 앞면까지)
      # type:           'undermount' | 'side_mount'
      # returns { w:, d:, h:, slide_len:, z_off: }  (slide_len nil → 규격 미달)
      def drawer_box_mm(open_w_mm:, comp_h_mm:, inner_depth_mm:, type: 'undermount')
        under = type.to_s == 'undermount'
        side  = under ? Kabinet::Constants::UNDERMOUNT_SIDE_CLEARANCE_MM :
                        Kabinet::Constants::SIDEMOUNT_SIDE_CLEARANCE_MM
        z_off = under ? Kabinet::Constants::UNDERMOUNT_HEIGHT_OFFSET_MM :
                        Kabinet::Constants::SIDEMOUNT_HEIGHT_OFFSET_MM
        slide = slide_length_mm(inner_depth_mm, type)
        d     = slide || [inner_depth_mm.to_f - 50.0, 100.0].max
        h     = comp_h_mm.to_f - z_off - Kabinet::Constants::DRAWER_BOX_TOP_CLEAR_MM
        { w: open_w_mm.to_f - 2.0 * side, d: d, h: h, slide_len: slide, z_off: z_off.to_f }
      end

      # ── 세로 분할판 → 칸(cell) 범위 (단위 불문) ───────────────────────────
      # dividers: [{ 'x' => .., 'thickness' => .. }, ...] — x/inner_w와 같은 단위
      # (SU Length 또는 mm Float 어느 쪽이든 그대로 사용 가능. 순수 사칙연산).
      # 반환: [[start, end], ...] 좌→우, 같은 단위.
      def cell_ranges(dividers, inner_w)
        sorted = (dividers || []).sort_by { |d| d['x'] }
        prev   = inner_w * 0   # 0 in the caller's numeric type (SU Length or Float)
        ranges = []
        sorted.each do |d|
          x  = d['x']
          dt = d['thickness'] || 18
          ranges << [prev, x]
          prev = x + dt
        end
        ranges << [prev, inner_w]
        ranges
      end

      # ── 런 모드: bed_gap 제외 연속 구간 (mm 전용) ─────────────────────────
      # 걸레받이·상판·외곽은 침대 공간(bed_gap)을 가로지르면 안 되므로
      # 3D/커트리스트/도면이 모두 이 구간으로 나눠 생성한다.
      # modules: normalize된 모듈 해시 배열 (width는 mm Float).
      # 반환: [[x_offset_mm, width_mm], ...]
      def run_segments(modules)
        segs  = []
        x     = 0.0
        cur_x = nil
        cur_w = 0.0
        (modules || []).each do |m|
          w = m['width'].to_f
          if m['kind'] == 'bed_gap'
            segs << [cur_x, cur_w] if cur_x && cur_w > 0
            cur_x = nil
            cur_w = 0.0
          else
            cur_x ||= x
            cur_w += w
          end
          x += w
        end
        segs << [cur_x, cur_w] if cur_x && cur_w > 0
        segs
      end

      # ── 도어/전판 전면 돌출량 (mm 전용) ──────────────────────────────────
      # EP 마감판이 도어 전면까지 나와야 할 때 필요한 깊이 연장량.
      # modules: normalize된 모듈 해시 배열.
      def front_protrusion_mm(modules)
        off  = Kabinet::Constants::DOOR_FRONT_OFFSET_MM.to_f
        prot = 0.0
        (modules || []).each do |m|
          p = case m['kind']
              when 'drawer_module'
                (m['drawer_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM).to_f + off
              when 'shelf_module'
                t = (m['door_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM).to_f
                has_overlay_door = (m['door_config'] || 'none') != 'none' && m['door_mount'] != 'inset'
                if has_overlay_door && m['door_type'] == 'sliding'
                  # 미닫이 후면 레일 도어까지의 돌출: 도어 2겹 + 레일 간격
                  t + Kabinet::Constants::SLIDING_DOOR_TRACK_SPACING_MM + off
                elsif has_overlay_door || !(m['cell_drawers'] || []).empty?
                  t + off
                else
                  0.0
                end
              else
                0.0
              end
          prot = p if p > prot
        end
        prot
      end
    end
  end
end
