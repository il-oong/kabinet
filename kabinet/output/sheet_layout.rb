module Kabinet
  module Output
    # 가구 도면(LayOut) 쪽 배치 계획 — 순수 계산 (SketchUp·LayOut 불필요, 테스트·미리보기 가능).
    #
    # 규칙
    #   * A3 가로(420x297 mm) 여러 쪽. 쪽마다 모든 뷰가 같은 표준 배율(STD_DENS 중 들어가는 가장 큰 값).
    #   * 각 뷰의 종이상 크기 = 가구 크기 x 배율 + 치수선 여백 + 캡션. 쪽 안에서 서로 겹치지 않게 배치.
    #   * 쪽 구성(기본): 1 입체도·재질·메모 / 2 정면도+평면도(+측면도: 작은 가구는 한 쪽에) / 3 측면도(좌·우).
    #     정면도가 한 쪽에 표준 배율 1/50 이하로만 들어가면 정면·평면을 좌우 구간으로 나눠 쪽을 늘린다.
    #   * 모든 좌표는 종이 mm, 원점은 쪽 왼쪽 위(y 아래로).
    module SheetLayout
      module_function

      STD_DENS = [5, 8, 10, 15, 20, 25, 30, 40, 50, 75, 100].freeze
      PAGE_W = 420.0
      PAGE_H = 297.0
      # 내용 영역(제목줄 아래 ~ 표제란 위)
      AREA = { x0: 15.0, y0: 26.0, x1: 405.0, y1: 262.0 }.freeze
      TITLE_BLOCK = { x: 15.0, y: 268.0, w: 390.0, h: 18.0 }.freeze
      GAP = 8.0
      MIN_OUTER_W = 72.0      # 캡션(뷰 이름 + SCALE) 글자가 들어갈 최소 폭
      CAPTION_H = 9.0
      SPLIT_DEN = 50          # 이보다 작은 배율(분모 큼)이 필요하면 정면 구간 분할
      SPLIT_OVERLAP = 100.0   # 분할 구간 겹침(mm, 실물)
      MAX_WINDOWS = 4
      COMBO_MAX_DEN = 10      # 한 쪽에 정면·평면·측면을 모으는 경우 허용 최소 크기(분모 상한)

      # 뷰별 치수선 여백(종이 mm): 왼쪽·오른쪽·위·아래
      MARGINS = {
        'front'  => { l: 10.0, r: 20.0, t: 34.0, b: 6.0 },
        'top'    => { l: 10.0, r: 20.0, t: 18.0, b: 6.0 },
        'side_r' => { l: 6.0, r: 20.0, t: 18.0, b: 6.0 },
        'side_l' => { l: 20.0, r: 6.0, t: 18.0, b: 6.0 }
      }.freeze
      # 장(유닛) 세부 도면 뷰: 정면(도어 닫힘) / 정면 내부(도어 제거) / 평면 / 측면 단면(우측 측판 제거)
      MARGINS_UNIT = {
        'u_front' => { l: 10.0, r: 20.0, t: 28.0, b: 6.0 },
        'u_inner' => { l: 10.0, r: 20.0, t: 28.0, b: 6.0 },
        'u_top' => { l: 10.0, r: 20.0, t: 18.0, b: 6.0 },
        'u_section' => { l: 6.0, r: 20.0, t: 18.0, b: 6.0 }
      }.freeze
      AXES = { 'front' => [0, 2], 'top' => [0, 1], 'side_r' => [1, 2], 'side_l' => [1, 2],
               'u_front' => [0, 2], 'u_inner' => [0, 2], 'u_top' => [0, 1], 'u_section' => [1, 2] }.freeze
      LABELS = { 'front' => 'FRONT VIEW 정면도', 'top' => 'TOP VIEW 평면도',
                 'side_r' => 'RIGHT SIDE VIEW 우측면도', 'side_l' => 'LEFT SIDE VIEW 좌측면도',
                 'u_front' => 'FRONT VIEW 정면도(도어 닫힘)', 'u_inner' => 'FRONT VIEW 내부(도어 제거)',
                 'u_top' => 'TOP VIEW 평면도', 'u_section' => 'SECTION 측면 단면' }.freeze
      TABLE_W = 112.0         # 장 쪽 오른쪽 장 표 폭
      MAX_UNIT_PAGES = 16
      UNIT_VIEW_MODEL = { 'u_front' => 'front', 'u_inner' => 'front', 'u_top' => 'top', 'u_section' => 'side_r' }.freeze

      def area_w; AREA[:x1] - AREA[:x0]; end
      def area_h; AREA[:y1] - AREA[:y0]; end

      # 모델 mm 크기 [w, d, h] 의 뷰 이름별 실물 크기(가로, 세로)
      def model_extent(name, w, d, h)
        case name
        when 'front', 'u_front', 'u_inner' then [w, h]
        when 'top', 'u_top' then [w, d]
        else [d, h]
        end
      end

      # 한 뷰: 기하 사각형 [gw, gh] 와 바깥 사각형(여백·캡션 포함)의 종이 크기
      def view_dims(name, ext, den)
        m = MARGINS[name] || MARGINS_UNIT.fetch(name)
        gw = ext[0] / den
        gh = ext[1] / den
        { gw: gw, gh: gh, ow: [gw + m[:l] + m[:r], MIN_OUTER_W].max, oh: gh + m[:t] + m[:b] + CAPTION_H, m: m }
      end

      # 들어가는 가장 큰 표준 배율 분모를 구한다. fit 블록은 den 을 받아 true/false.
      def largest_den
        STD_DENS.find { |den| yield(den) }
      end

      # ── 한 쪽 안의 뷰 배치(가운데 정렬, 기준선 정렬) ──────────────────────
      # columns: [[view_name, ...] 위→아래, ...] 왼→오. 각 열은 아래 뷰 기준선 기하 하단을 공유한다.
      # 반환: 배치 가능하면 { views: [...] }, 아니면 nil. 모든 뷰는 같은 배율.
      def arrange(columns, windows, size, den, area = AREA)
        w, d, h = size
        dims = {}
        columns.flatten.each do |n|
          win = windows[n]
          dims[n] = view_dims(n, model_extent(n, win ? win[1] - win[0] : w, d, h), den)
        end
        col_w = columns.map { |col| col.map { |n| dims[n][:ow] }.max }
        total_w = col_w.sum + GAP * (columns.length - 1)
        # 열 높이: 기준선 위 / 아래
        above = columns.map do |col|
          col.each_with_index.sum do |n, i|
            dm = dims[n]
            base = dm[:m][:t] + dm[:gh]
            i == col.length - 1 ? base : base + dm[:m][:b] + CAPTION_H + GAP
          end
        end
        below = columns.map { |col| dims[col.last][:m][:b] + CAPTION_H }
        total_h = above.max + below.max
        aw = area[:x1] - area[:x0]
        ah = area[:y1] - area[:y0]
        return nil if total_w > aw + 1e-6 || total_h > ah + 1e-6
        x = area[:x0] + (aw - total_w) / 2
        baseline = area[:y0] + (ah - total_h) / 2 + above.max
        views = []
        columns.each_with_index do |col, ci|
          outer_top = nil
          col.reverse_each do |n|
            dm = dims[n]
            gx = x + dm[:m][:l]
            y_bottom = outer_top ? outer_top - GAP - dm[:m][:b] - CAPTION_H : baseline
            gy = y_bottom - dm[:gh]
            views << {
              name: n, label: LABELS.fetch(n), den: den, clip: windows[n] ? windows[n].dup : nil,
              rect: [gx, gy, dm[:gw], dm[:gh]],
              outer: [x, gy - dm[:m][:t], dm[:ow], dm[:m][:t] + dm[:gh] + dm[:m][:b] + CAPTION_H],
              marker: front_marker(n, [gx, gy, dm[:gw], dm[:gh]])
            }
            outer_top = gy - dm[:m][:t]
          end
          x += col_w[ci] + GAP
        end
        { views: views }
      end

      # 같은 배율로 columns 를 배치. 표준 배율 중 들어가는 가장 큰 값. 못 들어가면 nil.
      def fit_columns(columns, windows, size, area = AREA)
        STD_DENS.each do |den|
          arr = arrange(columns, windows, size, den, area)
          return arr.merge(den: den) if arr
        end
        nil
      end

      # 전면 표시(작은 화살표 + '전면'): 방향을 도면만 봐도 알 수 있게 한다. 정면도에는 없다.
      #   우측면도 = 전면이 왼쪽(화살표 왼쪽), 좌측면도 = 전면이 오른쪽, 평면도 = 전면이 아래쪽.
      #   arrow = [x1, y1, x2, y2] (머리는 끝점), 모두 뷰 바깥 여백 안(종이 mm, y 아래로).
      def front_marker(name, rect)
        x, y, w, h = rect
        case name
        when 'side_r', 'u_section' then { dir: 'left', label: '전면', arrow: [x + 9, y + h + 3, x, y + h + 3], text: [x + 11, y + h + 0.8, 14, 4.5] }
        when 'side_l' then { dir: 'right', label: '전면', arrow: [x + w - 9, y + h + 3, x + w, y + h + 3], text: [x + w - 25, y + h + 0.8, 14, 4.5] }
        when 'top', 'u_top' then { dir: 'down', label: '전면', arrow: [x - 5, y + h - 12, x - 5, y + h], text: [x - 9.5, y + h - 20, 9, 4.5] }
        end
      end

      def view_page(id, title, fit, extra = {})
        { id: id, title: title, scale: fit[:den], views: fit[:views] }.merge(extra)
      end

      # 정면+평면(+측면)을 한 쪽에 — 세로로 평면 위 정면 아래, 필요하면 측면을 옆에
      def front_top_columns(sides)
        left = sides.include?('side_l') ? [['side_l']] : []
        right = sides.include?('side_r') ? [['side_r']] : []
        left + [%w[top front]] + right
      end

      # 정면+평면 쪽(들) — 구간 분할 포함. 반환: 쪽 배열
      def front_pages(size)
        w, = size
        best = nil
        (1..MAX_WINDOWS).each do |n|
          wins = window_ranges(w, n)
          fits = wins.map { |win| fit_columns(front_top_columns([]), { 'front' => win, 'top' => win }, size) }
          next if fits.any?(&:nil?)
          # 모든 구간이 같은 배율: 가장 작은 배율(큰 분모)로 통일
          den = fits.map { |f| f[:den] }.max
          arrs = wins.map { |win| arrange(front_top_columns([]), { 'front' => win, 'top' => win }, size, den) }
          best = { n: n, wins: wins, den: den, arrs: arrs }
          break if den <= SPLIT_DEN
        end
        raise '가구가 너무 커서 쪽에 배치할 수 없습니다.' unless best
        best[:arrs].each_with_index.map do |arr, i|
          suffix = best[:n] > 1 ? " (#{i + 1}/#{best[:n]})" : ''
          extra = best[:n] > 1 ? { window: best[:wins][i] } : {}
          view_page('front', "정면도·평면도#{suffix}", arr.merge(den: best[:den]), extra)
        end
      end

      def window_ranges(w, n)
        return [nil] if n == 1
        step = w.to_f / n
        (0...n).map do |i|
          [[i * step - (i.zero? ? 0 : SPLIT_OVERLAP / 2), 0.0].max, [(i + 1) * step + (i == n - 1 ? 0 : SPLIT_OVERLAP / 2), w.to_f].min]
        end.map { |a, b| [a.round(1), b.round(1)] }
      end

      # 입체도·재질·메모 쪽: 좌측 큰 입체도, 우측 재질·메모·표기.
      def iso_page
        iso = [AREA[:x0], AREA[:y0], 260.0, area_h]
        rx = AREA[:x0] + 260.0 + GAP
        rw = AREA[:x1] - rx
        {
          id: 'iso', title: '입체도·재질·메모', scale: nil, views: [],
          boxes: {
            iso: iso,
            materials: [rx, AREA[:y0], rw, 62.0],
            memo: [rx, AREA[:y0] + 62.0 + GAP, rw, 92.0],
            notes: [rx, AREA[:y0] + 62.0 + GAP + 92.0 + GAP, rw, area_h - 62.0 - 92.0 - 2 * GAP]
          }
        }
      end

      # 장(유닛) 세부 쪽 하나: 평면 위 정면(도어 닫힘), 내부(도어 제거), 측면 단면, 오른쪽 장 표.
      def unit_page(unit, size)
        area = AREA.merge(x1: AREA[:x1] - TABLE_W - GAP)
        cols = [%w[u_top u_front], ['u_inner'], ['u_section']]
        fit = fit_columns(cols, {}, size, area)
        raise "장 #{unit[:index].to_i + 1} 이(가) 너무 커서 쪽에 배치할 수 없습니다." unless fit
        title = "장 #{unit[:number]} / #{unit[:count]} - #{unit[:name]} (#{unit[:size].map { |v| v.round }.join('x')})"
        view_page('unit', title, fit, unit: unit[:index], boxes: { table: [AREA[:x1] - TABLE_W, AREA[:y0], TABLE_W, area_h] })
      end

      # units: [{ index:, name:, size: [w, d, h] }] (좌 -> 우 순서). 반환: 쪽 배열
      def unit_pages(units)
        raise "장이 너무 많습니다(최대 #{MAX_UNIT_PAGES}개). 일부만 선택하세요." if units.length > MAX_UNIT_PAGES
        units.each_with_index.map do |u, i|
          unit_page({ index: u[:index], name: u[:name].to_s, size: u[:size], number: i + 1, count: units.length }, u[:size].map(&:to_f))
        end
      end

      # 장 표 글자(순수): info = { name:, size: [w,d,h], index:, count:, parts: [{role:, dims: [a,b,c]}] }
      PART_NAMES = [[/drawer_front/, '서랍 전면'], [/drawer/, '서랍 부재'], [/door/, '도어'], [/channel/, '찬넬'], [/side/, '측판'],
                    [/top/, '상판/레일'], [/bottom/, '하판'], [/back/, '뒷판'], [/shelf/, '선반'], [/divider/, '칸막이']].freeze

      def part_name(role)
        r = role.to_s
        hit = PART_NAMES.find { |re, _| re =~ r }
        hit ? hit[1] : r
      end

      def parts_table(parts)
        rows = Hash.new(0)
        parts.each do |pt|
          dims = pt[:dims].map { |v| v.round }.sort.reverse
          rows[[part_name(pt[:role]), dims]] += 1
        end
        rows.map { |(name, dims), qty| [name, "#{dims[0]} x #{dims[1]} x #{dims[2]}T", qty] }.sort_by { |n, d, _| [n, d] }
      end

      def unit_table_lines(info, body_t = 18)
        w, d, h = info[:size].map { |v| v.round }
        parts = info[:parts] || []
        doors = parts.count { |pt| pt[:role].to_s =~ /door/ && pt[:role].to_s !~ /drawer/ }
        drawers = parts.count { |pt| pt[:role].to_s =~ /drawer_front/ }
        shelves = parts.count { |pt| pt[:role].to_s =~ /shelf/ }
        lines = ["장 #{info[:number]} / #{info[:count]}", info[:name].to_s,
                 "외곽 폭 x 깊이 x 높이: #{w} x #{d} x #{h}",
                 "내경(= 외곽 - #{body_t * 2}): #{w - body_t * 2}",
                 '측판: 장마다 양쪽 18T (이웃 장 사이 판 2장 = 36)',
                 "도어 #{doors}장 / 서랍 #{drawers}단 / 선반 #{shelves}장 / 칸수 #{shelves + 1}"]
        table = parts_table(parts)
        lines << '' << '판재 목록 (부재 / 크기 / 수량)'
        table.each { |n, dm, q| lines << "#{n}  #{dm}  x#{q}" }
        lines << '(판재 크기는 3D 부재의 외곽 치수, 제작 전 확인)' unless table.empty?
        lines
      end

      # size = [w, d, h] (mm). opts: 'pages' => %w[iso front side] (기본 모두)
      def plan(size, opts = {})
        w, d, h = size.map(&:to_f)
        raise '가구 크기가 올바르지 않습니다.' if [w, d, h].any? { |v| v <= 0 }
        size = [w, d, h]
        want = (opts['pages'] || opts[:pages] || %w[iso front side]).map(&:to_s)
        units = opts['units'] || opts[:units]
        pages = []
        pages << iso_page if want.include?('iso')
        if want.include?('front') || want.include?('side')
          combo = nil
          if want.include?('front') && want.include?('side')
            fit = fit_columns(front_top_columns(%w[side_l side_r]), {}, size)
            combo = fit if fit && fit[:den] <= COMBO_MAX_DEN
          end
          if combo
            pages << view_page('combo', '정면도·평면도·측면도', combo)
          else
            pages.concat(front_pages(size)) if want.include?('front')
            if want.include?('side')
              fit = fit_columns([['side_l'], ['side_r']], {}, size)
              raise '가구가 너무 커서 측면도를 배치할 수 없습니다.' unless fit
              pages << view_page('side', '좌·우 측면도', fit)
            end
          end
        end
        units = opts['units'] || opts[:units]
        pages.concat(unit_pages(units)) if units && !units.empty?
        pages.each_with_index { |pg, i| pg[:number] = i + 1; pg[:total] = pages.length }
        { size: size, pages: pages, title_block: title_block_cells }
      end

      # 표제란 칸(종이 mm): key 는 값 채우기용
      def title_block_cells
        t = TITLE_BLOCK
        rh = t[:h] / 2
        [
          { key: 'furniture', label: '가구명', rect: [t[:x], t[:y], 120.0, rh] },
          { key: 'site', label: '현장정보', rect: [t[:x] + 120.0, t[:y], t[:w] - 120.0, rh] },
          { key: 'date', label: '제작날짜', rect: [t[:x], t[:y] + rh, 90.0, rh] },
          { key: 'author', label: '작성자', rect: [t[:x] + 90.0, t[:y] + rh, 90.0, rh] },
          { key: 'scale', label: '축척', rect: [t[:x] + 180.0, t[:y] + rh, 90.0, rh] },
          { key: 'page', label: '쪽', rect: [t[:x] + 270.0, t[:y] + rh, t[:w] - 270.0, rh] }
        ]
      end

      # LayOut 글자 깨짐 방지: 한글 Windows(CP949)에 없는 문자(em dash 등)는 '?'로 깨진다 → 안전한 문자로 치환.
      TEXT_MAP = { "\u2014" => '-', "\u2013" => '-', "\u2015" => '-', "\u2212" => '-', "\u2018" => "'", "\u2019" => "'",
                   "\u201C" => '"', "\u201D" => '"', "\u2026" => '...', "\u00A0" => ' ', "\u2192" => '->', "\u2264" => '<=', "\u2265" => '>=' }.freeze

      def clean_text(value)
        str = value.to_s.dup.force_encoding(Encoding::UTF_8)
        str = str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: ' ') unless str.valid_encoding?
        TEXT_MAP.each { |from, to| str = str.gsub(from, to) }
        str.each_char.map do |ch|
          begin
            ch.encode(Encoding::CP949)
            ch
          rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
            ' '
          end
        end.join
      end

      def scale_label(den)
        den ? "1/#{den}" : 'N.T.S'
      end

      # ── 검사 도우미 ───────────────────────────────────────────────────────
      def rects_intersect?(a, b)
        a[0] < b[0] + b[2] - 1e-6 && b[0] < a[0] + a[2] - 1e-6 && a[1] < b[1] + b[3] - 1e-6 && b[1] < a[1] + a[3] - 1e-6
      end

      def inside_area?(r)
        r[0] >= AREA[:x0] - 1e-6 && r[1] >= AREA[:y0] - 1e-6 && r[0] + r[2] <= AREA[:x1] + 1e-6 && r[1] + r[3] <= AREA[:y1] + 1e-6
      end

      # 문제 목록(빈 배열이면 통과): 겹침·영역 이탈·표제란 침범·비표준 배율·쪽 내 배율 불일치
      def problems(plan)
        out = []
        tb = [TITLE_BLOCK[:x], TITLE_BLOCK[:y], TITLE_BLOCK[:w], TITLE_BLOCK[:h]]
        plan[:pages].each do |pg|
          rects = pg[:views].map { |v| [v[:name], v[:outer]] }
          (pg[:boxes] || {}).each { |k, r| rects << [k.to_s, r] }
          rects.each { |n, r| out << "쪽#{pg[:number]} #{n}: 내용 영역 이탈" unless inside_area?(r) }
          rects.each { |n, r| out << "쪽#{pg[:number]} #{n}: 표제란 침범" if rects_intersect?(r, tb) }
          rects.combination(2) { |(an, ar), (bn, br)| out << "쪽#{pg[:number]} #{an}/#{bn}: 겹침" if rects_intersect?(ar, br) }
          dens = pg[:views].map { |v| v[:den] }.uniq
          out << "쪽#{pg[:number]}: 배율 불일치 #{dens}" if dens.length > 1
          dens.each { |dn| out << "쪽#{pg[:number]}: 비표준 배율 #{dn}" unless STD_DENS.include?(dn) }
        end
        out
      end

      # 선분 [x1,y1,x2,y2] 를 x 구간 [a,b] 로 자른다(없으면 nil). x 는 a 만큼 이동해 돌려준다.
      def clip_segment(seg, a, b)
        return seg if a.nil?
        x1, y1, x2, y2 = seg.map(&:to_f)
        lo, hi = [x1, x2].minmax
        return nil if hi < a - 1e-9 || lo > b + 1e-9
        return [(x1 - a).round(3), y1, (x2 - a).round(3), y2] if lo >= a && hi <= b
        return nil if (x2 - x1).abs < 1e-9
        t1 = (a - x1) / (x2 - x1)
        t2 = (b - x1) / (x2 - x1)
        t_lo, t_hi = [t1, t2].minmax
        t_lo = [t_lo, 0.0].max
        t_hi = [t_hi, 1.0].min
        return nil if t_hi - t_lo < 1e-9
        px = ->(t) { x1 + (x2 - x1) * t }
        py = ->(t) { y1 + (y2 - y1) * t }
        [(px.call(t_lo) - a).round(3), py.call(t_lo).round(3), (px.call(t_hi) - a).round(3), py.call(t_hi).round(3)]
      end
    end
  end
end
