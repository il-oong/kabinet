module Kabinet
  module Core
    # ── 주방 상판 평면 계산 (순수 계산, mm Float) ───────────────────────────
    #
    # 선택한 하부장들의 평면 사각형(공통 좌표계, 도어 앞면 포함)을 받아
    # 앞 돌출 · 노출된 옆면 돌출 · 뒤 여유를 붙인 뒤 합쳐서 상판 평면을 만든다.
    # 일자·ㄱ자·ㄷ자처럼 90° 단위로 꺾인 배치를 하나의 상판으로 잇는다.
    #
    # item: { rect: [x0, y0, x1, y1], front: [fx, fy] (±1,0 / 0,±1), top: z_mm }
    # 반환: { cells: [[x0, y0, x1, y1], ...] (겹침 없는 사각형 조각), top: z_mm, warnings: [] }
    module Countertop
      class Error < StandardError; end

      module_function

      TOUCH_MM = 5.0      # 이 거리 이내로 붙어 있으면 이웃 가구로 본다
      TOP_DIFF_MM = 5.0   # 윗면 높이 차가 이보다 크면 경고

      def plan(items, front_overhang: 20.0, side_overhang: 0.0, back_gap: 0.0)
        raise Error, '상판을 놓을 가구를 선택하세요.' if items.nil? || items.empty?
        warnings = []
        tops = items.map { |it| it[:top].to_f }
        if tops.max - tops.min > TOP_DIFF_MM
          warnings << "선택한 가구 윗면 높이가 다릅니다 (#{tops.min.round}~#{tops.max.round}mm). 가장 높은 면에 맞춥니다."
        end

        rects = items.each_with_index.map do |it, i|
          x0, y0, x1, y1 = it[:rect].map(&:to_f)
          fx, fy = it[:front]
          # 앞(+), 뒤(-) 확장
          x0, x1 = grow(x0, x1, fx, front_overhang.to_f, -back_gap.to_f)
          y0, y1 = grow(y0, y1, fy, front_overhang.to_f, -back_gap.to_f)
          # 옆(앞 방향과 수직) — 다른 가구와 붙어 있지 않은 쪽만
          side_axis = fx.zero? ? 0 : 1
          [-1, 1].each do |s|
            next if neighbor?(items, i, side_axis, s)
            if side_axis.zero?
              s < 0 ? x0 -= side_overhang.to_f : x1 += side_overhang.to_f
            else
              s < 0 ? y0 -= side_overhang.to_f : y1 += side_overhang.to_f
            end
          end
          [x0, y0, x1, y1]
        end

        { cells: union_cells(rects), top: tops.max, warnings: warnings }
      end

      # 앞쪽 방향 성분(f)에 따라 앞을 front만큼, 뒤를 back만큼 늘린다 (음수면 줄임)
      def grow(lo, hi, f, front, back)
        return [lo, hi] if f.zero?
        f > 0 ? [lo - back, hi + front] : [lo - front, hi + back]
      end

      # i번째 가구의 (축 axis, 방향 s) 옆면에 다른 가구가 붙어 있는가
      def neighbor?(items, i, axis, s)
        r = items[i][:rect].map(&:to_f)
        lo = [r[0], r[1]]
        hi = [r[2], r[3]]
        edge = s < 0 ? lo[axis] : hi[axis]
        o = 1 - axis
        items.each_with_index.any? do |other, j|
          next false if j == i
          q = other[:rect].map(&:to_f)
          qlo = [q[0], q[1]]
          qhi = [q[2], q[3]]
          touches = s < 0 ? (qhi[axis] - edge).abs <= TOUCH_MM || (qlo[axis] < edge && qhi[axis] > edge) :
                            (qlo[axis] - edge).abs <= TOUCH_MM || (qlo[axis] < edge && qhi[axis] > edge)
          touches && qlo[o] < hi[o] - TOUCH_MM && qhi[o] > lo[o] + TOUCH_MM
        end
      end

      # 사각형들의 합집합을 겹치지 않는 격자 조각으로 (가로로 이어지는 조각은 합침)
      def union_cells(rects)
        xs = rects.flat_map { |r| [r[0], r[2]] }.uniq.sort
        ys = rects.flat_map { |r| [r[1], r[3]] }.uniq.sort
        cells = []
        (0...ys.size - 1).each do |j|
          cy = (ys[j] + ys[j + 1]) / 2.0
          run = nil
          (0...xs.size - 1).each do |i|
            cx = (xs[i] + xs[i + 1]) / 2.0
            covered = rects.any? { |r| cx > r[0] && cx < r[2] && cy > r[1] && cy < r[3] }
            if covered
              run ||= xs[i]
            elsif run
              cells << [run, ys[j], xs[i], ys[j + 1]]
              run = nil
            end
          end
          cells << [run, ys[j], xs[-1], ys[j + 1]] if run
        end
        cells
      end
    end
  end
end
