# 선택 그룹/컴포넌트 → 3면도 투영 — 직접 모델링한 가구의 발주도면용.
#
# 파라메트릭 해석 없이, 스케치업 평행투영 표준 뷰와 동일한 직교투영으로
# 엣지를 2D에 떨어뜨린다.
#
# 기본 출력은 실무 도면에 맞게:
#   - 곡면(soft/smooth) 엣지 제외 — 소파 등 메시 오브젝트의 삼각분할 제거
#   - 은선 제거(HLR) — 뷰 방향 레이캐스트로 가려진 엣지 스킵
#   - 곡면만으로 이뤄진 유닛은 바운딩 박스 외곽으로 대체 표시
#
# 뷰 좌표계 (Drawing2D와 동일, mm):
#   정면도(front): X = 모델 X(폭),  Y = 모델 Z(높이), 뷰어 -Y 쪽
#   측면도(side):  X = 모델 Y(깊이), Y = 모델 Z(높이), 뷰어 +X 쪽
#   평면도(top):   X = 모델 X(폭),  Y = 모델 Y(깊이), 뷰어 +Z 쪽
#
# views_from_segments 는 순수 루비 (SketchUp API 불필요) — 테스트 가능.
# collect_segments_mm / visible_segments / collect_unit_bounds_mm 만
# SketchUp API를 사용한다.
module Kabinet
  module Output
    module GroupProjection
      module_function

      # 뷰별 뷰어 방향 (엣지 → 뷰어로 쏘는 레이 방향)
      VIEW_DIRS = {
        'front' => [0.0, -1.0, 0.0],
        'side'  => [1.0,  0.0, 0.0],
        'top'   => [0.0,  0.0, 1.0]
      }.freeze

      # ── SketchUp 순회: 엣지를 월드 mm 좌표 세그먼트로 수집 ──────────────
      # include_soft: false면 곡면 메시 엣지(soft/smooth/hidden) 제외
      def collect_segments_mm(entity, out, tr = ::Geom::Transformation.new, include_soft: false)
        case entity
        when ::Sketchup::Group
          t = tr * entity.transformation
          entity.entities.each { |e| collect_segments_mm(e, out, t, include_soft: include_soft) }
        when ::Sketchup::ComponentInstance
          t = tr * entity.transformation
          entity.definition.entities.each { |e| collect_segments_mm(e, out, t, include_soft: include_soft) }
        when ::Sketchup::Edge
          return out if !include_soft && (entity.soft? || entity.smooth? || entity.hidden?)
          p1 = entity.start.position.transform(tr)
          p2 = entity.end.position.transform(tr)
          out << [[p1.x.to_mm, p1.y.to_mm, p1.z.to_mm],
                  [p2.x.to_mm, p2.y.to_mm, p2.z.to_mm]]
        end
        out
      end

      # ── 은선 제거 (SketchUp raytest) ─────────────────────────────────────
      # 각 세그먼트 중점에서 뷰어 방향으로 레이 발사 — 뭔가에 막히면 가려진
      # 것으로 보고 제외. 중점 근사(부분 가림은 통째 판정)지만 발주도면엔 충분.
      def visible_segments(model, segs, view_name)
        dir_a = VIEW_DIRS[view_name]
        return segs unless dir_a
        dir = ::Geom::Vector3d.new(*dir_a)
        eps = 0.5 / 25.4   # 0.5mm (인치) — 자기 면 자체 히트 방지 오프셋
        segs.select do |p, q|
          mid = ::Geom::Point3d.new(((p[0] + q[0]) / 2.0) / 25.4,
                                    ((p[1] + q[1]) / 2.0) / 25.4,
                                    ((p[2] + q[2]) / 2.0) / 25.4)
          start = mid.offset(dir, eps)
          model.raytest([start, dir], true).nil?
        end
      end

      # ── 순수 계산: 세그먼트 → 정면/측면/평면 뷰 (OrderSheet 호환 형식) ──
      # segs:      전체 세그먼트 (mm, 월드) — 도면 범위/원점 산출용
      # units:     [{ name:, min:, max: }] — 유닛 분할 치수용 (2개 이상일 때만)
      # view_segs: { 'front' => [...], ... } — 뷰별로 그릴 세그먼트 오버라이드
      #            (은선 제거 결과). nil이면 세 뷰 모두 segs 사용.
      # dim_overall / dim_units: 치수 출력 여부
      def views_from_segments(segs, units: [], view_segs: nil,
                              dim_overall: true, dim_units: true, round_mm: 1.0)
        raise ArgumentError, '선택에 엣지가 없습니다' if segs.empty?

        pts  = segs.flatten(1)
        minx, maxx = pts.map { |p| p[0] }.minmax
        miny, maxy = pts.map { |p| p[1] }.minmax
        minz, maxz = pts.map { |p| p[2] }.minmax
        w = maxx - minx
        d = maxy - miny
        h = maxz - minz

        vs = ->(name) { (view_segs && view_segs[name]) || segs }
        front = view('front', '정면도  FRONT', w, h, project(vs['front'], 0, 2, minx, minz))
        side  = view('side',  '측면도  SIDE',  d, h, project(vs['side'],  1, 2, miny, minz))
        top   = view('top',   '평면도  TOP',   w, d, project(vs['top'],   0, 1, minx, miny))

        off_f = dim_off(w, h)
        if dim_overall
          # 전체 치수 — 제일 바깥
          dim(front, 0, 0, w, 0, -off_f, fmt(w, round_mm), :h)
          dim(front, 0, 0, 0, h, -off_f, fmt(h, round_mm), :v)
          dim(side,  0, 0, d, 0, -dim_off(d, h), fmt(d, round_mm), :h)
          dim(top,   w, 0, w, d, dim_off(w, d),  fmt(d, round_mm), :v)
        end

        if dim_units && units.size >= 2
          add_unit_dims(front, top, units, minx, miny, minz, w, d, h, off_f, round_mm)
        end

        [front, side, top]
      end

      # 유닛(장) 분할 치수:
      #   폭 체인 — 정면도 하단 안쪽 라인 (전체 치수보다 뷰에 가깝게)
      #   높이   — 전체와 다른 값만, 같은 값은 1회, 뷰 우측 바깥에 계단식
      #   깊이   — 전체와 다른 값만, 평면도 우측 바깥에 계단식
      # (이전 버그: 높이/깊이 치수를 유닛 위치에 그대로 그려 뷰 내용과 겹침)
      def add_unit_dims(front, top, units, minx, miny, minz, w, d, h, off_f, round_mm = 1.0)
        inner  = -off_f * 0.55
        sorted = units.sort_by { |u| u[:min][0] }

        sorted.each do |u|
          x1 = u[:min][0] - minx
          x2 = u[:max][0] - minx
          next if (x2 - x1) < 1.0
          dim(front, x1, 0, x2, 0, inner, fmt(x2 - x1, round_mm), :h)
        end

        # 높이: 값별 1회, 뷰 오른쪽 바깥으로 계단식 오프셋
        seen_h = {}
        k = 0
        sorted.each do |u|
          uh = u[:max][2] - u[:min][2]
          next if (uh - h).abs <= 0.5          # 전체 높이와 같으면 생략
          key = fmt(uh, round_mm)
          next if seen_h[key]                  # 같은 높이는 1회만
          seen_h[key] = true
          off = off_f * (0.55 + 0.5 * k)       # 계단식 — 겹침 방지
          dim(front, w, u[:min][2] - minz, w, u[:max][2] - minz, off, key, :v)
          k += 1
        end

        # 깊이: 값별 1회, 평면도 오른쪽 바깥 계단식
        seen_d = {}
        k = 0
        sorted.each do |u|
          ud = u[:max][1] - u[:min][1]
          next if (ud - d).abs <= 0.5
          key = fmt(ud, round_mm)
          next if seen_d[key]
          seen_d[key] = true
          off = dim_off(w, d) * (0.55 + 0.5 * k)
          dim(top, w, u[:min][1] - miny, w, u[:max][1] - miny, off, key, :v)
          k += 1
        end
      end

      # 바운딩 박스 12엣지 세그먼트 (곡면 전용 유닛 대체 표시용)
      def bbox_segments(min, max)
        x0, y0, z0 = min
        x1, y1, z1 = max
        pts = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0],
               [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]]
        [[0, 1], [1, 2], [2, 3], [3, 0],
         [4, 5], [5, 6], [6, 7], [7, 4],
         [0, 4], [1, 5], [2, 6], [3, 7]].map { |a, b| [pts[a], pts[b]] }
      end

      # ── SketchUp 순회: 유닛(장) 분해 수집 ────────────────────────────────
      # 선택이 그룹 1개면 그 안의 하위 그룹/컴포넌트들이 유닛,
      # 여러 개 선택이면 각각이 유닛.
      # 반환: { units: [{ name:, min:, max:, segs: [...] }], loose: [...] }
      #   segs  — 해당 유닛의 (필터 적용된) 엣지 세그먼트
      #   loose — 어느 유닛에도 속하지 않는 최상위 낱개 엣지
      # 호출부에서 segs가 임계값을 넘는 유닛(임포트 메시 소파 등)을
      # bbox_segments로 대체할 수 있게 유닛별로 분리해 준다.
      def collect_units_mm(targets, include_soft: false)
        pairs = []
        loose = []
        if targets.size == 1
          t    = targets.first
          tr   = t.transformation
          ents = t.is_a?(::Sketchup::ComponentInstance) ? t.definition.entities : t.entities
          kids = ents.to_a.select { |e|
            e.is_a?(::Sketchup::Group) || e.is_a?(::Sketchup::ComponentInstance)
          }
          if kids.size >= 2
            pairs = kids.map { |k| [k, tr] }
            ents.each do |e|
              collect_segments_mm(e, loose, tr, include_soft: include_soft) if e.is_a?(::Sketchup::Edge)
            end
          else
            pairs = [[t, ::Geom::Transformation.new]]
          end
        else
          pairs = targets.map { |t| [t, ::Geom::Transformation.new] }
        end

        units = pairs.map { |ent, tr|
          all = collect_segments_mm(ent, [], tr, include_soft: true)
          next if all.empty?
          segs = include_soft ? all : collect_segments_mm(ent, [], tr, include_soft: false)
          pts  = all.flatten(1)
          name = ent.name.to_s
          name = ent.definition.name.to_s if name.empty? && ent.respond_to?(:definition)
          { name: name, segs: segs,
            min: [pts.map { |p| p[0] }.min, pts.map { |p| p[1] }.min, pts.map { |p| p[2] }.min],
            max: [pts.map { |p| p[0] }.max, pts.map { |p| p[1] }.max, pts.map { |p| p[2] }.max] }
        }.compact
        { units: units, loose: loose }
      end

      # 전체 외형 치수 문자열 (표제란용)
      def size_string(segs)
        pts = segs.flatten(1)
        w = pts.map { |p| p[0] }.minmax.reverse.reduce(:-)
        d = pts.map { |p| p[1] }.minmax.reverse.reduce(:-)
        h = pts.map { |p| p[2] }.minmax.reverse.reduce(:-)
        "#{w.round}W x #{d.round}D x #{h.round}H"
      end

      # ── 내부 ─────────────────────────────────────────────────────────────

      # 축 인덱스 (ai, bi)로 투영 + 원점 이동 + 중복/영길이 세그먼트 제거
      def project(segs, ai, bi, o1, o2)
        seen = {}
        segs.each_with_object([]) do |(p, q), acc|
          a = [(p[ai] - o1).round(2), (p[bi] - o2).round(2)]
          b = [(q[ai] - o1).round(2), (q[bi] - o2).round(2)]
          next if a == b                       # 투영 후 점으로 붕괴
          key = [a, b].sort
          next if seen[key]                    # 같은 선 중복 (앞뒤 면 등)
          seen[key] = true
          acc << { x1: a[0], y1: a[1], x2: b[0], y2: b[1], layer: 'OUTLINE' }
        end
      end

      def view(name, label, w, h, lines)
        { name: name, label: label, width: w.to_f, height: h.to_f,
          lines: lines, rects: [], dims: [], texts: [] }
      end

      def dim(v, x1, y1, x2, y2, offset, text, dir)
        v[:dims] << { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f,
                      offset: offset.to_f, text: text.to_s, dir: dir }
      end

      def dim_off(a, b)
        [[a, b].max * 0.06, 80.0].max.round(0)
      end

      # round_mm: 반올림 단위 — 0.1(정밀) / 1 / 5 / 10
      def fmt(val, round_mm = 1.0)
        step = round_mm.to_f
        step = 1.0 if step <= 0
        v = (val.to_f / step).round * step
        v = v.round(1)
        v == v.to_i ? v.to_i.to_s : v.to_s
      end
    end
  end
end
