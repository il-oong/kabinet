require_relative 'text'
require_relative 'styles'
module Kabinet
  module Output
    module Sheet
      # AC1015(R2000) ASCII DXF 작성기 — LINE/LWPOLYLINE/CIRCLE/TEXT/SOLID/IMAGE, 레이어 선굵기·TrueColor,
      # 시트별 BG(배경) 채움. 한글은 CP949(ANSI_949)로 인코딩. 순수 Ruby.
      #
      # pages: [Canvas], 시트는 X 방향으로 (PW + gap) 간격으로 배치(1단위 = 1mm).
      # opts: bg: 'white'|'dark'|'none', style_name:, font_file:, image_paths: {원본경로 => DXF에 적을 경로}
      class DxfWriter
        PAGE_GAP = 80.0

        def initialize(pages, bg: 'white', style_name: 'MALGUN', font_file: 'malgun.ttf', image_paths: {}, image_sizes: {})
          @pages = pages
          @bg = %w[white dark none].include?(bg.to_s) ? bg.to_s : 'white'
          @style = Text.utf8(style_name).empty? ? 'MALGUN' : Text.utf8(style_name)
          @font = Text.utf8(font_file).empty? ? 'malgun.ttf' : Text.utf8(font_file)
          @image_paths = image_paths
          @image_sizes = image_sizes
          @handle = 0x100
          @ents = []
          @images = []      # [{ent, def, reactor, path, pw, ph}]
          @model_rec_h = '1F'
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

        def build_entities
          @model_rec = '1F'
          out = []
          out << bg_solids if %w[white dark].include?(@bg)
          @pages.each_with_index do |pg, i|
            ox = i * (PW_ + PAGE_GAP)
            pg.items.each do |it|
              out << entity(it, ox)
            end
            out << info_text(pg, i, ox)
          end
          out.flatten.compact
        end

        PW_ = Sheet::PW

        def bg_solids
          @pages.each_index.map do |i|
            ox = i * (PW_ + PAGE_GAP)
            ent_head('SOLID', 'BG', BG_RGB_FOR[@bg], 0) + pair(100, 'AcDbTrace') +
              pair(10, fx(ox)) + pair(20, fx(0)) + pair(30, 0) + pair(11, fx(ox + PW_)) + pair(21, fx(0)) + pair(31, 0) +
              pair(12, fx(ox)) + pair(22, fx(Sheet::PH)) + pair(32, 0) + pair(13, fx(ox + PW_)) + pair(23, fx(Sheet::PH)) + pair(33, 0)
          end
        end

        def info_text(pg, i, ox)
          text_entity(ox + 4.5, Sheet::PH + 4.0, 3.0, "[#{i + 1}] #{pg.name}", 'SHEET_FRAME_INFO', [110, 110, 110], 0, 'l')
        end

        def entity(it, ox)
          case it[0]
          when :L
            _t, x1, y1, x2, y2, st = it
            lay, w, rgb = Sheet::STY[st]
            ent_head('LINE', lay, rgb, Sheet.lineweight(w)) + pair(100, 'AcDbLine') +
              pair(10, fx(ox + x1)) + pair(20, fx(Sheet::PH - y1)) + pair(30, 0) +
              pair(11, fx(ox + x2)) + pair(21, fx(Sheet::PH - y2)) + pair(31, 0)
          when :P
            _t, pts, st, closed = it
            lay, w, rgb = Sheet::STY[st]
            s = ent_head('LWPOLYLINE', lay, rgb, Sheet.lineweight(w)) + pair(100, 'AcDbPolyline') +
                pair(90, pts.size) + pair(70, closed ? 1 : 0)
            pts.each { |x, y| s += pair(10, fx(ox + x)) + pair(20, fx(Sheet::PH - y)) }
            s
          when :C
            _t, cx, cy, r, st = it
            lay, w, rgb = Sheet::STY[st]
            ent_head('CIRCLE', lay, rgb, Sheet.lineweight(w)) + pair(100, 'AcDbCircle') +
              pair(10, fx(ox + cx)) + pair(20, fx(Sheet::PH - cy)) + pair(30, 0) + pair(40, fx(r))
          when :F
            _t, pts, rgb = it
            fill_entity(pts, rgb, ox)
          when :T
            _t, x, y, str, size, col, a, rot = it
            lay, rgb = Sheet::TXT[col]
            text_entity(ox + x, Sheet::PH - y, size * 0.72, str, lay, rgb, rot, a)
          when :I
            image_entity(it, ox)
          end
        end

        def fill_entity(pts, rgb, ox)
          lay = rgb == [85, 85, 85] ? 'FRAME' : 'OUTLINE'
          return fan_solids(pts, rgb, ox, lay) if pts.size > 4
          q = pts.size == 3 ? pts + [pts[2]] : pts
          ent_head('SOLID', lay, rgb, 0) + pair(100, 'AcDbTrace') + solid_corners(q, ox)
        end

        # SOLID 점 순서: 1,2,4,3
        def solid_corners(q, ox)
          [q[0], q[1], q[3], q[2]].each_with_index.map do |(x, y), i|
            pair(10 + i, fx(ox + x)) + pair(20 + i, fx(Sheet::PH - y)) + pair(30 + i, 0)
          end.join
        end

        def fan_solids(pts, rgb, ox, lay)
          (1...pts.size - 1).map do |i|
            ent_head('SOLID', lay, rgb, 0) + pair(100, 'AcDbTrace') + solid_corners([pts[0], pts[i], pts[i + 1], pts[i + 1]], ox)
          end
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

        def image_entity(it, ox)
          _t, x, y, w, hgt, path = it
          ref = @image_paths[path] || path
          sz = @image_sizes[path] || [1000, 1000]
          pw, ph = sz
          eh = h; dh = h; rh = h
          @images << { ent: eh, def: dh, reactor: rh, path: ref, pw: pw, ph: ph }
          # 삽입점 = 이미지 좌하단(DXF 좌표). 시트 y 는 아래로 증가하므로 변환.
          llx = ox + x; lly = Sheet::PH - (y + hgt)
          s = pair(0, 'IMAGE') + pair(5, eh) + pair(330, @model_rec) + pair(100, 'AcDbEntity') + pair(8, 'IMAGE') +
              pair(100, 'AcDbRasterImage') + pair(90, 0) +
              pair(10, fx(llx)) + pair(20, fx(lly)) + pair(30, 0) +
              pair(11, fx(w / pw.to_f)) + pair(21, 0) + pair(31, 0) +
              pair(12, 0) + pair(22, fx(hgt / ph.to_f)) + pair(32, 0) +
              pair(13, fx(pw)) + pair(23, fx(ph)) +
              pair(340, dh) + pair(70, 7) + pair(280, 1) + pair(281, 50) + pair(282, 50) + pair(283, 0) +
              pair(360, rh) + pair(71, 1) + pair(91, 2) +
              pair(14, fx(-0.5)) + pair(24, fx(-0.5)) + pair(14, fx(pw - 0.5)) + pair(24, fx(ph - 0.5))
          s
        end

        BG_RGB_FOR = { 'white' => [255, 255, 255], 'dark' => [33, 37, 43] }.freeze

        def to_s
          ents = build_entities
          has_img = !@images.empty?
          layers = layer_defs
          # 핸들 사전 할당(테이블/블록/객체)
          out = +''
          out << section('HEADER',
                         pair(9, '$ACADVER') + pair(1, 'AC1015') +
                         pair(9, '$HANDSEED') + pair(5, 'FFFFF') +
                         pair(9, '$INSUNITS') + pair(70, 4) +
                         pair(9, '$LWDISPLAY') + pair(290, 1) +
                         pair(9, '$DWGCODEPAGE') + pair(3, 'ANSI_949') +
                         pair(9, '$EXTMIN') + pair(10, 0) + pair(20, 0) + pair(30, 0) +
                         pair(9, '$EXTMAX') + pair(10, fx(@pages.size * (PW_ + PAGE_GAP))) + pair(20, fx(Sheet::PH + 10)) + pair(30, 0))
          if has_img
            out << section('CLASSES',
                           class_def('IMAGE', 'AcDbRasterImage', 127, 1) +
                           class_def('IMAGEDEF', 'AcDbRasterImageDef', 0, 0) +
                           class_def('IMAGEDEF_REACTOR', 'AcDbRasterImageDefReactor', 1, 0))
          else
            out << section('CLASSES', '')
          end
          out << section('TABLES', tables(layers))
          out << section('BLOCKS', blocks)
          out << section('ENTITIES', ents.join)
          out << section('OBJECTS', objects)
          out << pair(0, 'EOF')
          out
        end

        def class_def(name, cpp, flags, proxy)
          pair(0, 'CLASS') + pair(1, name) + pair(2, cpp) + pair(3, 'ISM') + pair(90, flags) + pair(280, 0) + pair(281, proxy)
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

        def tables(layers)
          s = +''
          # VPORT
          s << table_head('VPORT', '8', 1) + pair(0, 'VPORT') + pair(5, '40') + pair(330, '8') + pair(100, 'AcDbSymbolTableRecord') +
               pair(100, 'AcDbViewportTableRecord') + pair(2, '*Active') + pair(70, 0) + pair(10, 0) + pair(20, 0) + pair(11, 1) + pair(21, 1) +
               pair(12, fx(@pages.size * (PW_ + PAGE_GAP) / 2)) + pair(22, fx(Sheet::PH / 2)) + pair(13, 0) + pair(23, 0) + pair(14, 10) + pair(24, 10) +
               pair(15, 0) + pair(25, 0) + pair(16, 0) + pair(26, 0) + pair(36, 1) + pair(17, 0) + pair(27, 0) + pair(37, 0) +
               pair(40, fx(Sheet::PH + 30)) + pair(41, 1.5) + pair(42, 50) + pair(43, 0) + pair(44, 0) + pair(50, 0) + pair(51, 0) +
               pair(71, 0) + pair(72, 100) + pair(73, 1) + pair(74, 3) + pair(75, 0) + pair(76, 0) + pair(77, 0) + pair(78, 0) + pair(0, 'ENDTAB')
          # LTYPE
          s << table_head('LTYPE', '5', 3)
          [['ByBlock', '14'], ['ByLayer', '15'], ['Continuous', '16']].each do |nm, hd|
            s << pair(0, 'LTYPE') + pair(5, hd) + pair(330, '5') + pair(100, 'AcDbSymbolTableRecord') + pair(100, 'AcDbLinetypeTableRecord') +
                 pair(2, nm) + pair(70, 0) + pair(3, nm == 'Continuous' ? 'Solid line' : '') + pair(72, 65) + pair(73, 0) + pair(40, 0)
          end
          s << pair(0, 'ENDTAB')
          # LAYER
          s << table_head('LAYER', '2', layers.size + 1)
          s << layer_rec('0', [0, 0, 0], 0.0, '10')
          layers.each { |nm, (rgb, w)| s << layer_rec(nm, rgb, w, h) }
          s << pair(0, 'ENDTAB')
          # STYLE
          s << table_head('STYLE', '3', 2)
          s << style_rec('Standard', '11') << style_rec(@style, h)
          s << pair(0, 'ENDTAB')
          # VIEW / UCS 비움, APPID
          s << pair(0, 'TABLE') + pair(2, 'VIEW') + pair(5, '6') + pair(330, 0) + pair(100, 'AcDbSymbolTable') + pair(70, 0) + pair(0, 'ENDTAB')
          s << pair(0, 'TABLE') + pair(2, 'UCS') + pair(5, '7') + pair(330, 0) + pair(100, 'AcDbSymbolTable') + pair(70, 0) + pair(0, 'ENDTAB')
          s << table_head('APPID', '9', 1) + pair(0, 'APPID') + pair(5, '12') + pair(330, '9') + pair(100, 'AcDbSymbolTableRecord') +
               pair(100, 'AcDbRegAppTableRecord') + pair(2, 'ACAD') + pair(70, 0) + pair(0, 'ENDTAB')
          s << pair(0, 'TABLE') + pair(2, 'DIMSTYLE') + pair(5, 'A') + pair(330, 0) + pair(100, 'AcDbSymbolTable') + pair(70, 0) + pair(0, 'ENDTAB')
          s << table_head('BLOCK_RECORD', '1', 2)
          [['*Model_Space', @model_rec_h], ['*Paper_Space', '1B']].each do |nm, hd|
            s << pair(0, 'BLOCK_RECORD') + pair(5, hd) + pair(330, '1') + pair(100, 'AcDbSymbolTableRecord') +
                 pair(100, 'AcDbBlockTableRecord') + pair(2, nm) + pair(340, 0)
          end
          s << pair(0, 'ENDTAB')
          s
        end

        def table_head(name, handle, count)
          pair(0, 'TABLE') + pair(2, name) + pair(5, handle) + pair(330, 0) + pair(100, 'AcDbSymbolTable') + pair(70, count)
        end

        def layer_rec(name, rgb, w, hd)
          col = Sheet.dxf_color(rgb, @bg)
          s = pair(0, 'LAYER') + pair(5, hd) + pair(330, '2') + pair(100, 'AcDbSymbolTableRecord') + pair(100, 'AcDbLayerTableRecord') +
              pair(2, name) + pair(70, 0)
          s += col.is_a?(Integer) ? pair(62, col) : pair(62, 7) + pair(420, (col[0] << 16) | (col[1] << 8) | col[2])
          s + pair(6, 'Continuous') + pair(370, Sheet.lineweight(w))
        end

        def style_rec(name, hd)
          pair(0, 'STYLE') + pair(5, hd) + pair(330, '3') + pair(100, 'AcDbSymbolTableRecord') + pair(100, 'AcDbTextStyleTableRecord') +
            pair(2, name) + pair(70, 0) + pair(40, 0) + pair(41, 1) + pair(50, 0) + pair(71, 0) + pair(42, 2.5) + pair(3, @font) + pair(4, '')
        end

        def blocks
          s = +''
          [['*Model_Space', '20', @model_rec_h], ['*Paper_Space', '1C', '1B']].each do |nm, hd, rec|
            s << pair(0, 'BLOCK') + pair(5, hd) + pair(330, rec) + pair(100, 'AcDbEntity') + pair(8, '0') +
                 pair(100, 'AcDbBlockBegin') + pair(2, nm) + pair(70, 0) + pair(10, 0) + pair(20, 0) + pair(30, 0) + pair(3, nm) + pair(1, '')
            s << pair(0, 'ENDBLK') + pair(5, hd == '20' ? '21' : '1D') + pair(330, rec) + pair(100, 'AcDbEntity') + pair(8, '0') + pair(100, 'AcDbBlockEnd')
          end
          s
        end

        def objects
          root = 'C'; imgdict = 'D1'
          s = pair(0, 'DICTIONARY') + pair(5, root) + pair(330, 0) + pair(100, 'AcDbDictionary') + pair(281, 1)
          s += pair(3, 'ACAD_IMAGE_DICT') + pair(350, imgdict) unless @images.empty?
          unless @images.empty?
            s << pair(0, 'DICTIONARY') + pair(5, imgdict) + pair(330, root) + pair(100, 'AcDbDictionary') + pair(281, 1)
            @images.each_with_index { |im, i| s << pair(3, "IMG#{i + 1}") + pair(350, im[:def]) }
            @images.each_with_index do |im, i|
              s << pair(0, 'IMAGEDEF') + pair(5, im[:def]) + pair(102, '{ACAD_REACTORS') + pair(330, imgdict) + pair(330, im[:reactor]) + pair(102, '}') +
                   pair(330, imgdict) + pair(100, 'AcDbRasterImageDef') + pair(90, 0) + pair(1, im[:path]) +
                   pair(10, fx(im[:pw])) + pair(20, fx(im[:ph])) + pair(11, 1) + pair(21, 1) + pair(280, 1) + pair(281, 0)
              s << pair(0, 'IMAGEDEF_REACTOR') + pair(5, im[:reactor]) + pair(330, im[:ent]) + pair(100, 'AcDbRasterImageDefReactor') +
                   pair(90, 2) + pair(330, im[:ent])
            end
          end
          s
        end

        def section(name, body)
          pair(0, 'SECTION') + pair(2, name) + body + pair(0, 'ENDSEC')
        end

        public

        def model_rec_handle=(v); @model_rec_h = v; end

        # CP949 바이트로 변환. 변환 불가 문자는 '?'
        def to_cp949
          @model_rec_h = '1F'
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
