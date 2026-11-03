require_relative 'text'
require_relative 'styles'
module Kabinet
  module Output
    module Sheet
      # 한 장(A3 가로)의 그리기 모델. 좌표: mm, 좌상단 원점, y 아래로.
      # 항목: [:L, x1,y1,x2,y2,st] [:P, pts,st,closed] [:C, cx,cy,r,st] [:F, pts,rgb] [:H, pts,st,step](해칭)
      #       [:T, x,y,str,size,color,align,rot] [:I, x,y,w,h,path,id]
      class Canvas
        attr_reader :name, :items, :meta
        attr_accessor :title

        def initialize(name, title: nil)
          @name = name
          @title = title || name
          @items = []
          @meta = {}
        end

        def line(x1, y1, x2, y2, st = 'OUT'); @items << [:L, x1, y1, x2, y2, st]; end
        def poly(pts, st = 'OUT', closed = false); @items << [:P, pts, st, closed]; end
        def rect(x1, y1, x2, y2, st = 'OUT'); poly([[x1, y1], [x2, y1], [x2, y2], [x1, y2]], st, true); end
        def circ(cx, cy, r, st = 'OUT'); @items << [:C, cx, cy, r, st]; end
        def fill(pts, rgb); @items << [:F, pts, rgb]; end
        def text(x, y, str, size = 2.4, c = 'k', a = 'l', rot = 0)
          str = Text.utf8(str)
          @items << [:T, x, y, str, size, c, a, rot] unless str.empty?
        end
        # 이미지 자리(DXF IMAGE 로 출력). (x,y)=좌상단, w,h mm
        def image(x, y, w, h, path)
          @items << [:I, x, y, w, h, path]
        end

        def dashed(x1, y1, x2, y2, st = 'THIN', d = 1.6, g = 0.9)
          len = Math.hypot(x2 - x1, y2 - y1)
          return if len < 1e-6
          ux = (x2 - x1) / len; uy = (y2 - y1) / len
          t = 0.0
          while t < len
            e = [t + d, len].min
            line(x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e, st)
            t = e + g
          end
        end

        # 긴 쇄선(절단선)
        def chain(x1, y1, x2, y2, st = 'FR', seg = [8.0, 1.4, 0.8, 1.4])
          len = Math.hypot(x2 - x1, y2 - y1)
          return if len < 1e-6
          ux = (x2 - x1) / len; uy = (y2 - y1) / len
          t = 0.0; k = 0
          while t < len
            e = [t + seg[k % 4], len].min
            line(x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e, st) if k.even?
            t = e; k += 1
          end
        end

        def rrect(x1, y1, x2, y2, r, st = 'OUT')
          pts = []
          [[x2 - r, y1 + r, -90], [x2 - r, y2 - r, 0], [x1 + r, y2 - r, 90], [x1 + r, y1 + r, 180]].each do |cx, cy, a0|
            7.times do |k|
              a = (a0 + 90.0 * k / 6) * Math::PI / 180
              pts << [cx + r * Math.cos(a), cy + r * Math.sin(a)]
            end
          end
          poly(pts, st, true)
        end

        # 닫힌 사각 안을 45° 해칭 — DXF 에서는 HATCH(ANSI31) 엔티티. step = 종이 mm 간격
        def hatch_rect(x1, y1, x2, y2, step = 1.6, st = 'HATCH')
          @items << [:H, [[x1, y1], [x2, y1], [x2, y2], [x1, y2]], st, step]
        end

        # EP 20T 판 — 해칭 + 외곽
        def ep_rect(x1, y1, x2, y2, step = 0.5)
          hatch_rect(x1, y1, x2, y2, step)
          rect(x1, y1, x2, y2, 'OUT')
        end

        # ── 치수 ─────────────────────────────────────────────────────────
        DSZ = 2.4

        def dim_h(xs, y, labels, ref: nil, size: DSZ)
          sgn = ref.nil? ? 0 : (y > ref ? 1 : -1)
          xs.each do |x|
            line(x, ref + sgn * 0.8, x, y + sgn * 1.2, 'DIM') unless ref.nil?
            line(x - 0.7, y + 0.7, x + 0.7, y - 0.7, 'DIMT')
          end
          line(xs.first - 0.8, y, xs.last + 0.8, y, 'DIM')
          n = labels.size
          labels.each_with_index do |lab, i|
            a1 = xs[i]; a2 = xs[i + 1]
            w = Sheet.text_width(lab, size)
            if a2 - a1 >= w + 0.8
              text((a1 + a2) / 2, y - 0.8, lab, size, 'k', 'c')
            else
              cx = (i.zero? && n > 1) ? a1 - 0.8 - w / 2 : a2 + 0.8 + w / 2
              text(cx, y - 0.8, lab, size, 'k', 'c')
            end
          end
        end

        def dim_v(x, ys, labels, ref: nil, size: DSZ, side: -1)
          sgn = ref.nil? ? 0 : (x > ref ? 1 : -1)
          ys.each do |y|
            line(ref + sgn * 0.8, y, x + sgn * 1.2, y, 'DIM') unless ref.nil?
            line(x - 0.7, y + 0.7, x + 0.7, y - 0.7, 'DIMT')
          end
          line(x, ys.first - 0.8, x, ys.last + 0.8, 'DIM')
          xx = side < 0 ? x - 0.8 : x + 0.8 + size * 0.75
          labels.each_with_index do |lab, i|
            a1 = ys[i]; a2 = ys[i + 1]
            w = Sheet.text_width(lab, size)
            cy = (a2 - a1 >= w + 0.8) ? (a1 + a2) / 2 : a2 + 0.8 + w / 2
            text(xx, cy, lab, size, 'k', 'c', 90)
          end
        end

        # 단면/입면 방향 마커: 원 + 삼각형 + 'A / ELE'
        def marker(cx, cy, label, direction = :up, r = 3.3)
          circ(cx, cy, r, 'OUT')
          text(cx, cy + 0.9, label, 2.6, 'k', 'c')
          text(cx, cy + 2.2, 'ELE', 1.1, 'k', 'c')
          t = 2.6
          pts = case direction
                when :up    then [[cx - 2.4, cy - r], [cx + 2.4, cy - r], [cx, cy - r - t]]
                when :down  then [[cx - 2.4, cy + r], [cx + 2.4, cy + r], [cx, cy + r + t]]
                when :left  then [[cx - r, cy - 2.4], [cx - r, cy + 2.4], [cx - r - t, cy]]
                else             [[cx + r, cy - 2.4], [cx + r, cy + 2.4], [cx + r + t, cy]]
                end
          fill(pts, [0, 0, 0])
        end

        # 가는 화살표 + 글자 (x2,y2 = 화살촉 쪽)
        def arrow(x1, y1, x2, y2, label, size = 2.2, a = 'l', dx = 1.5, dy = 0.8)
          line(x1, y1, x2, y2, 'OUT')
          len = Math.hypot(x2 - x1, y2 - y1)
          return if len < 1e-6
          ux = (x2 - x1) / len; uy = (y2 - y1) / len
          fill([[x2, y2], [x2 - ux * 2.2 - uy * 0.9, y2 - uy * 2.2 + ux * 0.9], [x2 - ux * 2.2 + uy * 0.9, y2 - uy * 2.2 - ux * 0.9]], [0, 0, 0])
          text(x2 + dx, y2 + dy, label, size, 'k', a)
        end

        def block_arrow(x, y, len, dir, th = 1.4)
          dx, dy = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.fetch(dir)
          px = -dy; py = dx
          hx = x + dx * len; hy = y + dy * len
          b = len * 0.45
          fill([[x + px * th / 2, y + py * th / 2], [hx - dx * b + px * th / 2, hy - dy * b + py * th / 2],
                [hx - dx * b + px * th * 1.5, hy - dy * b + py * th * 1.5], [hx, hy],
                [hx - dx * b - px * th * 1.5, hy - dy * b - py * th * 1.5], [hx - dx * b - px * th / 2, hy - dy * b - py * th / 2],
                [x - px * th / 2, y - py * th / 2]], [0, 0, 0])
        end

        def shaded_label(x, y, str, size = 2.4, a = 'l')
          w = Sheet.text_width(str, size) + 2.0
          x0 = a == 'l' ? x - 1.0 : (a == 'c' ? x - w / 2 : x - w + 1.0)
          fill([[x0, y - size * 0.9], [x0 + w, y - size * 0.9], [x0 + w, y + size * 0.35], [x0, y + size * 0.35]], [225, 225, 225])
          text(x0 + 1.0, y, str, size, 'k', 'l')
        end

        def blue_leader(tx, ty, px, py, str, a = 'l', size = 2.0)
          line(tx, ty - size * 0.35, px, py, 'BLUE')
          text(tx, ty, str, size, 'b', a)
        end

        # 상세 제목: 번호 원 + 굵은 글씨 + 굵은 밑줄
        def detail_title(x, y, num, str, size = 3.6)
          circ(x + 3.0, y - 1.3, 3.0, 'OUT')
          text(x + 3.0, y - 0.3, num.to_s, 3.4, 'k', 'c')
          tx = x + 8.0
          [0.0, 0.2].each { |dx| text(tx + dx, y, str, size, 'k', 'l') }
          line(tx, y + 1.8, tx + Sheet.text_width(str, size), y + 1.8, 'SEC')
        end
      end
    end
  end
end
