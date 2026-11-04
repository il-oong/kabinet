# 제작도면 시트 DXF 생성기 (순수 Ruby) 단위 테스트
require 'tmpdir'
require_relative '../kabinet/output/sheet'
S = Kabinet::Output::Sheet
def assert(v, m); raise m unless v; end

# 간단한 DXF 파서 → 엔티티 [{type:, layer:, pairs: [[code,val]...]}]
def parse_dxf(path)
  lines = File.binread(path).force_encoding(Encoding::CP949).encode('UTF-8').split(/\r?\n/)
  pairs = lines.each_slice(2).map { |c, v| [c.strip.to_i, v.to_s] }
  sections = {}
  cur = nil; name = nil
  pairs.each do |c, v|
    if c == 0 && v == 'SECTION' then cur = []; next end
    if cur && cur.empty? && c == 2 && name.nil? then name = v; next end
    if c == 0 && v == 'ENDSEC' then sections[name] = cur; cur = nil; name = nil; next end
    cur << [c, v] if cur
  end
  sections
end

def entities(sec)
  ents = []
  sec.each do |c, v|
    if c == 0 then ents << { type: v, pairs: [] } else ents.last[:pairs] << [c, v] if ents.last end
  end
  ents.each { |e| e[:layer] = (e[:pairs].find { |c, _| c == 8 } || [])[1] }
  ents
end

model = {
  'furniture_name' => '테스트장', 'overall' => { 'W' => 1800, 'H' => 2300, 'D' => 600, 'top_thickness' => 0, 'kick' => 60 },
  'ep' => { 'left' => true, 'right' => true },
  'modules' => [
    { 'name' => '도어장', 'x' => 0, 'z' => 60, 'w' => 900, 'h' => 2240, 'type' => 'doors', 'doors' => 2, 'shelves' => [600, 1200], 'rods' => [1800] },
    { 'name' => '서랍', 'x' => 900, 'z' => 60, 'w' => 900, 'h' => 2240, 'type' => 'drawers', 'drawers' => 4 }
  ]
}
cfg = { 'site' => '판교 푸르지오 그랑블', 'furniture_name' => '__-1', 'blocks' => false }

Dir.mktmpdir do |dir|
  path = File.join(dir, 'out.dxf')
  r = S::Builder.export(cfg, model, path)
  assert File.file?(path), 'dxf not written'
  assert r[:pages] == 7, "pages #{r[:pages]}"            # 기본 구성: 사진·3D·평면도·가구·측면·상세·확인표
  sec = parse_dxf(path)
  assert %w[HEADER CLASSES TABLES BLOCKS ENTITIES OBJECTS].all? { |n| sec.key?(n) }, "sections #{sec.keys}"
  assert sec['HEADER'].include?([1, 'AC1018']), 'version'
  ents = entities(sec['ENTITIES'])
  types = ents.map { |e| e[:type] }.tally
  assert types['LINE'] > 200 && types['HATCH'].to_i > 5 && types['TEXT'] > 100 && types['LWPOLYLINE'] > 50 && types['CIRCLE'] > 3, "types #{types}"
  assert types['SOLID'].to_i >= 7 + 10, "solid (BG 7 + fills) #{types['SOLID']}"
  layers = ents.map { |e| e[:layer] }.uniq
  %w[OUTLINE DIM THIN NOTE_BLUE NOTE_RED FRAME TEXT BG].each { |l| assert layers.include?(l), "layer #{l} missing in #{layers}" }
  assert ents.count { |e| e[:layer] == 'BG' } == 7, 'BG per sheet'
  # 한글 텍스트 보존 (CP949 round trip)
  texts = ents.select { |e| e[:type] == 'TEXT' }.map { |e| e[:pairs].find { |c, _| c == 1 }[1] }
  assert texts.include?('판교 푸르지오 그랑블') && texts.include?('__-1') && texts.include?('SITE LOCATION'), 'texts'
  assert texts.include?('SITE PHOTO') && texts.include?('3D VIEW') && texts.include?('TOP VIEW'), 'headers'
  # 스타일 / 폰트
  tabs = sec['TABLES']
  assert tabs.include?([3, 'malgun.ttf']), 'font file in STYLE'
  assert tabs.include?([2, 'MALGUN']), 'style name'
  # 이미지 없음 → IMAGE 엔티티/IMAGEDEF 없음, 도곽은 있음
  assert !types.key?('IMAGE'), 'no image expected'
  # 시트 X 배치: 마지막 시트 프레임 x 가 6*(420+80) 부근
  xs = ents.select { |e| e[:type] == 'LINE' }.map { |e| e[:pairs].find { |c, _| c == 10 }[1].to_f }
  assert xs.max > 6 * 500, "sheet offsets #{xs.max}"
