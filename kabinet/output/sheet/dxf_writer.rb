require_relative 'text'
require_relative 'styles'
require_relative 'dxf_skeleton'
module Kabinet
  module Output
    module Sheet
      # AC1018(R2004) ASCII DXF 작성기 — LINE/LWPOLYLINE/CIRCLE/TEXT/SOLID/HATCH/IMAGE, 레이어 선굵기·TrueColor,
      # 시트별 BG(배경) 채움. 한글은 CP949(ANSI_949)로 인코딩. 순수 Ruby.
      #
      # 골격(HEADER/CLASSES/TABLES/BLOCKS/OBJECTS)은 ezdxf 가 쓰는 R2004 파일을 그대로 옮긴 DxfSkeleton(자동 생성,
      # tools/sheet/gen_dxf_skeleton.py)이고, 여기서는 레이어·텍스트 스타일·엔티티·IMAGEDEF 만 끼워 넣는다.
      # (LAYOUT/ACAD_GROUP/ACAD_MATERIAL/DIMSTYLE/CLASSES 등이 빠진 파일은 일부 CAD 가 열지 못한다)
      #
      # pages: [Canvas], 시트는 X 방향으로 나란히 배치(1단위 = 1mm).
      # opts:
      #   bg: 'white'|'dark'|'none', style_name:, font_file:
      #   image_paths: {원본경로 => DXF 에 적을 경로}, image_sizes: {원본경로 => [px_w, px_h]}
      #   images: false 면 IMAGE/IMAGEDEF 를 쓰지 않는다(사진 자리는 IMAGE_FRAME 사각형만 남는다)
      #   blocks: true(기본)면 뷰(Canvas#group)·도곽을 이름 있는 BLOCK(+INSERT 1개)으로 묶는다. 수정은 분해(EXPLODE)/REFEDIT.
      #   real_scale: true 면 시트별 축척 분모(canvas.meta[:den] 또는 default_den)만큼 모든 좌표·글자·간격을 키워
      #               가구 형상이 실제 mm 좌표가 되게 한다(도곽은 420xden × 297xden).
      class DxfWriter
        PAGE_GAP = 80.0
        PW_ = Sheet::PW
        BG_RGB_FOR = { 'white' => [255, 255, 255], 'dark' => [33, 37, 43] }.freeze

        attr_reader :ents_count

        def initialize(pages, bg: 'white', style_name: 'MALGUN', font_file: 'malgun.ttf', image_paths: {}, image_sizes: {},
                       images: true, real_scale: false, default_den: nil, blocks: true)
          @blocks_on = blocks ? true : false
          @pages = pages
          @bg = %w[white dark none].include?(bg.to_s) ? bg.to_s : 'white'
          @style = Text.utf8(style_name).empty? ? 'MALGUN' : Text.utf8(style_name)
          @font = Text.utf8(font_file).empty? ? 'malgun.ttf' : Text.utf8(font_file)
          @image_paths = image_paths
          @image_sizes = image_sizes
          @images_on = images ? true : false
          @real = real_scale ? true : false
          @default_den = [(default_den || 1).to_f, 1.0].max
          @handle = [0x100, DxfSkeleton::MAX_TEMPLATE_HANDLE + 1].max
          @model_rec = DxfSkeleton::MODEL_RECORD
          @images = []      # [{ent, def, reactor, path, pw, ph}]
          layout_pages
        end

        # 시트별 배수·X 오프셋
        def layout_pages
          @dens = @pages.map do |pg|
            @real ? [((pg.respond_to?(:meta) && pg.meta[:den]) || @default_den).to_f, 1.0].max : 1.0
          end
          @offsets = []
          x = 0.0
          @dens.each do |k|
            @offsets << x
            x += @real ? PW_ * k * 1.1 : PW_ * k + PAGE_GAP
          end
          @total_w = @pages.empty? ? PW_ : @offsets.last + PW_ * @dens.last
          @max_k = @dens.max || 1.0
        end

        def h
          @handle += 1
          @handle.to_s(16).upcase
        end

        def pair(code, val)
          v = val.is_a?(String) ? Text.utf8(val) : val
          "#{code}\n#{v}\n"
        end

        def fx(v) format('%.4f', v.to_f) end

        def color_pairs(rgb)
          col = Sheet.dxf_color(rgb, @bg)
          col.is_a?(Integer) ? pair(62, col) : pair(420, (col[0] << 16) | (col[1] << 8) | col[2])
        end

        def ent_head(type, layer, rgb, lw = nil)
          s = pair(0, type) + pair(5, h) + pair(330, @model_rec) + pair(100, 'AcDbEntity') + pair(8, layer)
          s += color_pairs(rgb) if rgb
          s += pair(370, lw) if lw
          s
        end

        # ── 엔티티 ───────────────────────────────────────────────────────
        def build_entities
          @block_recs = +''
          @block_defs = +''
          @block_count = 0
          out = []
          out << bg_solids if %w[white dark].include?(@bg)
          @pages.each_with_index do |pg, i|
            ox = @offsets[i]; k = @dens[i]
            if @blocks_on && pg.respond_to?(:item_groups)
              out << block_page(pg, i, ox, k)
            else
              pg.items.each { |it| out << entity(it, ox, k) }
            end
            out << info_text(pg, i, ox, k)
          end
          out.flatten.compact
        end

        # 뷰별 BLOCK 정의 + 시트 원점에 INSERT 1개씩. 사진(IMAGE)은 블록 밖(모델 공간)에 둔다.
        def block_page(pg, i, ox, k)
          groups = {}
          loose = []
          pg.items.each_with_index do |it, idx|
            if it[0] == :I
              loose << entity(it, ox, k)
            else
              (groups[pg.item_groups[idx] || :frame] ||= []) << it
            end
          end
          inserts = []
          groups.each do |g, its|
            name = g == :frame ? "FRAME_SHEET#{i + 1}" : "#{g.to_s.upcase.gsub(/[^A-Z0-9_]/, '_')}_S#{i + 1}"
            rec = h
            saved = @model_rec
            @model_rec = rec
            body = its.map { |it| entity(it, 0.0, k) }.flatten.compact
            @model_rec = saved
            bh = h; eh = h
            @block_recs << pair(0, 'BLOCK_RECORD') + pair(5, rec) + pair(330, '9') + pair(100, 'AcDbSymbolTableRecord') +
                           pair(100, 'AcDbBlockTableRecord') + pair(2, name) + pair(340, 0)
            @block_defs << pair(0, 'BLOCK') + pair(5, bh) + pair(330, rec) + pair(100, 'AcDbEntity') + pair(8, '0') +
                           pair(100, 'AcDbBlockBegin') + pair(2, name) + pair(70, 0) + pair(10, 0) + pair(20, 0) + pair(30, 0) + pair(3, name) + pair(1, '') +
                           body.join +
                           pair(0, 'ENDBLK') + pair(5, eh) + pair(330, rec) + pair(100, 'AcDbEntity') + pair(8, '0') + pair(100, 'AcDbBlockEnd')
            @block_count += 1
            inserts << (pair(0, 'INSERT') + pair(5, h) + pair(330, @model_rec) + pair(100, 'AcDbEntity') + pair(8, '0') +
                        pair(100, 'AcDbBlockReference') + pair(2, name) + pair(10, fx(ox)) + pair(20, 0) + pair(30, 0))
          end
          inserts + loose
        end

        def bg_solids
          @pages.each_index.map do |i|
            ox = @offsets[i]; k = @dens[i]
            ent_head('SOLID', 'BG', BG_RGB_FOR[@bg], 0) + pair(100, 'AcDbTrace') +
              pair(10, fx(ox)) + pair(20, fx(0)) + pair(30, 0) + pair(11, fx(ox + PW_ * k)) + pair(21, fx(0)) + pair(31, 0) +
              pair(12, fx(ox)) + pair(22, fx(Sheet::PH * k)) + pair(32, 0) + pair(13, fx(ox + PW_ * k)) + pair(23, fx(Sheet::PH * k)) + pair(33, 0)
          end
        end

        def info_text(pg, i, ox, k)
          lab = "[#{i + 1}] #{pg.name}"
          lab += " (1/#{k.round})" if @real && k > 1
          text_entity(ox + 4.5 * k, (Sheet::PH + 4.0) * k, 3.0 * k, lab, 'SHEET_FRAME_INFO', [110, 110, 110], 0, 'l')
        end

        def entity(it, ox, k)
          px = ->(x) { ox + x * k }
          py = ->(y) { (Sheet::PH - y) * k }
          case it[0]
          when :L
            _t, x1, y1, x2, y2, st = it
            lay, w, rgb = Sheet::STY[st]
            ent_head('LINE', lay, rgb, Sheet.lineweight(w)) + pair(100, 'AcDbLine') +
              pair(10, fx(px.call(x1))) + pair(20, fx(py.call(y1))) + pair(30, 0) +
              pair(11, fx(px.call(x2))) + pair(21, fx(py.call(y2))) + pair(31, 0)
          when :P
            _t, pts, st, closed = it
            lay, w, rgb = Sheet::STY[st]
            s = ent_head('LWPOLYLINE', lay, rgb, Sheet.lineweight(w)) + pair(100, 'AcDbPolyline') +
                pair(90, pts.size) + pair(70, closed ? 1 : 0)
            pts.each { |x, y| s += pair(10, fx(px.call(x))) + pair(20, fx(py.call(y))) }
            s
          when :C
            _t, cx, cy, r, st = it
            lay, w, rgb = Sheet::STY[st]
            ent_head('CIRCLE', lay, rgb, Sheet.lineweight(w)) + pair(100, 'AcDbCircle') +
              pair(10, fx(px.call(cx))) + pair(20, fx(py.call(cy))) + pair(30, 0) + pair(40, fx(r * k))
          when :F
            _t, pts, rgb = it
            fill_entity(pts, rgb, px, py)
          when :H
            hatch_entity(it, px, py, k)
          when :T
            _t, x, y, str, size, col, a, rot = it
            lay, rgb = Sheet::TXT[col]
            text_entity(px.call(x), py.call(y), size * 0.72 * k, str, lay, rgb, rot, a)
          when :I
            image_entity(it, px, py, k)
          end
        end

        def fill_entity(pts, rgb, px, py)
          lay = rgb == [85, 85, 85] ? 'FRAME' : 'OUTLINE'
          return fan_solids(pts, rgb, px, py, lay) if pts.size > 4
          q = pts.size == 3 ? pts + [pts[2]] : pts
          ent_head('SOLID', lay, rgb, 0) + pair(100, 'AcDbTrace') + solid_corners(q, px, py)
        end

        # SOLID 점 순서: 1,2,4,3
        def solid_corners(q, px, py)
          [q[0], q[1], q[3], q[2]].each_with_index.map do |(x, y), i|
            pair(10 + i, fx(px.call(x))) + pair(20 + i, fx(py.call(y))) + pair(30 + i, 0)
          end.join
        end

        def fan_solids(pts, rgb, px, py, lay)
          (1...pts.size - 1).map do |i|
            ent_head('SOLID', lay, rgb, 0) + pair(100, 'AcDbTrace') + solid_corners([pts[0], pts[i], pts[i + 1], pts[i + 1]], px, py)
          end
        end

        # [:H, pts, st, step] — 닫힌 외곽 안을 45° 해칭(ANSI31). step = 종이 mm 간격(실치수 모드에선 배수 적용)
        def hatch_entity(it, px, py, k)
          _t, pts, st, step = it
          lay, _w, rgb = Sheet::STY[st || 'HATCH']
          step = (step || 0.5).to_f * k
          scale = step / (3.175 * 0.70710678)          # ANSI31 기본 선 간격 3.175 → 원하는 간격
          off = 3.175 * scale * 0.70710678
          s = ent_head('HATCH', lay, rgb, nil) + pair(100, 'AcDbHatch') +
              pair(10, 0) + pair(20, 0) + pair(30, 0) + pair(210, 0) + pair(220, 0) + pair(230, 1) +
              pair(2, 'ANSI31') + pair(70, 0) + pair(71, 0) + pair(91, 1) + pair(92, 3) + pair(72, 0) + pair(73, 1) + pair(93, pts.size)
          pts.each { |x, y| s += pair(10, fx(px.call(x))) + pair(20, fx(py.call(y))) }
          s + pair(97, 0) + pair(75, 1) + pair(76, 1) + pair(52, 0) + pair(41, fx(scale)) + pair(77, 0) + pair(78, 1) +
            pair(53, 45) + pair(43, 0) + pair(44, 0) + pair(45, fx(-off)) + pair(46, fx(off)) + pair(79, 0) + pair(98, 0)
        end

        def text_entity(x, y, height, str, layer, rgb, rot, align)
          s = ent_head('TEXT', layer, rgb) + pair(100, 'AcDbText') +
              pair(10, fx(x)) + pair(20, fx(y)) + pair(30, 0) + pair(40, fx(height)) + pair(1, str.to_s)
          s += pair(50, fx(rot)) if rot.to_f != 0
          s += pair(7, @style)
          ha = { 'l' => 0, 'c' => 1, 'r' => 2 }[align] || 0
          if ha != 0
            s += pair(72, ha) + pair(11, fx(x)) + pair(21, fx(y)) + pair(31, 0)
          end
          s + pair(100, 'AcDbText')
        end

        # IMAGE + IMAGEDEF + IMAGEDEF_REACTOR (ezdxf 와 같은 구성). images: false 면 아무것도 쓰지 않는다.
        def image_entity(it, px, py, k)
          return nil unless @images_on
          _t, x, y, w, hgt, path = it
          ref = @image_paths[path] || path
          sz = @image_sizes[path] || [1000, 1000]
          pw, ph = sz
          eh = h; dh = h; rh = h
          @images << { ent: eh, def: dh, reactor: rh, path: ref, pw: pw, ph: ph }
          # 삽입점 = 이미지 좌하단(DXF 좌표). 시트 y 는 아래로 증가하므로 변환.
          llx = px.call(x); lly = py.call(y + hgt)
          pair(0, 'IMAGE') + pair(5, eh) + pair(330, @model_rec) + pair(100, 'AcDbEntity') + pair(8, 'IMAGE') +
            pair(100, 'AcDbRasterImage') + pair(90, 0) +
            pair(10, fx(llx)) + pair(20, fx(lly)) + pair(30, 0) +
            pair(11, format('%.10f', w * k / pw.to_f)) + pair(21, 0) + pair(31, 0) +
            pair(12, 0) + pair(22, format('%.10f', hgt * k / ph.to_f)) + pair(32, 0) +
            pair(13, fx(pw)) + pair(23, fx(ph)) +
            pair(340, dh) + pair(70, 3) + pair(280, 0) + pair(281, 50) + pair(282, 50) + pair(283, 0) +
            pair(360, rh) + pair(71, 1) + pair(91, 2) +
            pair(14, fx(-0.5)) + pair(24, fx(-0.5)) + pair(14, fx(pw - 0.5)) + pair(24, fx(ph - 0.5))
        end

        # ── 파일 조립 ─────────────────────────────────────────────────────
        def to_s
          @images = []
          @handle = [0x100, DxfSkeleton::MAX_TEMPLATE_HANDLE + 1].max
          ents = build_entities
          @ents_count = ents.size
          layers = layer_defs
          layer_text = +''
          layers.each { |nm, (rgb, w)| next if %w[0 Defpoints].include?(nm); layer_text << layer_rec(nm, rgb, w, h) }
          style_text = style_rec(@style, h)
          image_dict, image_objs = image_objects
          cx = @offsets.empty? ? 0.0 : PW_ * @dens.first / 2.0
          vals = {
            'ENTITIES' => ents.join, 'BLOCKS' => @block_defs, 'BLOCKRECS' => @block_recs,
            'BLOCKRECS_COUNT' => (2 + @block_count).to_s,
            'LAYERS' => layer_text, 'LAYERS_COUNT' => (DxfSkeleton::BASE_LAYER_COUNT + layers.keys.reject { |n| %w[0 Defpoints].include?(n) }.size).to_s,
            'STYLES' => style_text, 'STYLES_COUNT' => (DxfSkeleton::BASE_STYLE_COUNT + 1).to_s,
            'IMAGE_DICT_ENTRIES' => image_dict, 'IMAGE_OBJECTS' => image_objs,
            'EXTMINX' => '0.0', 'EXTMINY' => '0.0',
            'EXTMAXX' => fx(@total_w), 'EXTMAXY' => fx((Sheet::PH + 10) * @max_k),
            'LTSCALE' => format('%.1f', @real ? @dens.first.to_f : 1.0),
            'VPCX' => fx(cx), 'VPCY' => fx(Sheet::PH * (@dens.first || 1) / 2.0), 'VPH' => fx(Sheet::PH * (@dens.first || 1) * 1.15),
            'HANDSEED' => (@handle + 1).to_s(16).upcase
          }
          DxfSkeleton::TEXT.gsub(/^@@(\w+)@@\n/) do
            v = vals.fetch(Regexp.last_match(1))
            v.empty? || v.end_with?("\n") ? v : "#{v}\n"
          end
        end

        def layer_defs
          defs = {}
          Sheet::STY.each_value do |lay, w, rgb|
            defs[lay] ||= [rgb, w]
            defs[lay][1] = w if w > defs[lay][1]
          end
          defs['TEXT'] = [[0, 0, 0], 0.36]
          defs['IMAGE'] = [[0, 0, 0], 0.0]
          defs['SHEET_FRAME_INFO'] = [[110, 110, 110], 0.0]
          defs['BG'] = [Sheet::BG_RGB['white'], 0.0] if %w[white dark].include?(@bg)
          defs
        end

        # ezdxf 가 쓰는 LAYER 레코드와 같은 그룹 순서(62 [420] 6 290 370 390)
        def layer_rec(name, rgb, w, hd)
          col = Sheet.dxf_color(rgb, @bg)
          s = pair(0, 'LAYER') + pair(5, hd) + pair(330, '1') + pair(100, 'AcDbSymbolTableRecord') + pair(100, 'AcDbLayerTableRecord') +
              pair(2, name) + pair(70, 0)
          s += col.is_a?(Integer) ? pair(62, col) : pair(62, 7) + pair(420, (col[0] << 16) | (col[1] << 8) | col[2])
          s + pair(6, 'Continuous') + pair(290, 1) + pair(370, Sheet.lineweight(w)) + pair(390, '13')
        end

        def style_rec(name, hd)
          pair(0, 'STYLE') + pair(5, hd) + pair(330, '5') + pair(100, 'AcDbSymbolTableRecord') + pair(100, 'AcDbTextStyleTableRecord') +
            pair(2, name) + pair(70, 0) + pair(40, 0) + pair(41, 1) + pair(50, 0) + pair(71, 0) + pair(42, 2.5) + pair(3, @font) + pair(4, '')
        end

        # => [ACAD_IMAGE_DICT 항목 텍스트, IMAGEDEF/IMAGEDEF_REACTOR 객체 텍스트]
        def image_objects
          return ['', ''] if @images.empty?
          dict = DxfSkeleton::IMAGE_DICT
          used = {}
          entries = +''
          objs = +''
          @images.each_with_index do |im, i|
            key = File.basename(im[:path].to_s)
            key = "img_#{i + 1}" if key.empty?
            key = "#{key}_#{i + 1}" if used[key]
            used[key] = true
            entries << pair(3, key) + pair(350, im[:def])
            objs << pair(0, 'IMAGEDEF') + pair(5, im[:def]) + pair(102, '{ACAD_REACTORS') + pair(330, dict) + pair(330, im[:reactor]) + pair(102, '}') +
                    pair(330, dict) + pair(100, 'AcDbRasterImageDef') + pair(90, 0) + pair(1, im[:path]) +
                    pair(10, fx(im[:pw])) + pair(20, fx(im[:ph])) + pair(11, '0.01') + pair(21, '0.01') + pair(280, 1) + pair(281, 0)
            objs << pair(0, 'IMAGEDEF_REACTOR') + pair(5, im[:reactor]) + pair(330, im[:ent]) + pair(100, 'AcDbRasterImageDefReactor') +
                    pair(90, 2) + pair(330, im[:ent])
          end
          [entries, objs]
        end

        # CP949 바이트로 변환. 변환 불가 문자는 '?'
        def to_cp949
          Text.to_cp949(to_s)
        end

        def write(path)
          File.open(path, 'wb') { |fh| fh.write(to_cp949) }
          path
        end
      end
    end
  end
end
