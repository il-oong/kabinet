# 발주도면 시트 컴포저 — 순수 루비.
#
# Drawing2D가 만든 정면/측면/평면 뷰를 3각법 배치(평면도 위, 정면도 아래,
# 측면도 우측)로 조합하고, 도면 틀(보더)과 표제란을 붙여 DXF로 출력한다.
#
# 좌표는 1:1 mm — 공장에서 치수를 그대로 잰다. 출력(인쇄) 축척은
# CAD에서 용지에 맞춰 지정한다 (표제란에 SCALE: N.T.S. 표기).
#
# 배치:
#   ┌─────────────────────────────┐
#   │  [평면도]                    │
#   │  [정면도]   [측면도]          │
#   │  NOTE                 표제란 │
#   └─────────────────────────────┘
module Kabinet
  module Output
    module OrderSheet
      module_function

      # spec(정규화 해시)에서 DXF 파일 생성. 반환: path.
      def generate(spec, path)
        dxf = build(spec)
        dxf.write(path)
      end

      # DXF 객체 생성 (테스트에서 문자열 검증용으로 분리)
      def build(spec)
        views = Kabinet::Output::Drawing2D.views(spec)
        front = views.find { |v| v[:name] == 'front' }
        side  = views.find { |v| v[:name] == 'side' }
        top   = views.find { |v| v[:name] == 'top' }

        # 문자 높이/간격 — 가구 크기에 비례 (인쇄 축척 무관 가독성)
        ref = [front[:width], front[:height]].max
        th  = clamp(ref / 50.0, 25.0, 80.0)          # 치수 문자 높이
        gap = clamp(ref * 0.28, 300.0, 1200.0)       # 뷰 사이 간격 (치수 공간 포함)

        dxf = Dxf.new

        # ── 뷰 배치 (3각법) ──────────────────────────────────────────────
        fx0 = 0.0
        fy0 = 0.0
        render_view(dxf, front, fx0, fy0, th)

        sx0 = fx0 + front[:width] + gap
        render_view(dxf, side, sx0, fy0, th)          # 측면도: 정면 우측, 바닥 정렬

        tx0 = fx0
        ty0 = fy0 + front[:height] + gap
        render_view(dxf, top, tx0, ty0, th)           # 평면도: 정면 위, 좌측 정렬

        # ── 도면 범위 계산 ───────────────────────────────────────────────
        margin  = gap * 0.8
        right   = [sx0 + side[:width], tx0 + top[:width]].max
        top_y   = ty0 + top[:height]

        bx0 = fx0 - margin
        by0 = fy0 - margin - title_height(th)         # 표제란 공간
        bx1 = right + margin
        by1 = top_y + margin * 0.7

        # ── 도면 틀 (보더) ───────────────────────────────────────────────
        dxf.rect(bx0, by0, bx1 - bx0, by1 - by0, 'TITLE')

        # ── 표제란 + NOTE ────────────────────────────────────────────────
        draw_title_block(dxf, spec, bx0, by0, bx1, th)

        dxf
      end

      # ── 뷰 1개 렌더 (라벨 + 지오메트리 + 치수) ────────────────────────
      def render_view(dxf, view, ox, oy, th)
        view[:rects].each do |r|
          dxf.rect(ox + r[:x], oy + r[:y], r[:w], r[:h], r[:layer])
        end
        view[:lines].each do |l|
          dxf.line(ox + l[:x1], oy + l[:y1], ox + l[:x2], oy + l[:y2], l[:layer])
        end
        view[:dims].each { |d| render_dim(dxf, d, ox, oy, th) }
        view[:texts].each do |t|
          dxf.text(ox + t[:x], oy + t[:y], t[:height] || th, t[:text], t[:layer] || 'TEXT')
        end
        # 뷰 라벨 — 뷰 하단 중앙 아래
        label_y = oy - dim_label_clear(view, th)
        dxf.text(ox + view[:width] / 2.0, label_y, th * 1.2, view[:label],
                 'TEXT', align: :center)
      end

      # 치수선이 아래(-offset)에 있으면 라벨을 그 아래로 내림
      def dim_label_clear(view, th)
        below = view[:dims].select { |d| d[:dir] == :h && d[:offset] < 0 }
                           .map { |d| -d[:offset] }.max || 0.0
        below + th * 3.2
      end

      # ── 치수 렌더 (건축 관례: 사선 틱) ────────────────────────────────
      def render_dim(dxf, d, ox, oy, th)
        ext  = th * 0.5     # 연장선 돌출
        tick = th * 0.45    # 사선 틱 반길이

        if d[:dir] == :h
          y  = oy + d[:y1] + d[:offset]
          x1 = ox + d[:x1]
          x2 = ox + d[:x2]
          y1 = oy + d[:y1]
          # 연장선
          dxf.line(x1, y1, x1, y + sign(d[:offset]) * ext, 'DIM')
          dxf.line(x2, oy + d[:y2], x2, y + sign(d[:offset]) * ext, 'DIM')
          # 치수선
          dxf.line(x1, y, x2, y, 'DIM')
          # 사선 틱 (45°)
          dxf.line(x1 - tick, y - tick, x1 + tick, y + tick, 'DIM')
          dxf.line(x2 - tick, y - tick, x2 + tick, y + tick, 'DIM')
          # 문자 — 치수선 위 중앙
          dxf.text((x1 + x2) / 2.0, y + th * 0.35, th, d[:text], 'DIM', align: :center)
        else
          x  = ox + d[:x1] + d[:offset]
          y1 = oy + d[:y1]
          y2 = oy + d[:y2]
          x1 = ox + d[:x1]
          dxf.line(x1, y1, x + sign(d[:offset]) * ext, y1, 'DIM')
          dxf.line(ox + d[:x2], y2, x + sign(d[:offset]) * ext, y2, 'DIM')
          dxf.line(x, y1, x, y2, 'DIM')
          dxf.line(x - tick, y1 - tick, x + tick, y1 + tick, 'DIM')
          dxf.line(x - tick, y2 - tick, x + tick, y2 + tick, 'DIM')
          # 문자 — 세로 치수선 좌측, 90° 회전
          dxf.text(x - th * 0.35, (y1 + y2) / 2.0, th, d[:text], 'DIM',
                   align: :center, rotation: 90)
        end
      end

      # ── 표제란 ───────────────────────────────────────────────────────────
      def title_height(th)
        th * 6.0
      end

      def draw_title_block(dxf, spec, bx0, by0, bx1, th)
        h     = title_height(th)
        ty    = by0            # 표제란 바닥 = 보더 바닥
        row_h = h / 2.0

        # 표제란 폭: 보더 폭의 45% (우측 정렬)
        tw  = (bx1 - bx0) * 0.45
        tx0 = bx1 - tw

        dxf.rect(tx0, ty, tw, h, 'TITLE')
        dxf.line(tx0, ty + row_h, bx1, ty + row_h, 'TITLE')

        g = Kabinet::Output::Drawing2D.geometry_params(spec)
        size_str = "#{g[:total_w].round}W x #{g[:max_d].round}D x #{g[:total_h].round}H"
        mat      = material_label(spec['material'])
        date     = Time.now.strftime('%Y-%m-%d')

        # 상단 행: 품명 (크게)
        dxf.text(tx0 + th, ty + row_h + row_h * 0.32, th * 1.3,
                 "품명: #{spec['name'] || '가구'}", 'TITLE')
        # 하단 행: 규격(넓게) | 재질 | 날짜
        c1 = tw * 0.46
        c2 = tw * 0.30
        dxf.line(tx0 + c1, ty, tx0 + c1, ty + row_h, 'TITLE')
        dxf.line(tx0 + c1 + c2, ty, tx0 + c1 + c2, ty + row_h, 'TITLE')
        dxf.text(tx0 + th * 0.6,           ty + row_h * 0.32, th * 0.85, size_str, 'TITLE')
        dxf.text(tx0 + c1 + th * 0.6,      ty + row_h * 0.32, th * 0.85, "재질: #{mat}", 'TITLE')
        dxf.text(tx0 + c1 + c2 + th * 0.6, ty + row_h * 0.32, th * 0.85, date, 'TITLE')

        # NOTE (보더 좌하단, 표제란 왼쪽)
        notes = build_notes(spec, g)
        ny = ty + h - th * 1.8
        dxf.text(bx0 + th, ny + th * 1.6, th * 0.9, 'NOTE', 'TEXT')
        notes.each_with_index do |n, i|
          dxf.text(bx0 + th, ny - i * th * 1.6, th * 0.85, "#{i + 1}. #{n}", 'TEXT')
        end
      end

      def build_notes(spec, g)
        notes = []
        notes << '모든 치수 단위: mm. 도면 1:1 작도 (인쇄 축척 별도 지정)'
        eb = spec['edge_banding_mm']
        notes << "엣지밴딩: #{eb ? "#{eb}T" : '1.0T'} (전면 노출부 기준)"
        if g[:base_h] > 0
          notes << "받침 높이 #{g[:base_h].round}mm, 걸레받이 전면 #{Kabinet::Constants::TOE_KICK_SETBACK_MM}mm 후퇴"
        end
        door_types = (spec['modules'] || []).map { |m| m['door_type'] }.compact.uniq - ['none']
        unless door_types.empty?
          labels = { 'swing' => '여닫이', 'sliding' => '미닫이',
                     'folding' => '접이식', 'lift_up' => '리프트업' }
          notes << "도어: #{door_types.map { |t| labels[t] || t }.join(', ')} (은선=내부 구조)"
        end
        warns = Kabinet::Core::Validation.warnings(spec)
        warns.first(3).each { |w| notes << "확인: #{w}" }
        notes
      end

      def material_label(mat)
        {
          'LPM' => 'LPM', 'PET' => 'PET', 'MDF_paint' => 'MDF 도장',
          'UV_gloss' => 'UV도장', 'acrylic' => '아크릴', 'high_gloss' => '하이그로시',
          'phenix' => '페닉스', 'plywood' => '합판', 'solid_wood' => '집성목',
          'HPL' => 'HPL'
        }[mat.to_s] || mat.to_s
      end

      def clamp(v, lo, hi)
        [[v, lo].max, hi].min
      end

      def sign(v)
        v < 0 ? -1.0 : 1.0
      end
    end
  end
end