end

# 배경 옵션: dark → BG 레이어 어두운 TrueColor, 선 색은 밝게 / none → BG 없음, 검정은 ACI 7
Dir.mktmpdir do |dir|
  %w[white dark none].each do |bg|
    path = File.join(dir, "#{bg}.dxf")
    S::Builder.export(cfg.merge('bg' => bg), model, path, only_ids: nil)
    ents = entities(parse_dxf(path)['ENTITIES'])
    bgs = ents.select { |e| e[:layer] == 'BG' }
    if bg == 'none'
      assert bgs.empty?, 'none: no BG'
      outl = ents.find { |e| e[:layer] == 'OUTLINE' && e[:type] == 'LINE' }
      assert outl[:pairs].include?([62, '7']), 'none: ACI 7'
    else
      assert bgs.size == 7, "#{bg}: BG sheets"
      col = bgs.first[:pairs].find { |c, _| c == 420 }[1].to_i
      assert(bg == 'white' ? col == 0xFFFFFF : col == ((33 << 16) | (37 << 8) | 43), "#{bg}: bg color #{col}")
      outl = ents.find { |e| e[:layer] == 'OUTLINE' && e[:type] == 'LINE' }
      c = outl[:pairs].find { |cc, _| cc == 420 }[1].to_i
      assert(bg == 'white' ? c == 0 : c == 0xFFFFFF, "#{bg}: outline color #{c}")
    end
  end
end

# 페이지 선택/숨김, 시트 번호
cfg2 = S::Builder.normalize_config(cfg)
pages = cfg2['pages']
ids = pages.select { |p| %w[furniture side].include?(p['type']) }.map { |p| p['id'] }
cv = S::Builder.build(cfg2, model, only_ids: ids)
assert cv.size == 2 && cv.map(&:name) == %w[furniture side], 'only_ids'
t = cv.first.items.select { |i| i[0] == :T }.map { |i| i[3] }
assert t.include?('NO.001'), 'sheet no'
hidden = S::Builder.normalize_config(cfg2.merge('pages' => pages.map { |p| p['type'] == 'table' ? p.merge('hidden' => true) : p }))
assert S::Builder.build(hidden, model).size == 6, 'hidden'

