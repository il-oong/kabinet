# 최소 DXF R12 (AC1009) ASCII 라이터 — 순수 루비, 외부 젬 불필요.
#
# 가구 공장 CAD (AutoCAD / LibreCAD / CADian 등)에서 바로 열리는
# 발주도면용. 한글은 CP949로 인코딩하고 $DWGCODEPAGE ANSI_949를
# 선언한다 (국내 CAD 표준 환경).
#
# 지원 엔티티: LINE, TEXT (회전/정렬), 레이어/선종류 테이블.
# 좌표 단위: mm (1:1).
module Kabinet
  module Output
    class Dxf
      # 레이어 정의: 이름 => [ACI 색번호, 선종류]
      LAYERS = {
        'OUTLINE' => [7, 'CONTINUOUS'],  # 외곽 실선 (흰/검)
        'FRONTS'  => [4, 'CONTINUOUS'],  # 도어/서랍 전판 (하늘색)
        'HIDDEN'  => [8, 'DASHED'],      # 은선 (회색 점선)
        'SYMBOL'  => [3, 'CONTINUOUS'],  # 개폐 표시 (녹색)
        'DIM'     => [1, 'CONTINUOUS'],  # 치수 (빨강)
        'TEXT'    => [2, 'CONTINUOUS'],  # 문자 (노랑)
        'TITLE'   => [7, 'CONTINUOUS']   # 도면 틀/표제란
      }.freeze

      def initialize
        @entities = []
        @min_x = @min_y =  1e12
        @max_x = @max_y = -1e12
      end

      def line(x1, y1, x2, y2, layer = 'OUTLINE')
        track(x1, y1); track(x2, y2)
        @entities << [
          '0', 'LINE', '8', layer,
          '10', fx(x1), '20', fx(y1), '30', '0.0',
          '11', fx(x2), '21', fx(y2), '31', '0.0'
        ]
      end

      def rect(x, y, w, h, layer = 'OUTLINE')
        line(x, y, x + w, y, layer)
        line(x + w, y, x + w, y + h, layer)
        line(x + w, y + h, x, y + h, layer)
        line(x, y + h, x, y, layer)
      end

      # align: :left | :center | :right,  valign: :base | :middle
      def text(x, y, height, str, layer = 'TEXT', align: :left, rotation: 0, valign: :base)
        track(x, y)
        h_code = { left: 0, center: 1, right: 2 }[align] || 0
        v_code = { base: 0, bottom: 1, middle: 2, top: 3 }[valign] || 0
        # 모든 TEXT를 전용 스타일(KABINET=맑은고딕)에 강제 바인딩 —
        # 기존 도면의 STANDARD(한글 SHX)에 덮이지 않게 함.
        e = [
          '0', 'TEXT', '8', layer,
          '10', fx(x), '20', fx(y), '30', '0.0',
          '40', fx(height), '1', str.to_s, '7', 'KABINET'
        ]
        e += ['50', fx(rotation)] if rotation != 0
        if h_code != 0 || v_code != 0
          e += ['72', h_code.to_s, '73', v_code.to_s,
                '11', fx(x), '21', fx(y), '31', '0.0']
        end
        @entities << e
      end

      # ── 직렬화 ───────────────────────────────────────────────────────────
      def to_s
        out = []
        # HEADER
        out << sect('HEADER',
                    ['9', '$ACADVER',     '1', 'AC1009',
                     '9', '$DWGCODEPAGE', '3', 'ANSI_949',
                     '9', '$INSBASE',  '10', '0.0', '20', '0.0', '30', '0.0',
                     '9', '$EXTMIN',   '10', fx(@min_x), '20', fx(@min_y), '30', '0.0',
                     '9', '$EXTMAX',   '10', fx(@max_x), '20', fx(@max_y), '30', '0.0'])

        # TABLES: LTYPE + LAYER
        ltypes = [
          '0', 'TABLE', '2', 'LTYPE', '70', '2',
          '0', 'LTYPE', '2', 'CONTINUOUS', '70', '0',
          '3', 'Solid line', '72', '65', '73', '0', '40', '0.0',
          '0', 'LTYPE', '2', 'DASHED', '70', '0',
          '3', '- - - -', '72', '65', '73', '2', '40', '15.0',
          '49', '10.0', '49', '-5.0',
          '0', 'ENDTAB'
        ]
        layers = ['0', 'TABLE', '2', 'LAYER', '70', LAYERS.size.to_s]
        LAYERS.each do |name, (color, ltype)|
          layers += ['0', 'LAYER', '2', name, '70', '0',
                     '62', color.to_s, '6', ltype]
        end
        layers += ['0', 'ENDTAB']
        # 문자 스타일: 맑은 고딕 TTF. 전용 스타일 KABINET을 별도로 정의하고
        # 모든 TEXT가 이를 참조(group 7)하게 해 기존 도면 STANDARD에 안 덮임.
        # STANDARD도 맑은고딕으로 함께 정의 (호환용).
        style = ['0', 'TABLE', '2', 'STYLE', '70', '2',
                 '0', 'STYLE', '2', 'STANDARD', '70', '0', '40', '0.0',
                 '41', '1.0', '50', '0.0', '71', '0', '42', '2.5',
                 '3', 'malgun.ttf', '4', '',
                 '0', 'STYLE', '2', 'KABINET', '70', '0', '40', '0.0',
                 '41', '1.0', '50', '0.0', '71', '0', '42', '2.5',
                 '3', 'malgun.ttf', '4', '',
                 '0', 'ENDTAB']
        out << sect('TABLES', ltypes + layers + style)

        # ENTITIES
        body = @entities.flatten
        out << sect('ENTITIES', body)
        out << "0\nEOF\n"
        out.join
      end

      # CP949 바이트로 반환 (국내 CAD 호환). 변환 불가 문자는 '?'.
      def to_cp949
        to_s.encode(Encoding::CP949, invalid: :replace, undef: :replace, replace: '?')
      end

      def write(path)
        File.open(path, 'wb') { |f| f.write(to_cp949) }
        path
      end

      private

      def sect(name, pairs)
        "0\nSECTION\n2\n#{name}\n" + pairs.each_slice(2).map { |c, v| "#{c}\n#{v}\n" }.join + "0\nENDSEC\n"
      end

      def fx(v)
        format('%.2f', v.to_f)
      end

      def track(x, y)
        @min_x = x if x < @min_x
        @min_y = y if y < @min_y
        @max_x = x if x > @max_x
        @max_y = y if y > @max_y
      end
    end
  end
end
