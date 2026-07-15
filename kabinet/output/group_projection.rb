# 선택 그룹/컴포넌트 → 3면도 투영 — 직접 모델링한 가구의 발주도면용.
#
# 파라메트릭 해석 없이, 스케치업 평행투영 표준 뷰와 동일한 직교투영으로
# 모든 엣지를 2D에 떨어뜨린다 (와이어프레임 — 내부 구조 전부 표시).
#
# 뷰 좌표계 (Drawing2D와 동일, mm):
#   정면도(front): X = 모델 X(폭),  Y = 모델 Z(높이)
#   측면도(side):  X = 모델 Y(깊이), Y = 모델 Z(높이)
#   평면도(top):   X = 모델 X(폭),  Y = 모델 Y(깊이)
#
# views_from_segments 는 순수 루비 (SketchUp API 불필요) — 테스트 가능.
# collect_segments_mm 만 SketchUp 엔티티를 순회한다.
module Kabinet
  module Output
    module GroupProjection
      module_function

      # ── SketchUp 순회: 엣지를 월드 mm 좌표 세그먼트로 수집 ──────────────
      # entity: Group | ComponentInstance | Edge, out: Array (누적)
      def collect_segments_mm(entity, out, tr = ::Geom::Transformation.new)
        case entity
        when ::Sketchup::Group
          t = tr * entity.transformation
          entity.entities.each { |e| collect_segments_mm(e, out, t) }
        when ::Sketchup::ComponentInstance
          t = tr * entity.transformation
          entity.definition.entities.each { |e| collect_segments_mm(e, out, t) }
        when ::Sketchup::Edge
          p1 = entity.start.position.transform(tr)
          p2 = entity.end.position.transform(tr)
          out << [[p1.x.to_mm, p1.y.to_mm, p1.z.to_mm],
                  [p2.x.to_mm, p2.y.to_mm, p2.z.to_mm]]
        end
        out
      end

      # ── 순수 계산: 세그먼트 → 정면/측면/평면 뷰 (OrderSheet 호환 형식) ──
      # segs: [[[x,y,z],[x,y,z]], ...] (mm)
      # 반환: [front_view, side_view, top_view] + 전체 치수 포함
      def views_from_segments(segs)
        raise ArgumentError, '선택에 엣지가 없습니다' if segs.empty?

        pts  = segs.flatten(1)
        minx, maxx = pts.map { |p| p[0] }.minmax
        miny, maxy = pts.map { |p| p[1] }.minmax
        minz, maxz = pts.map { |p| p[2] }.minmax
        w = maxx - minx
        d = maxy - miny
        h = maxz - minz

        front = view('front', '정면도  FRONT', w, h, project(segs, 0, 2, minx, minz))
        side  = view('side',  '측면도  SIDE',  d, h, project(segs, 1, 2, miny, minz))
        top   = view('top',   '평면도  TOP',   w, d, project(segs, 0, 1, minx, miny))

        off_f = dim_off(w, h)
        dim(front, 0, 0, w, 0, -off_f, fmt(w), :h)
        dim(front, 0, 0, 0, h, -off_f, fmt(h), :v)
        dim(side,  0, 0, d, 0, -dim_off(d, h), fmt(d), :h)
        dim(top,   w, 0, w, d, dim_off(w, d),  fmt(d), :v)

        [front, side, top]
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

      def fmt(val)
        v = val.to_f.round(1)
        v == v.to_i ? v.to_i.to_s : v.to_s
      end
    end
  end
end
