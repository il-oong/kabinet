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
cfg = { 'site' => '판교 푸르지오 그랑블', 'furniture_name' => '__-1' }

Dir.mktmpdir do |dir|
  path = File.join(dir, 'out.dxf')
  r = S::Builder.export(cfg, model, path)
  assert File.file?(path), 'dxf not written'
  assert r[:pages] == 7, "pages #{r[:pages]}"            # 기본 구성: 사진·3D·평면도·가구·측면·상세·확인표
  sec = parse_dxf(path)
  assert %w[HEADER CLASSES TABLES BLOCKS ENTITIES OBJECTS].all? { |n| sec.key?(n) }, "sections #{sec.keys}"
  assert sec['HEADER'].include?([1, 'AC1015']), 'version'
  ents = entities(sec['ENTITIES'])
  types = ents.map { |e| e[:type] }.tally
  assert types['LINE'] > 500 && types['TEXT'] > 100 && types['LWPOLYLINE'] > 50 && types['CIRCLE'] > 3, "types #{types}"
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

puts 'sheet_dxf_test OK'