# ── 이미지(IMAGE/IMAGEDEF) 포함 ──────────────────────────────────────
require 'zlib'
def make_png(w, h)
  chunk = ->(type, data) { [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N') }
  raw = ("\x00".b + "\xFF\x80\x00".b * w) * h
  "\x89PNG\r\n\x1a\n".b + chunk.call('IHDR', [w, h, 8, 2, 0, 0, 0].pack('NNCCCCC')) + chunk.call('IDAT', Zlib::Deflate.deflate(raw)) + chunk.call('IEND', ''.b)
end
def make_jpeg(w, h)   # SOI + APP0 + SOF0 (헤더만 — 크기 파싱 검증용)
  "\xFF\xD8".b + "\xFF\xE0".b + [16].pack('n') + "JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00".b +
    "\xFF\xC0".b + [17].pack('n') + [8, h, w, 3].pack('CnnC') + "\x01\x22\x00\x02\x11\x01\x03\x11\x01".b + "\xFF\xD9".b
end

Dir.mktmpdir do |dir|
  png = File.join(dir, '거실 사진.png'); File.binwrite(png, make_png(40, 30))
  jpg = File.join(dir, 'kitchen.jpg');  File.binwrite(jpg, make_jpeg(64, 48))
  assert S::ImageInfo.size(png) == [40, 30] && S::ImageInfo.size(jpg) == [64, 48], 'image size parse'
  c3 = S::Builder.normalize_config(cfg)
  c3['pages'] = [S::Builder.page('photos', '현장사진', 'images' => [{ 'path' => png, 'caption' => '거실' }, { 'path' => jpg, 'caption' => '주방' }, { 'path' => '/없는/파일.png', 'caption' => '누락' }]),
                 S::Builder.page('view3d', '상담 3D', 'images' => [{ 'path' => png, 'caption' => '3D' }])]
  out_dir = File.join(dir, 'out'); Dir.mkdir(out_dir)
  path = File.join(out_dir, '도면.dxf')
  r = S::Builder.export(c3, model, path)
  assert r[:pages] == 2, "pages #{r[:pages]}"
  assert r[:images_dir] && File.basename(r[:images_dir]) =~ /\Asheet_[0-9a-f]{6}_images\z/ && r[:copied].size == 2, "copied #{r[:copied]}"   # 같은 파일은 한 번만, 누락 파일은 복사 안 함(ASCII 폴더)
  assert Dir.children(r[:images_dir]).map { |f| f.dup.force_encoding('UTF-8') }.sort == ['img_01.png', 'img_02.jpg'], 'image files (ASCII 이름)'
  sec = parse_dxf(path)
  assert sec['CLASSES'].include?([1, 'IMAGE']) && sec['CLASSES'].include?([1, 'IMAGEDEF']), 'classes'
  ents = entities(sec['ENTITIES'])
  imgs = ents.select { |e| e[:type] == 'IMAGE' }
  assert imgs.size == 3, "IMAGE entities #{imgs.size}"        # 사진 2 + 3D 1 (누락 파일은 IMAGE 없이 틀만)
  assert imgs.all? { |e| e[:layer] == 'IMAGE' }, 'IMAGE layer'
  frames = ents.select { |e| e[:layer] == 'IMAGE_FRAME' }
  assert frames.size >= 4, 'image frame rectangles on own layer'
  objs = sec['OBJECTS']
  defs = objs.each_index.select { |i| objs[i] == [0, 'IMAGEDEF'] }
  assert defs.size == imgs.size, 'imagedef per image'
  paths = objs.each_cons(2).select { |a, _| a[0] == 1 }.map { |a, _| a[1] }
  paths = objs.select { |c, v| c == 1 && v =~ /_images\// }.map { |_, v| v }
  assert paths.sort.uniq == %w[img_01.png img_02.jpg].map { |n| "#{File.basename(r[:images_dir])}/#{n}" }, "relative ASCII paths #{paths}"
  assert paths.all? { |v| v.ascii_only? && v !~ /[ ()]/ }, 'ASCII-safe IMAGEDEF paths'
  assert objs.include?([0, 'IMAGEDEF_REACTOR']) && objs.include?([3, 'ACAD_IMAGE_DICT']), 'reactor/dict'
  # 이미지가 없어도 도곽만 있는 DXF 로 열림
  path2 = File.join(out_dir, 'empty.dxf')
  S::Builder.export(S::Builder.normalize_config(cfg).merge('pages' => [S::Builder.page('photos', '현장사진')]), model, path2)
  e2 = entities(parse_dxf(path2)['ENTITIES'])
  assert e2.none? { |e| e[:type] == 'IMAGE' } && e2.any? { |e| e[:layer] == 'FRAME' }, 'empty photo page frame only'
end

# ── (v1.25) ezdxf 형 골격 구조 검사: 핸들 유일·참조 해소·LAYOUT/DICTIONARY/DIMSTYLE/CLASSES ─────────────
def structure_problems(path)
  lines = File.binread(path).force_encoding(Encoding::CP949).encode('UTF-8').split(/\r?\n/)
  pairs = lines.each_slice(2).map { |c, v| [c.strip, v.to_s.strip] }
  sec = nil; defs = Hash.new(0); refs = []; cur0 = nil; seed = nil; objs = Hash.new(0); classes = 0
  pairs.each_with_index do |(c, v), i|
    sec = pairs[i + 1][1] if c == '0' && v == 'SECTION'
    if c == '0'
      cur0 = v
      objs[v] += 1 if sec == 'OBJECTS'
      classes += 1 if sec == 'CLASSES' && v == 'CLASS'
    end
    seed = pairs[i + 1][1] if c == '9' && v == '$HANDSEED'
    next unless %w[TABLES BLOCKS ENTITIES OBJECTS].include?(sec)
    defs[v.upcase] += 1 if %w[5 105].include?(c)
    refs << [v.upcase, c, cur0] if %w[330 340 350 360 390].include?(c) && v != '0' && !v.empty?
  end
  probs = []
  probs << "dup handles #{defs.select { |_, n| n > 1 }.keys.first(3)}" if defs.any? { |_, n| n > 1 }
  miss = refs.reject { |h, _, _| defs.key?(h) }
  probs << "unresolved refs #{miss.first(3)}" unless miss.empty?
  probs << "HANDSEED #{seed} <= max" if seed.nil? || seed.to_i(16) <= defs.keys.map { |h| h.to_i(16) }.max
  probs << "LAYOUT #{objs['LAYOUT']}" if objs['LAYOUT'] < 2
  probs << "DICTIONARY #{objs['DICTIONARY']}" if objs['DICTIONARY'] < 10
  probs << "CLASSES #{classes}" if classes < 10
  probs << 'DIMSTYLE Standard' unless pairs.each_cons(8).any? { |a| a[0] == %w[0 DIMSTYLE] && a.include?(%w[2 Standard]) }
  names = []
  k = pairs.index(%w[0 DICTIONARY]) + 1
  while pairs[k][0] != '0' do names << pairs[k][1] if pairs[k][0] == '3'; k += 1 end
  %w[ACAD_GROUP ACAD_LAYOUT ACAD_MLINESTYLE ACAD_PLOTSETTINGS ACAD_PLOTSTYLENAME ACAD_MATERIAL ACAD_COLOR ACAD_VISUALSTYLE].each { |n| probs << "root dict #{n}" unless names.include?(n) }
  br = pairs.each_index.select { |i| pairs[i] == %w[0 BLOCK_RECORD] }.map { |i| pairs[i + 1, 14] }
  probs << 'BLOCK_RECORD 340' unless br.size >= 2 && br.first(2).all? { |b| b.any? { |c, v| c == '340' && v != '0' } }
  probs
end

Dir.mktmpdir do |dir|
  path = File.join(dir, 's.dxf')
  S::Builder.export(cfg, model, path)
  probs = structure_problems(path)
  assert probs.empty?, "structure: #{probs}"
  # 이미지가 있어도 구조 유지 + images:false 는 IMAGE/IMAGEDEF 를 쓰지 않는다
  png = File.join(dir, '사진 (1).png'); File.binwrite(png, make_png(40, 30))
  imgcfg = S::Builder.normalize_config(cfg)
  imgcfg['pages'] = [S::Builder.page('photos', '현장사진', 'images' => [{ 'path' => png, 'caption' => '사진 (1)' }])]
  p1 = File.join(dir, 'with.dxf'); r1 = S::Builder.export(imgcfg, model, p1)
  assert r1[:copied].size == 1 && structure_problems(p1).empty?, "image structure #{structure_problems(p1)}"
  p2 = File.join(dir, 'without.dxf'); r2 = S::Builder.export(imgcfg.merge('images' => false), model, p2)
  s2 = parse_dxf(p2)
  assert r2[:copied].empty? && entities(s2['ENTITIES']).none? { |e| e[:type] == 'IMAGE' }, 'images:false -> no IMAGE'
  assert s2['OBJECTS'].none? { |c, v| c == 0 && v == 'IMAGEDEF' } && structure_problems(p2).empty?, 'images:false -> no IMAGEDEF'
  assert entities(s2['ENTITIES']).any? { |e| e[:layer] == 'IMAGE_FRAME' }, 'frame kept without images'
end

# ── 1:1 실치수: 도곽 = 420x297 × 축척 배수, 가구 외곽 폭 = 입력 W ────────────────────────────────────────
Dir.mktmpdir do |dir|
  c = S::Builder.normalize_config(cfg)
  c['pages'] = [S::Builder.page('furniture', '가구', 'scale' => '25')]
  pr = File.join(dir, 'paper.dxf'); S::Builder.export(c.merge('real_scale' => false), model, pr)
  rl = File.join(dir, 'real.dxf'); S::Builder.export(c.merge('real_scale' => true), model, rl)
  def frame_w(path)
    es = entities(parse_dxf(path)['ENTITIES']).select { |e| e[:type] == 'SOLID' && e[:layer] == 'BG' }
    pts = es.first[:pairs].select { |c, _| c == 11 }.map { |_, v| v.to_f }
    pts.first
  end
  assert (frame_w(pr) - 420.0).abs < 0.01, 'paper frame 420'
  assert (frame_w(rl) - 10_500.0).abs < 0.01, "real frame #{frame_w(rl)}"      # 420 x 25
  xs = entities(parse_dxf(rl)['ENTITIES']).select { |e| e[:type] == 'LWPOLYLINE' && e[:layer] == 'OUTLINE' }.map do |e|
    v = e[:pairs].select { |cc, _| cc == 10 }.map { |_, q| q.to_f }; [v.min, v.max]
  end
  widths = xs.map { |a, b| (b - a).round(1) }
  assert widths.include?(1800.0), "furniture outline width 1800 mm in real scale: #{widths.uniq.first(8)}"
end

# ── 뷰를 이름 있는 BLOCK + INSERT 로, 해칭은 영역당 HATCH 1개 ───────────────────────────────────────
Dir.mktmpdir do |dir|
  path = File.join(dir, 'blk.dxf')
  S::Builder.export(cfg.merge('blocks' => true, 'real_scale' => true), model, path)
  sec = parse_dxf(path)
  assert structure_problems(path).empty?, "block structure #{structure_problems(path)}"
  bnames = []
  sec['BLOCKS'].each_with_index { |(c, v), i| bnames << sec['BLOCKS'][(i + 1)..-1].find { |cc, _| cc == 2 }[1] if c == 0 && v == 'BLOCK' }
  user = bnames.reject { |n| n.start_with?('*') }
  assert user.include?('FRAME_SHEET1') && user.any? { |n| n =~ /\AVIEW_TOP_S\d+\z/ } && user.any? { |n| n =~ /\AVIEW_FRONT_DOOR_S\d+\z/ } &&
         user.any? { |n| n =~ /\ASECTION_1_S\d+\z/ } && user.any? { |n| n =~ /\ANOTE_S\d+\z/ }, "block names #{user}"
  ents = entities(sec['ENTITIES'])
  inserts = ents.select { |e| e[:type] == 'INSERT' }
  assert inserts.size == user.size, "INSERT #{inserts.size} == blocks #{user.size}"
  assert ents.none? { |e| %w[LINE LWPOLYLINE TEXT CIRCLE].include?(e[:type]) && e[:layer] != 'SHEET_FRAME_INFO' }, 'only INSERT/BG/info in model space'
  inner = entities(sec['BLOCKS'])
  hatches = inner.select { |e| e[:type] == 'HATCH' }
  assert hatches.size >= 4, "HATCH per area #{hatches.size}"
  assert hatches.all? { |e| e[:pairs].include?([2, 'ANSI31']) }, 'ANSI31 pattern'
  # 해칭 낱개 선 없음: THIN 레이어의 회색 45° LINE 이 반복되지 않는다
  diag = inner.select do |e|
    next false unless e[:type] == 'LINE' && e[:layer] == 'THIN'
    v = e[:pairs].to_h { |c, q| [c, q] }
    (v[10].to_f - v[11].to_f).abs > 1e-6 && ((v[10].to_f - v[11].to_f).abs - (v[20].to_f - v[21].to_f).abs).abs < 1e-3
  end
  assert diag.size < 8, "loose hatch lines #{diag.size}"
  # 블록 정의 안 좌표는 실치수(시트 원점 기준) — 도곽 외곽이 10,500 근처까지
  # blocks:false 면 낱개 + 블록 정의 없음
  p2 = File.join(dir, 'flat.dxf'); S::Builder.export(cfg.merge('blocks' => false), model, p2)
  s2 = parse_dxf(p2)
  assert entities(s2['ENTITIES']).none? { |e| e[:type] == 'INSERT' } && s2['BLOCKS'].none? { |c, v| c == 2 && v =~ /_S\d+\z|FRAME_SHEET/ }, 'blocks off'
end

# ── 모듈별 손잡이: 채널·바 혼합 가구에서 채널 보정은 채널 모듈에만 ──────────────────────────────
mixed = S::Model.normalize(
  'furniture_name' => '혼합', 'overall' => { 'W' => 1200, 'H' => 1000, 'D' => 600, 'kick' => 100 },
  'modules' => [{ 'name' => 'C', 'x' => 0, 'z' => 100, 'w' => 600, 'h' => 800, 'type' => 'doors', 'doors' => 1, 'channel' => true },
                { 'name' => 'B', 'x' => 600, 'z' => 100, 'w' => 600, 'h' => 800, 'type' => 'doors', 'doors' => 1, 'channel' => false }]
)
fc = S::Pages.fronts_for(mixed, mixed['modules'][0]); fb = S::Pages.fronts_for(mixed, mixed['modules'][1])
assert fc == [[104, 875.0]] || fc == [[104.0, 875.0]], "channel module door (상판 하면 25 아래, 천판 EP 없음) #{fc}"
assert fb == [[104, 896.0]] || fb == [[104.0, 896.0]], "bar module door unaffected #{fb}"
spec = { 'width' => 1200, 'max_depth' => 600, 'base_height' => 100, 'run_mode' => true, 'run_height' => 800,
         'modules' => [{ 'kind' => 'shelf_module', 'width' => 600, 'height' => 800, 'handle_type' => 'channel', 'door_config' => 'single' },
                       { 'kind' => 'shelf_module', 'width' => 600, 'height' => 800, 'handle_type' => 'bar', 'door_config' => 'single' }] }
ms = S::Model.from_spec(spec)
assert ms['modules'].map { |m| m['channel'] } == [true, false] && ms['channel'] == true, 'per-module channel kept from spec'
assert S::Pages.furniture(ms, { scale: 25, subject: 's', sheet_no: '', site: '', title: 't', date: '' }).items.size > 50, 'mixed sheet builds'

# 도곽 블록(FRAME_SHEET*)에는 도곽·표제란만 — 치수선(DIM)·마커(CIRCLE)가 뷰 블록 밖에 남지 않는다
Dir.mktmpdir do |dir|
  path = File.join(dir, 'f.dxf')
  S::Builder.export(cfg.merge('blocks' => true), model, path)
  blk = parse_dxf(path)['BLOCKS']
  cur = nil; stray = 0
  blk.each do |c, v|
    if c == 0 && v == 'BLOCK' then cur = :next
    elsif cur == :next && c == 2 then cur = v
    elsif c == 0 then (cur = nil if v == 'ENDBLK'); stray += 1 if cur.is_a?(String) && cur.start_with?('FRAME_SHEET') && v == 'CIRCLE'
    elsif c == 8 && cur.is_a?(String) && cur.start_with?('FRAME_SHEET') && v == 'DIM' then stray += 1
    end
  end
  assert stray == 0, "view elements in FRAME_SHEET blocks: #{stray}"
end

puts 'sheet_dxf_test OK'
