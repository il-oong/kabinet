# 3D CAD(DXF R12, 3DFACE) 내보내기.
#
# 가구 3D 형상을 부재 역할별 레이어로 나눠 DXF 로 쓴다. 솔리드가 아니라 면(3DFACE) 모음이라
# AutoCAD/한글 CAD 에서 열어 보고 선택·치수 확인은 되지만 부피 계산·불리언 편집은 안 된다.
# 레이어 이름은 CAD 호환을 위해 영문(ASCII)으로 쓰고, 아래 LAYERS 에 한글 설명을 둔다.
# 좌표 단위 mm, 좌표계는 SketchUp 모델 월드(X 우, Y 안쪽, Z 위) 그대로.
module Kabinet
  module Output
    class Dxf3d
      # 레이어 => [ACI 색, 한글 설명]
      LAYERS = {
        'K3D_SIDE'    => [5,   '측판·칸막이'],
        'K3D_TOP'     => [4,   '상판·천판'],
        'K3D_BOTTOM'  => [150, '하판·바닥판'],
        'K3D_BACK'    => [8,   '뒷판'],
        'K3D_SHELF'   => [3,   '선반'],
        'K3D_DOOR'    => [2,   '도어'],
        'K3D_DRAWER_FRONT' => [6, '서랍 전판'],
        'K3D_DRAWER'  => [30,  '서랍 몸통'],
        'K3D_EP'      => [1,   'EP 마감판'],
        'K3D_PLINTH'  => [9,   '걸레받이'],
        'K3D_CHANNEL' => [40,  '찬넬'],
        'K3D_HANDLE'  => [7,   '손잡이'],
        'K3D_HARDWARE' => [253, '행거·철물'],
        'K3D_OTHER'   => [7,   '기타']
      }.freeze

      # 자식이 각자 역할을 갖는 묶음 역할: 레이어를 정하지 않고 상위 값을 이어받는다.
      CONTAINER_ROLES = /\A(assembly|body_group|carcase|[a-z_]*_module|shelf_accessory)\z/

      RULES = [
        [/\Aep(_|\z)/,                                   'K3D_EP'],
        [/\Adrawer_front|\Adrawer_inner_front|\Acell_dfr_|\Ainner_dfr_/, 'K3D_DRAWER_FRONT'],
        [/\Adoor|\Acenter_stile/,                        'K3D_DOOR'],
        [/\Adrawers_group|\Adrawer|\Acell_dbox_|\Ainner_dbox_/, 'K3D_DRAWER'],
        [/\Ahandle/,                                     'K3D_HANDLE'],
        [/channel/,                                      'K3D_CHANNEL'],
        [/modesty|kick|plinth/,                          'K3D_PLINTH'],
        [/shelf/,                                        'K3D_SHELF'],
        [/\Aside|_side|divider|desk_leg/,                'K3D_SIDE'],
        [/\Atop|_top\z|top_panel|desk_top/,              'K3D_TOP'],
        [/\Abottom|_bottom\z/,                           'K3D_BOTTOM'],
        [/back/,                                         'K3D_BACK'],
        [/rod|hanger/,                                   'K3D_HARDWARE']
      ].freeze

      NAME_RULES = [
        [/EP/i, 'K3D_EP'], [/걸레받이/, 'K3D_PLINTH'], [/찬넬/, 'K3D_CHANNEL'], [/손잡이/, 'K3D_HANDLE'],
        [/서랍.*(전|면)/, 'K3D_DRAWER_FRONT'], [/서랍/, 'K3D_DRAWER'], [/도어|문짝/, 'K3D_DOOR'],
        [/선반/, 'K3D_SHELF'], [/측판|칸막이/, 'K3D_SIDE'], [/상판|천판/, 'K3D_TOP'],
        [/하판|바닥판/, 'K3D_BOTTOM'], [/뒷판|뒤판/, 'K3D_BACK']
      ].freeze

      # 역할(role) 과 그룹 이름으로 레이어를 정한다. 정할 수 없으면 nil(상위 값을 이어받는다).
      def self.layer_for(role, name = nil)
        r = role.to_s
        unless r.empty? || r =~ CONTAINER_ROLES
          RULES.each { |re, layer| return layer if r =~ re }
        end
        n = name.to_s
        NAME_RULES.each { |re, layer| return layer if n =~ re } unless n.empty?
        nil
      end

      # 다각형(볼록)을 축 평면으로 잘라 keep 쪽만 남긴다. axis 0=X 1=Y 2=Z, keep :le(<= pos) / :ge(>= pos).
      # 결과는 점 3개 미만이면 빈 배열. 단면 보기용이라 절단면 뚜껑은 만들지 않는다.
      def self.clip(pts, axis, pos, keep)
        inside = lambda { |p| keep == :le ? p[axis] <= pos + 1e-6 : p[axis] >= pos - 1e-6 }
        out = []
        pts.each_with_index do |a, i|
          b = pts[(i + 1) % pts.length]
          ia = inside.call(a)
          ib = inside.call(b)
          out << a if ia
          if ia != ib
            t = (pos - a[axis]).to_f / (b[axis] - a[axis])
            out << (0..2).map { |k| a[k] + (b[k] - a[k]) * t }
          end
        end
        out.length >= 3 ? out : []
      end

      # 3~N 점 다각형을 3·4점 면으로 나눠 쓴다(부채꼴 분할).
      def polygon(pts, layer)
        return if pts.length < 3
        (1...(pts.length - 1)).each { |i| face([pts[0], pts[i], pts[i + 1]], layer) }
      end

      attr_reader :face_count

      def initialize
        @faces = []
        @face_count = 0
        @lo = [1e12] * 3
        @hi = [-1e12] * 3
        @used = {}
      end

      # pts: 3개 또는 4개의 [x, y, z](mm). hidden_edges: 보이지 않게 할 변 번호(0~3)
      def face(pts, layer = 'K3D_OTHER', hidden_edges = [])
        raise ArgumentError, '점은 3개 또는 4개' unless [3, 4].include?(pts.length)
        layer = 'K3D_OTHER' unless LAYERS.key?(layer)
        quad = pts.length == 3 ? pts + [pts[2]] : pts
        quad.each { |p| track(p) }
        flags = hidden_edges.inject(0) { |a, i| a | (1 << i) }
        e = ['0', '3DFACE', '8', layer]
        quad.each_with_index do |p, i|
          e += [(10 + i).to_s, fx(p[0]), (20 + i).to_s, fx(p[1]), (30 + i).to_s, fx(p[2])]
        end
        e += ['70', flags.to_s] if flags != 0
        @faces << e
        @face_count += 1
        @used[layer] = (@used[layer] || 0) + 1
      end

      def layer_counts
        @used.dup
      end

      def to_s
        lo = @face_count.zero? ? [0, 0, 0] : @lo
        hi = @face_count.zero? ? [0, 0, 0] : @hi
        out = []
        out << sect('HEADER',
                    ['9', '$ACADVER', '1', 'AC1009',
                     '9', '$DWGCODEPAGE', '3', 'ANSI_949',
                     '9', '$INSBASE', '10', '0.0', '20', '0.0', '30', '0.0',
                     '9', '$EXTMIN', '10', fx(lo[0]), '20', fx(lo[1]), '30', fx(lo[2]),
                     '9', '$EXTMAX', '10', fx(hi[0]), '20', fx(hi[1]), '30', fx(hi[2])])
        ltypes = ['0', 'TABLE', '2', 'LTYPE', '70', '1',
                  '0', 'LTYPE', '2', 'CONTINUOUS', '70', '0', '3', 'Solid line', '72', '65', '73', '0', '40', '0.0',
                  '0', 'ENDTAB']
        layers = ['0', 'TABLE', '2', 'LAYER', '70', LAYERS.size.to_s]
        LAYERS.each { |name, (color, _)| layers += ['0', 'LAYER', '2', name, '70', '0', '62', color.to_s, '6', 'CONTINUOUS'] }
        layers += ['0', 'ENDTAB']
        out << sect('TABLES', ltypes + layers)
        out << sect('ENTITIES', @faces.flatten)
        out << "0\nEOF\n"
        out.join
      end

      def write(path)
        File.open(path, 'wb') { |f| f.write(to_s.encode(Encoding::CP949, invalid: :replace, undef: :replace, replace: '?')) }
        path
      end

      private

      def sect(name, pairs)
        "0\nSECTION\n2\n#{name}\n" + pairs.each_slice(2).map { |c, v| "#{c}\n#{v}\n" }.join + "0\nENDSEC\n"
      end

      def fx(v)
        format('%.3f', v.to_f)
      end

      def track(p)
        3.times do |i|
          @lo[i] = p[i] if p[i] < @lo[i]
          @hi[i] = p[i] if p[i] > @hi[i]
        end
      end
    end
  end
end
