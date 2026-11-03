require_relative 'frame'
require_relative 'model'
module Kabinet
  module Output
    module Sheet
      # 페이지 빌더 — 모두 순수 계산(Canvas 반환). 좌표계·양식은 SHEET_FORMAT_ANALYSIS.md 참조.
      module Pages
        module_function

        EP = 20.0
        BT = 18.0
        DT = 20.0
        BACK_T = 9.0
        CH_H = 60.0
        CH_GAP = 25.0

        def f(n); Sheet.fmt(n); end

        def lbl(md)
          md['label'].to_s.empty? ? md['name'] : md['label']
        end

        def has_ep?(m)
          m['ep'].values_at('left', 'right', 'top').any?
        end

        # ── 평면(TOP VIEW): 앞(정면) = 아래 ───────────────────────────────
        def draw_plan(c, m, ox, oy, s, labels: true)
          o = m['overall']; w = o['W']; d = o['D']
          m['modules'].each do |md|
            x0 = ox + md['x'] * s; x1 = ox + (md['x'] + md['w']) * s
            c.rect(x0, oy + (d - md['d']) * s, x1, oy + d * s, 'THIN')
            c.line(x0, oy + (d - DT) * s, x1, oy + (d - DT) * s, 'THIN') if %w[doors drawers].include?(md['type'])   # 도어 20T
            c.text((x0 + x1) / 2, oy + (d - md['d'] / 2) * s + 0.6, lbl(md), 1.8, 'g', 'c') if labels && md['w'] * s > 8
          end
          ep = m['ep']; t = ep['thickness']
          c.ep_rect(ox, oy, ox + t * s, oy + d * s, 0.45) if ep['left']
          c.ep_rect(ox + (w - t) * s, oy, ox + w * s, oy + d * s, 0.45) if ep['right']
          c.rect(ox, oy, ox + w * s, oy + d * s, 'OUT')
          sk = m['sink']
          if sk
            c.rrect(ox + sk['x'] * s, oy + sk['y'] * s, ox + (sk['x'] + sk['w']) * s, oy + (sk['y'] + sk['d']) * s, [25 * s, 0.4].max, 'OUT')
          end
        end

        def plan_dims(c, m, ox, oy, s)
          o = m['overall']; w = o['W']; d = o['D']
          xs = ([0.0, w] + m['modules'].flat_map { |md| [md['x'], md['x'] + md['w']] }).map(&:round).uniq.sort
          c.dim_h(xs.map { |x| ox + x * s }, oy - 5.5, xs.each_cons(2).map { |a, b| f(b - a) }, ref: oy) if xs.size > 2
          c.dim_h([ox, ox + w * s], oy - 11.5, [f(w)], ref: oy)
          c.dim_v(ox - 5.5, [oy, oy + d * s], [f(d)], ref: ox)
        end

        # 단면 절단 위치(평면 X) 1~2개. 지정(cuts)이 없으면 문/서랍 모듈 중 가운데 1개(Python 과 동일)
        def cut_list(m)
          return m['cuts'] unless m['cuts'].nil? || m['cuts'].empty?
          mods = m['modules'].select { |md| %w[doors drawers].include?(md['type']) }
          mods = m['modules'] if mods.empty?
          md = mods[mods.size / 2]
          [md['x'] + md['w'] / 2.0]
        end

        def cut_x(m)
          cut_list(m).first
        end

        # 평면 마커(A/C/D 방향 + 절단선 + 번호 마커 양끝)
        def plan_markers(c, m, ox, oy, s)
          o = m['overall']; w = o['W']; d = o['D']
          cy = oy + d * s / 2
          c.marker(ox + w * s + 8, oy + d * s - 8, 'A', :down)
          c.marker(ox + w * s + 8, cy, 'D', :left)
          c.marker(ox - 25.0, cy, 'C', :right)
          cut_list(m).each_with_index do |cx, i|
            x = ox + cx * s
            yt = oy - 19.0; yb = oy + d * s + 14.5
            c.chain(x, yt + 3.3, x, yb - 3.3, 'FR')
            c.line(x - 2.2, yt + 5.0, x + 2.2, yt + 5.0, 'SEC'); c.line(x - 2.2, yb - 5.0, x + 2.2, yb - 5.0, 'SEC')
            c.marker(x, yt, (i + 1).to_s, :right); c.marker(x, yb, (i + 1).to_s, :right)
          end
        end

        # 키플랜: 방 + 가구 위치 + 전면 방향 빨간 삼각형
        def keyplan(c, m, x0 = 12.0, y0 = 19.5, w = 26.0)
          rd = m['room']; o = m['overall']
          s = w / rd['W']; h = rd['D'] * s
          c.rect(x0, y0, x0 + w, y0 + h, 'OUT')
          wt = 150 * s
          c.rect(x0 + wt, y0 + wt, x0 + w - wt, y0 + h - wt, 'THIN')
          ix = x0 + (rd['W'] - o['W']) / 2 * s
          c.rect(ix, y0 + wt, ix + o['W'] * s, y0 + wt + o['D'] * s, 'OUT')
          cx = ix + o['W'] * s / 2; by = y0 + wt + o['D'] * s
          c.fill([[cx - 1.6, by + 3.4], [cx + 1.6, by + 3.4], [cx, by + 0.6]], [222, 0, 56])
        end

        # ── 정면 공통 ─────────────────────────────────────────────────────
        def fronts_for(m, md)
          z0 = md['z'] + 4
          z1 = m['channel'] ? md['z'] + md['h'] - EP - CH_GAP : md['z'] + md['h'] - 4
          case md['type']
          when 'drawers'
            n = [md['drawers'], 1].max
            gap = m['channel'] ? CH_GAP : 3.0
            fh = (((z1 - z0) - gap * (n - 1)) / n).floor
            (0...n).map { |i| [z0 + i * (fh + gap), z0 + i * (fh + gap) + fh] }
          when 'doors'
            [[z0, z1]]
          else
            []
          end
        end

        def elev_frame(c, m, ox, gy, s)
          o = m['overall']
          x = ->(v) { ox + v * s }
          z = ->(v) { gy - v * s }
          if o['top_thickness'] > 0
            c.rect(x.call(0), z.call(o['H']), x.call(o['W']), z.call(o['H'] - o['top_thickness']), 'OUT')
          end
          [x, z]
        end

        def elev_dims(c, m, x, z)
          o = m['overall']
          top = z.call(o['H'])
          xs = ([0.0, o['W']] + m['modules'].flat_map { |md| [md['x'], md['x'] + md['w']] }).map(&:round).uniq.sort
          c.dim_h(xs.map { |v| x.call(v) }, top - 11.0, xs.each_cons(2).map { |a, b| f(b - a) }, ref: top) if xs.size > 2
          c.dim_h([x.call(0), x.call(o['W'])], top - 17.0, [f(o['W'])], ref: top)
          body = o['H'] - o['top_thickness']
          c.dim_v(x.call(0) - 6.0, [z.call(body), z.call(0)], [f(body)], ref: x.call(0)) if o['top_thickness'] > 0
          c.dim_v(x.call(0) - 12.0, [z.call(o['H']), z.call(0)], [f(o['H'])], ref: x.call(0))
          if o['kick'] > 0
            c.dim_v(x.call(o['W']) + 6.0, [z.call(body), z.call(o['kick']), z.call(0)], [f(body - o['kick']), f(o['kick'])], ref: x.call(o['W']), side: 1)
          end
        end

        def ep_strips(c, m, x, z, body, k)
          o = m['overall']; ep = m['ep']; t = ep['thickness']
          c.ep_rect(x.call(0), z.call(body), x.call(t), z.call(k), 0.5) if ep['left']
          c.ep_rect(x.call(o['W'] - t), z.call(body), x.call(o['W']), z.call(k), 0.5) if ep['right']
          c.ep_rect(x.call(0), z.call(body), x.call(o['W']), z.call(body - t), 0.5) if ep['top']
        end

        def draw_door_view(c, m, ox, gy, s)
          o = m['overall']
          x, z = elev_frame(c, m, ox, gy, s)
          body = o['H'] - o['top_thickness']; k = o['kick']
          c.rect(x.call(0), z.call(body), x.call(o['W']), z.call(k), 'OUT') if body > k
          c.rect(x.call(10), z.call(k), x.call(o['W'] - 10), z.call(0), 'OUT') if k > 0
          m['modules'].each do |md|
            zb = md['z']; zt = md['z'] + md['h']
            c.line(x.call(md['x']), z.call(zb), x.call(md['x']), z.call(zt), 'OUT') if md['x'] > 0
            fr = fronts_for(m, md)
            case md['type']
            when 'doors'
              n = [md['doors'], 1].max
              dw = (md['w'] - 3.0 * (n - 1) - 6.0) / n
              n.times do |i|
                xa = md['x'] + 3.0 + i * (dw + 3.0)
                fr.each do |z0, z1|
                  c.rect(x.call(xa), z.call(z1), x.call(xa + dw), z.call(z0), 'OUT')
                  if m['channel']
                    c.rect(x.call(xa), z.call(z1 + CH_GAP), x.call(xa + dw), z.call(z1), 'OUT')     # 전판(찬넬 가림)
                  else
                    hx = (n == 1 || i.zero?) ? xa + dw - 40 : xa + 40                              # 손잡이 위치 표시(힌지 표기 없음)
                    c.line(x.call(hx), z.call((z0 + z1) / 2 - 60), x.call(hx), z.call((z0 + z1) / 2 + 60), 'THIN')
                  end
                end
              end
            when 'drawers'
              fr.each do |z0, z1|
                c.rect(x.call(md['x'] + 3), z.call(z1), x.call(md['x'] + md['w'] - 3), z.call(z0), 'OUT')
                c.rect(x.call(md['x'] + 3), z.call(z1 + CH_GAP), x.call(md['x'] + md['w'] - 3), z.call(z1), 'OUT') if m['channel']
                zc = (z0 + z1) / 2
                c.line(x.call(md['x'] + md['w'] / 2 - 100), z.call(zc), x.call(md['x'] + md['w'] / 2 + 100), z.call(zc), 'THIN') unless m['channel']
                c.dim_v(x.call(md['x'] + md['w']) - 3.0, [z.call(z1), z.call(z0)], [f(z1 - z0)], size: 1.7, ref: nil) if fr.size > 1 && md['w'] * s > 12
              end
            when 'appliance'
              c.text(x.call(md['x'] + md['w'] / 2), z.call((zb + zt) / 2), lbl(md), 2.0, 'r', 'c')
              c.dashed(x.call(md['x'] + 5), z.call(zb), x.call(md['x'] + 5), z.call(zt), 'RED')
            when 'desk'
              c.rect(x.call(md['x']), z.call(zt), x.call(md['x'] + md['w']), z.call(zt - 25), 'OUT')
            end
            if m['channel'] && %w[doors drawers].include?(md['type']) && md['w'] * s > 12
              top_f = fr.empty? ? zt : fr.last[1]
              c.blue_leader(x.call(md['x'] + md['w'] * 0.5), z.call(top_f - 110), x.call(md['x'] + md['w'] * 0.5), z.call(top_f + CH_GAP / 2.0), '목찬넬 60*40', 'l', 1.8)
            end
          end
          ep_strips(c, m, x, z, body, k)
          elev_dims(c, m, x, z)
          c.text(x.call(o['W'] / 2), z.call(k / 2.0) + 0.6, "걸레받이 H#{f(k)}", 1.7, 'g', 'c') if k > 0
          [x, z]
        end

        def draw_body_view(c, m, ox, gy, s)
          o = m['overall']
          x, z = elev_frame(c, m, ox, gy, s)
          body = o['H'] - o['top_thickness']; k = o['kick']
          c.rect(x.call(0), z.call(body), x.call(o['W']), z.call(k), 'OUT') if body > k
          c.rect(x.call(10), z.call(k), x.call(o['W'] - 10), z.call(0), 'OUT') if k > 0
          m['modules'].each do |md|
            zb = md['z']; zt = md['z'] + md['h']
            c.rect(x.call(md['x'] - 9), z.call(zt), x.call(md['x'] + 9), z.call(zb), 'THIN') if md['x'] > 0   # 칸막이 18T
            c.line(x.call(md['x']), z.call(zb), x.call(md['x'] + md['w']), z.call(zb), 'THIN')                # 모듈 하판/경계
            md['shelves'].each do |sh|
              zz = zb + sh
              c.rect(x.call(md['x'] + 9), z.call(zz + 9), x.call(md['x'] + md['w'] - 9), z.call(zz - 9), 'THIN')
              c.text(x.call(md['x'] + md['w'] / 2), z.call(zz) - 1.0, "선반 #{f(zz - zb)}", 1.6, 'g', 'c') if md['w'] * s > 14
            end
            md['rods'].each do |rr|
              zz = zb + rr
              c.dashed(x.call(md['x'] + 12), z.call(zz), x.call(md['x'] + md['w'] - 12), z.call(zz), 'BLUE', 2.0, 1.0)
              c.text(x.call(md['x'] + md['w'] / 2), z.call(zz) - 1.0, '옷걸이봉', 1.6, 'b', 'c') if md['w'] * s > 14
            end
            if md['type'] == 'drawers'
              fronts_for(m, md).each do |z0, _z1|
                c.rect(x.call(md['x'] + 22), z.call(z0 + 140), x.call(md['x'] + md['w'] - 22), z.call(z0 + 30), 'THIN')   # 서랍통
              end
            end
            if md['type'] == 'appliance'
              c.rect(x.call(md['x'] + 7), z.call(zt - 5), x.call(md['x'] + md['w'] - 7), z.call(zb + 5), 'RED')
              c.text(x.call(md['x'] + md['w'] / 2), z.call((zb + zt) / 2), lbl(md), 1.8, 'r', 'c')
            elsif md['w'] * s > 10 && md['shelves'].empty?
              c.text(x.call(md['x'] + md['w'] / 2), z.call((zb + zt) / 2), lbl(md), 1.7, 'g', 'c')
            end
            if m['channel']
              fronts_for(m, md).each do |_z0, z1|
                c.rect(x.call(md['x'] + 1.5), z.call(z1 + CH_GAP), x.call(md['x'] + md['w'] - 1.5), z.call(z1 + CH_GAP - CH_H), 'BLUE')   # 목찬넬
              end
            end
          end
          ep_strips(c, m, x, z, body, k)
          elev_dims(c, m, x, z)
          # 단면 절단선 + 번호 마커 양끝 (평면의 절단선과 같은 번호)
          cut_list(m).each_with_index do |cx, i|
            xx = x.call(cx); yt = z.call(o['H']) - 23.0; yb = gy + 9.5
            c.chain(xx, yt + 3.3, xx, yb - 3.3, 'FR')
            c.line(xx - 2.2, yt + 5.0, xx + 2.2, yt + 5.0, 'SEC'); c.line(xx - 2.2, yb - 5.0, xx + 2.2, yb - 5.0, 'SEC')
            c.marker(xx, yt, (i + 1).to_s, :right); c.marker(xx, yb, (i + 1).to_s, :right)
          end
          [x, z]
        end

        def note_block(c, m, lines)
          n = m['notes']
          c.text(218.3, 26.6, "DOOR : #{n['DOOR']}", 3.9)
          c.text(218.3, 38.6, "BODY : #{n['BODY']}", 3.9)
          c.text(218.3, 50.6, "손잡이 : #{n['handle']}", 3.9, n['handle'].to_s.include?('확인') ? 'r' : 'k')
          y = 61.0
          lines.each { |t, col| c.text(218.3, y, t, 3.0, col); y += 5.3 }
        end

        def default_notes(m)
          o = m['overall']
          lines = [["*W#{f(o['W'])} x H#{f(o['H'])} x D#{f(o['D'])} (mm) - 도면 입력 치수", 'k']]
          lines << ["*EP = 마감판 #{m['ep']['thickness'].round}T (측판·천판) / 몸통 18T / 도어 20T", 'b'] if has_ep?(m)
          lines << ['*목찬넬 60*40 : 전판 상단(천판 하단 25 이격) (확인필요)', 'r'] if m['channel']
          lines << ['*선반 18T · 뒷판 9T · 서랍 레일 13*2 (일반 기준, 추정)', 'k']
          m['flags'].first(5).each { |t| lines << ["*#{t}", 'r'] }
          lines << ["*단면 #{cut_list(m).size > 1 ? '1~2' : '1'} : SIDE VIEW 시트 / 확인 목록 : 생산 확인표", 'k']
          lines
        end

        # ── 가구 시트 1: TOP VIEW / NOTE / FRONT DOOR / FRONT BODY (+ 키플랜) ─
        def furniture(m, info)
          den = info[:scale] || Model.pick_scale(m)
          info = info.merge(scale: den)
          s = 1.0 / den
          c = Canvas.new('furniture', title: info[:subject])
          c.meta[:den] = den
          Frame.furniture(c, info)
          o = m['overall']
          c.group('KEYPLAN') { keyplan(c, m) }
          ox = 50.0; oy = 50.0
          c.group('VIEW_TOP') do
            draw_plan(c, m, ox, oy, s)
            plan_dims(c, m, ox, oy, s)
            plan_markers(c, m, ox, oy, s)
          end
          c.group('NOTE') { note_block(c, m, default_notes(m)) }
          gy = [124.2 + 26.0 + o['H'] * s, 262.0].min
          c.group('VIEW_FRONT_DOOR') do
            draw_door_view(c, m, 30.0, gy, s)
            c.marker(30.0 + o['W'] * s / 2, gy + 10.0, 'A', :up)
            c.text(30.0, gy + 19.0, '도어 20T / 전판 간격 3 / 걸레받이 (추정)', 2.0, 'b')
          end
          c.group('VIEW_FRONT_BODY') do
            draw_body_view(c, m, 240.0, gy, s)
            c.marker(240.0 + o['W'] * s / 2, gy + 10.0, 'A', :up)
            c.text(240.0, gy + 19.0, '몸통 18T · 칸막이 18T · 선반 18T · 뒷판 9T (추정)', 2.0, 'b')
          end
          c
        end

        # ── 가구 시트 2: 좌·우 측면도 + 단면 1~2 ───────────────────────────
        def side(m, info)
          den = info[:scale] || Model.pick_scale(m)
          o = m['overall']; d = o['D']; k = o['kick']
          den_top = [den, (o['H'] / 62.0).ceil].max            # 상단 구획(높이 ~70mm)에 들어가도록 측면도 축척을 키움
          info = info.merge(scale: den_top)
          s = 1.0 / den_top                                     # 시트 전체(측면도+단면)를 같은 축척 → DXF 1:1 유지
          cuts = cut_list(m)
          c = Canvas.new('side', title: info[:subject])
          c.meta[:den] = den_top
          Frame.furniture(c, info, hdr: 'SIDE VIEW (LEFT / RIGHT)',
                          hdr2: cuts.size > 1 ? ['SECTION 1  (단면)', 'SECTION 2  (단면)'] : ['SECTION 1  (단면)', 'SECTION 1  (구성)'])
          c.group('NOTE') { note_block(c, m, [['*C = 좌측면 / D = 우측면 (전면 = 오른쪽/왼쪽 화살표)', 'k'],
                            ["*단면 #{cuts.size > 1 ? '1~2' : '1'} : TOP VIEW · 정면 BODY 절단선과 연결", 'k']] + default_notes(m).drop(1).first(3)) }
          gy = 30.0 + o['H'] * s + 12.0
          body = o['H'] - o['top_thickness']
          [[48.0, false], [140.0, true]].each_with_index do |(ox, flip), idx|
           c.group(flip ? 'VIEW_SIDE_RIGHT' : 'VIEW_SIDE_LEFT') do
            yx = ->(v) { flip ? ox + (d - v) * s : ox + v * s }
            zz = ->(v) { gy - v * s }
            a, b = [yx.call(0), yx.call(d)].sort
            c.rect(a, zz.call(o['H']), b, zz.call(body), 'OUT') if o['top_thickness'] > 0
            ep_here = idx.zero? ? m['ep']['left'] : m['ep']['right']
            if ep_here then c.ep_rect(a, zz.call(body), b, zz.call(k), 0.5) else c.rect(a, zz.call(body), b, zz.call(k), 'OUT') end
            if k > 0
              p1, p2 = [yx.call(60), yx.call(d - 60)].sort
              c.rect(p1, zz.call(k), p2, zz.call(0), 'OUT')
            end
            c.dim_v(a - 6.0, [zz.call(o['H']), zz.call(0)], [f(o['H'])], ref: a)
            c.dim_h([a, b], zz.call(o['H']) - 8.0, [f(d)], ref: zz.call(o['H']))
            c.marker((a + b) / 2, gy + 16.0, flip ? 'D' : 'C', :up)
            # 전면 방향: 도면 정면(앞)은 평면 아래쪽 = 측면도에서 오른쪽(좌측면) / 왼쪽(우측면)
            c.block_arrow(flip ? a + 2 : b - 2, gy + 9.0, 7.0, flip ? :left : :right)
            c.shaded_label(flip ? a + 9.0 : b - 9.0, gy + 10.0, '전면', 2.2, flip ? 'l' : 'r')
           end
          end
          if cuts.size > 1
            c.group('SECTION_1') { draw_section(c, m, 70.0, 222.0, s, cuts[0], 1) }
            c.group('SECTION_2') { draw_section(c, m, 270.0, 222.0, s, cuts[1], 2) }
          else
            c.group('SECTION_1') { draw_section(c, m, 70.0, 222.0, s, cuts[0], 1) }
            c.group('SECTION_1_SPEC') { section_spec(c, m, 240.0, 150.0) }
          end
          c
        end

        def section_spec(c, m, x0, y0)
          o = m['overall']
          rows = ["몸통(측판·상하판) 18T / 칸막이 18T", '뒷판 9T (홈 또는 맞댐 / 확인필요)', '도어·서랍 전판 20T, 전판 간격 3',
                  "선반 18T (핀 간격 96 추정) / 걸레받이 H#{f(o['kick'])}", m['channel'] ? '목찬넬 60*40 (상세 쪽 참조)' : '손잡이: 노트 참조']
          rows.each_with_index { |t, i| c.text(x0, y0 + i * 7.0, "· #{t}", 2.8, i == 4 ? 'b' : 'k') }
        end

        def draw_section(c, m, ox, gy, s, cx, num)
          o = m['overall']; d = o['D']; k = o['kick']
          body = o['H'] - o['top_thickness']
          x = ->(v) { ox + v * s }
          z = ->(v) { gy - v * s }
          c.rect(x.call(0), z.call(o['H']), x.call(d), z.call(body), 'OUT') if o['top_thickness'] > 0
          c.rect(x.call(DT), z.call(body), x.call(d - BACK_T), z.call(k), 'OUT')
          c.rect(x.call(d - BACK_T), z.call(body), x.call(d), z.call(k), 'THIN')             # 뒷판 9T
          c.rect(x.call(DT), z.call(body - BT), x.call(d - BACK_T), z.call(body), 'THIN')    # 상판 18T
          c.rect(x.call(DT), z.call(k), x.call(d - BACK_T), z.call(k + BT), 'THIN')          # 하판 18T
          c.rect(x.call(0), z.call(body - EP - (m['channel'] ? CH_GAP : 4)), x.call(DT), z.call(k + 4), 'OUT')   # 도어 20T
          if m['channel']
            xb = DT; zc = body - EP
            pts = [[xb + 22, zc], [xb + 40, zc], [xb + 40, zc - CH_H], [xb, zc - CH_H], [xb, zc - CH_H + 18], [xb + 22, zc - CH_H + 18]]
            c.poly(pts.map { |a, b| [x.call(a), z.call(b)] }, 'OUT', true)
            c.ep_rect(x.call(0), z.call(body), x.call(d), z.call(body - EP), 0.5)
          end
          c.rect(x.call(60), z.call(k), x.call(d - 60), z.call(0), 'OUT') if k > 0
          mid = m['modules'].find { |md| md['x'] <= cx && cx < md['x'] + md['w'] } || m['modules'].first
          if mid
            mid['shelves'].each { |sh| zz = mid['z'] + sh; c.rect(x.call(DT), z.call(zz + 9), x.call(d - 29), z.call(zz - 9), 'OUT') }
            mid['rods'].each { |rr| c.circ(x.call(d / 2), z.call(mid['z'] + rr), [14 * s, 0.7].max, 'OUT') }
            if mid['type'] == 'drawers'
              fronts_for(m, mid).each { |z0, _z1| c.rect(x.call(DT + 13), z.call(z0 + 140), x.call(DT + [500, d - 80].min), z.call(z0 + 30), 'THIN') }
            end
            c.rect(x.call(DT + 10), z.call(mid['z'] + mid['h'] - 5), x.call(d - 30), z.call(mid['z'] + 5), 'RED') if mid['type'] == 'appliance'
          end
          c.dim_h([x.call(0), x.call(d)], z.call(o['H']) - 8.0, [f(d)], ref: z.call(o['H']))
          c.dim_v(x.call(0) - 6.0, [z.call(o['H']), z.call(0)], [f(o['H'])], ref: x.call(0))
          c.text(x.call(0), z.call(0) + 8.0, '전면 (도어 쪽)', 2.2, 'k', 'l')
          c.text(x.call(d), z.call(0) + 8.0, '후면 (벽 쪽)', 2.2, 'k', 'r')
          mx = (x.call(0) + x.call(d)) / 2
          c.marker(mx, z.call(0) + 18.0, num.to_s, :right)
          c.text(mx + 8, z.call(0) + 19.2, "SECTION #{num}  (X=#{f(cx)}, 추정 위치)", 2.4, 'k', 'l')
        end

        # ── 상세: EP 20T 평면 + 목찬넬 단면 ───────────────────────────────
        def detail(m, info)
          info = info.merge(scale: nil)
          c = Canvas.new('detail', title: info[:subject])
          Frame.furniture(c, info, hdr: 'DETAIL', hdr2: ['DETAIL', 'DETAIL'])
          c.group('NOTE') do
            note_block(c, m, [["*EP = 마감판 #{m['ep']['thickness'].round}T / 몸통 18T / 도어 20T", 'b']] +
                             (m['channel'] ? [['*목찬넬 60*40 = 손잡이 (확인필요, 기본값)', 'r']] : []))
            c.text(17.0, 28.0, "※ EP 위치는 도면의 'EP 판넬 [..T]' 라벨 기준(추정)", 2.6, 'r')
          end
          c.group('DETAIL_1') do
            c.detail_title(17.0, 139.0, 1, '측판 EP 상세 - 평면 (1/5)')
            edge_ep_plan(c, m, 60.0, 160.0, 0.2)
          end
          if m['channel']
           c.group('DETAIL_2') do
            c.detail_title(218.3, 139.0, 2, '목찬넬 상세 - 측면 (1/2)')
            edge_section(c, 262.0, 178.0, 0.5, 60, 62, true)
            c.shaded_label(240.0, 232.0, '전면 (도어 쪽)', 2.4)
            c.shaded_label(330.0, 232.0, '후면 (벽 쪽)', 2.4, 'r')
            c.text(232.0, 244.0, '파랑 치수 : 25 = 천판 하단~도어 상단 / 60 = 찬넬 높이', 2.0, 'b')
            c.text(232.0, 248.0, '40 = 도어 뒷면~찬넬 뒷면 / 20 = 도어 두께 / 손 진입 : 도어 위 25 틈', 2.0, 'b')
           end
          else
            c.text(218.3, 145.0, '목찬넬 없음 (지정 손잡이 사양은 NOTE 참조)', 3.0, 'g')
          end
          c
        end

        def edge_ep_plan(c, m, x0, y0, sc)
          xr = m['overall']['W']
          x = ->(v) { x0 + (v - (xr - 300)) * sc }
          y = ->(v) { y0 + v * sc }
          c.ep_rect(x.call(xr - EP), y.call(0), x.call(xr), y.call(300), 0.9)
          c.rect(x.call(xr - EP - BT), y.call(DT), x.call(xr - EP), y.call(300), 'OUT')
          c.rect(x.call(xr - 300), y.call(0), x.call(xr - EP), y.call(DT), 'OUT')
          c.dashed(x.call(xr - 300), y.call(300), x.call(xr), y.call(300), 'THIN')
          c.dim_h([x.call(xr - EP - BT), x.call(xr - EP), x.call(xr)], y.call(300) + 7, %w[18 20], ref: y.call(300))
          c.dim_v(x.call(xr - 300) - 6, [y.call(0), y.call(DT)], ['20'], ref: x.call(xr - 300))
          c.blue_leader(x.call(xr) + 6, y.call(55), x.call(xr - EP / 2), y.call(55), '측판 EP 20T (바깥쪽)')
          c.blue_leader(x.call(xr) + 6, y.call(150), x.call(xr - EP - BT / 2), y.call(150), '몸통 측판 18T (안쪽)')
          c.blue_leader(x.call(xr - 110), y.call(0) - 8, x.call(xr - 110), y.call(DT / 2), '도어 20T (전면)')
          c.block_arrow(x.call(xr - 300) + 5, y.call(0) - 3.0, 10.0, :up)
          c.shaded_label(x.call(xr - 300) + 9.0, y.call(0) - 6.0, '전면 (도어 쪽)', 2.6)
          c.line(x.call(xr - 300), y.call(DT + 18), x.call(xr - EP - BT), y.call(DT + 18), 'THIN')
          c.text(x.call(xr - 70), y.call(300) - 1.5, '(이하 생략)', 1.8, 'g', 'c')
          c.block_arrow(x.call(xr - 300) + 5, y.call(300) - 12.0, 9.0, :down)
          c.shaded_label(x.call(xr - 300) + 9.0, y.call(300) - 5.5, '후면 (벽 쪽)', 2.4)
          c.arrow(x.call(xr - 40), y.call(300) + 17.0, x.call(xr - 40) - 14.0, y.call(300) + 17.0, '가구 안쪽', 2.0, 'l', -1.0, 0.8)
          c.text(x.call(xr - 40) + 1.5, y.call(300) + 17.8, '바깥(우단)', 2.0, 'k', 'l')
          c.text(x.call(xr - 300), y.call(300) + 24.0, '위치: 가구 우단 앞쪽 모서리 / 위 = 전면(도어), 오른쪽 = 바깥(EP 마감면)', 2.0, 'k')
          ly = y.call(300) + 31.0
          c.hatch_rect(x.call(xr - 300), ly - 2.4, x.call(xr - 300) + 8.0, ly, 0.5); c.rect(x.call(xr - 300), ly - 2.4, x.call(xr - 300) + 8.0, ly, 'OUT')
          c.text(x.call(xr - 300) + 11.0, ly, "해칭 = 측판 EP #{EP.round}T (마감판)", 2.0, 'k', 'l')
          c.rect(x.call(xr - 300) + 66.0, ly - 2.4, x.call(xr - 300) + 74.0, ly, 'OUT')
          c.text(x.call(xr - 300) + 77.0, ly, '실선 사각 = 18T 몸통 / 20T 도어', 2.0, 'k', 'l')
        end

        # 천판 EP 하단(z=0) 기준 목찬넬 측면 단면: 전면 = 왼쪽
        def edge_section(c, x0, y0, sc, door_len, xmax, dims)
          x = ->(v) { x0 + v * sc }
          y = ->(v) { y0 + v * sc }
          c.ep_rect(x.call(0), y.call(-EP), x.call(xmax), y.call(0), 0.7)
          c.rect(x.call(0), y.call(CH_GAP), x.call(DT), y.call(CH_GAP + door_len), 'OUT')
          pts = [[42, 0], [60, 0], [60, CH_H], [DT, CH_H], [DT, CH_H - 18], [42, CH_H - 18]]
          c.poly(pts.map { |a, b| [x.call(a), y.call(b)] }, 'OUT', true)
          ay = y.call(12)
          c.line(x.call(-3), ay, x.call(38), ay, 'BLUE')
          c.fill([[x.call(38), ay], [x.call(38) - 1.6, ay - 0.8], [x.call(38) - 1.6, ay + 0.8]], [0, 0, 255])
          c.text(x.call(2), ay - 1.4, '손 진입', 2.0, 'b')
          return unless dims
          bx = x.call(60) + 4
          c.line(bx, y.call(0), bx, y.call(CH_H), 'BLUE')
          c.text(bx + 2.8, (y.call(0) + y.call(CH_H)) / 2, '60', 2.4, 'b', 'c', 90)
          lx = x.call(-14)
          c.line(lx, y.call(0), lx, y.call(CH_GAP), 'BLUE')
          c.text(lx - 0.8, (y.call(0) + y.call(CH_GAP)) / 2, '25', 2.4, 'b', 'c', 90)
          by = y.call(CH_H) + 3
          c.line(x.call(DT), by, x.call(60), by, 'BLUE')
          c.text((x.call(DT) + x.call(60)) / 2, by + 3.4, '40', 2.4, 'b', 'c')
          c.text(x.call(DT / 2), y.call(CH_GAP + door_len) + 3.2, '20', 2.0, 'b', 'c')
        end

        # ── 평면도(공간 + 가구 배치) ──────────────────────────────────────
        def floor(m, info)
          o = m['overall']; room = m['room']
          den = info[:scale] || [20, 25, 30, 40, 50].find { |dd| room['W'] / dd <= 270 && room['D'] / dd <= 185 } || 50
          info = info.merge(scale: den)
          s = 1.0 / den
          c = Canvas.new('floor', title: info[:subject])
          c.meta[:den] = den
          Frame.plan(c, info, room['name'], "#{room['name']} #{m['furniture_name']} 평면도")
          c.group('VIEW_PLAN') do
          wt = 150.0
          ox = 62.0; oy = 62.0
          x = ->(v) { ox + v * s }
          y = ->(v) { oy + v * s }
          [[-wt, -wt, room['W'] + wt, 0], [-wt, room['D'], room['W'] + wt, room['D'] + wt], [room['W'], 0, room['W'] + wt, room['D']], [-wt, 0, 0, room['D']]].each do |a, b, cc, dd|
            c.rect(x.call(a), y.call(b), x.call(cc), y.call(dd), 'OUT')
            c.hatch_rect(x.call(a), y.call(b), x.call(cc), y.call(dd))
          end
          ix = (room['W'] - o['W']) / 2.0
          iy = 0.0
          draw_plan(c, m, x.call(ix), y.call(iy), s)
          c.dim_h([x.call(ix), x.call(ix + o['W'])], y.call(iy) + o['D'] * s + 8, [f(o['W'])], ref: y.call(iy) + o['D'] * s)
          c.dim_v(x.call(ix) - 6, [y.call(iy), y.call(iy + o['D'])], [f(o['D'])], ref: x.call(ix))
          c.dim_h([x.call(0), x.call(room['W'])], y.call(-wt) - 6.0, [f(room['W'])], ref: y.call(-wt))
          c.dim_v(x.call(room['W'] + wt) + 7.0, [y.call(0), y.call(room['D'])], [f(room['D'])], ref: x.call(room['W'] + wt), side: 1)
          c.marker(x.call(ix + o['W'] / 2), y.call(iy + o['D']) + 22.0, 'A', :up)
          c.marker(x.call(ix) - 22.0, y.call(o['D'] / 2), 'C', :right)
          c.marker(x.call(ix + o['W']) + 22.0, y.call(o['D'] / 2), 'D', :left)
          c.text(x.call(room['W']) - 3, y.call(room['D']) - 3, '※ 공간 규격은 가정(확인필요)', 2.2, 'r', 'r')
          end
          c
        end

        # ── 생산 확인표 ────────────────────────────────────────────────────
        DEFAULT_TABLE = [
          ['도어 재질·색상', '목림 지정 자재 / 안도크림 색상 (샘플 문구)', '지정 자재 확인'],
          ['손잡이', '목찬넬 60*40 또는 지정 손잡이 (기본값)', '손잡이 사양 확인'],
          ['EP 20T 위치', '측판 양단·천판 (추정)', '원본 도면 EP 지시 대조'],
          ['서랍 레일', '좌우 13 여유, 레일 길이 = 깊이에 맞춤 (추정)', '레일 제품 규격 확인'],
          ['뒷판·후면 마감', '뒷판 9T (추정)', '후면 마감 사양 확인'],
          ['선반', '18T, 핀 간격 96 (추정)', '선반 위치 확정'],
          ['콘센트·배선 타공', 'Φ60~80, 위치 미정', '전기 도면 확인'],
          ['공간 규격', '평면도 공간은 가정치', '현장 실측']
        ].freeze

        def table(m, info, rows = nil)
          rows = (rows.nil? || rows.empty?) ? (m['table_rows'] + m['flags'].map { |t| [t, '도면에서 읽지 못함/추정', '확인 필요'] } + DEFAULT_TABLE) : rows
          c = Canvas.new('table', title: info[:subject])
          Frame.table(c, info, '생산 확인표')
          cols = [[15.0, 14.0, '번호'], [29.0, 62.0, '항목'], [91.0, 170.0, '현재 가정값'], [261.0, 140.0, '확인 방법']]
          y0 = 34.0; hh = 9.0
          rh = [[(255.0 - hh) / rows.size, 12.4].min, 7.0].max
          xe = 401.0
          c.rect(15.0, y0, xe, y0 + hh + rh * rows.size, 'SEC')
          c.fill([[15.0, y0], [xe, y0], [xe, y0 + hh], [15.0, y0 + hh]], [85, 85, 85])
          cols.each { |x, _w, t| c.text(x + 2.0, y0 + 6.2, t, 3.6, 'w') }
          cols.drop(1).each { |x, _w, _t| c.line(x, y0, x, y0 + hh + rh * rows.size, 'FR') }
          rows.each_with_index do |(a, b, cc), i|
            y = y0 + hh + i * rh
            c.line(15.0, y + rh, xe, y + rh, 'FR') if i < rows.size - 1
            c.text(cols[0][0] + 7.0, y + rh / 2 + 1.2, (i + 1).to_s, 3.4, 'k', 'c')
            [[cols[1], a, 'k'], [cols[2], b, 'r'], [cols[3], cc, 'b']].each do |(col, txt, color)|
              c.text(col[0] + 2.0, y + rh / 2 + 1.2, txt, 3.3, color)
            end
          end
          c
        end

        # ── 사진/3D 격자 페이지 ───────────────────────────────────────────
        # items: [{ 'path'=>, 'caption'=>, 'pw'=>px, 'ph'=>px }]
        def grid_cols_rows(n)
          case n
          when 0, 1 then [1, 1]
          when 2 then [2, 1]
          when 3, 4 then [2, 2]
          else [3, 2]
          end
        end

        def image_page(info, header, items, name: 'photos')
          c = Canvas.new(name, title: info[:subject])
          Frame.simple(c, info.merge(scale: nil), header)
          cols, rows = grid_cols_rows(items.size)
          ax0 = 14.0; ay0 = 22.0; ax1 = 406.0; ay1 = 264.0
          gap = 4.0
          cw = (ax1 - ax0 - gap * (cols - 1)) / cols
          ch = (ay1 - ay0 - gap * (rows - 1)) / rows
          items.each_with_index do |it, i|
            col = i % cols; row = i / cols
            cx = ax0 + col * (cw + gap); cy = ay0 + row * (ch + gap)
            capH = 7.0
            bw = cw; bh = ch - capH
            pw = it['pw'].to_f; ph = it['ph'].to_f
            if pw > 0 && ph > 0
              r = [bw / pw, bh / ph].min
              iw = pw * r; ih = ph * r
            else
              iw = bw; ih = bh
            end
            ix = cx + (bw - iw) / 2; iy = cy + (bh - ih) / 2
            c.rect(cx, cy, cx + bw, cy + bh, 'FR')
            c.image(ix, iy, iw, ih, it['path'])
            c.rect(ix, iy, ix + iw, iy + ih, 'IMG')
            c.text(cx + bw / 2, cy + bh + 5.0, it['caption'], 3.6, 'k', 'c')
          end
          c
        end
      end
    end
  end
end
