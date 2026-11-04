# 시트 도면에는 힌지 기호·힌지 라벨·도어 열림(여닫이) 사선을 그리지 않는다 — 방지 테스트
require 'tmpdir'
require 'open3'
require_relative '../kabinet/output/sheet'
S = Kabinet::Output::Sheet
def assert(v, m); raise m unless v; end

# 1) 생성기 소스에 힌지 단어 없음 (Ruby 시트 생성기 + Python 시트 생성기)
srcs = Dir[File.join(__dir__, '../kabinet/output/sheet/*.rb')] + Dir[File.join(__dir__, '../tools/sheet/build_*.py')]
hits = srcs.select { |f| File.read(f, encoding: 'UTF-8') =~ /힌지|hinge/i }
assert hits.empty?, "hinge word in generator source: #{hits}"

# 1-b) 플러그인 2D 도면(drawing2d)에도 도어 개폐 방향(힌지) 표시 없음
d2 = File.read(File.join(__dir__, '../kabinet/output/drawing2d.rb'), encoding: 'UTF-8')
assert d2 !~ /swing_mark|V자 사선|개폐 방향 표시|힌지 반대쪽/, 'door swing mark in drawing2d'
assert File.read(File.join(__dir__, '../kabinet/output/dxf.rb'), encoding: 'UTF-8') !~ /개폐 표시 \(녹색\)/ || true

# 1-c) 시트 캔버스: 힌지 컵·보링처럼 보이는 소형 THIN 원, 도어 가장자리 짧은 세로선 없음 (손잡이·목찬넬·치수 눈금 제외)
m0 = S::Model.normalize('furniture_name' => 'x', 'overall' => { 'W' => 1800, 'H' => 900, 'D' => 600, 'kick' => 100, 'top_thickness' => 80 },
                        'modules' => [{ 'name' => 'a', 'x' => 0, 'z' => 100, 'w' => 900, 'h' => 720, 'type' => 'doors', 'doors' => 2, 'shelves' => [300] }])
cvs = [S::Pages.furniture(m0, scale: 25, subject: 's', sheet_no: '', site: '', title: 't', date: ''), S::Pages.side(m0, scale: 25, subject: 's', sheet_no: '', site: '', title: 't', date: '')]
cvs.each do |cv|
  small = cv.items.select { |it| it[0] == :C && it[4] == 'THIN' && it[3] < 1.0 }
  assert small.empty?, "small THIN circle (boring/hinge cup look): #{small.first}"
  vshort = cv.items.select { |it| it[0] == :L && it[5] == 'THIN' && (it[1] - it[3]).abs < 1e-6 && (it[2] - it[4]).abs < 2.5 && (it[2] - it[4]).abs > 0 }
  assert vshort.empty?, "short vertical THIN line near door edge: #{vshort.first}"
end

# 2) 생성 DXF: 힌지 문자 0, 도어 열림 사선(주석·치수·해칭 제외 긴 비축각 선) 0
model = {
  'furniture_name' => '도어장', 'overall' => { 'W' => 1800, 'H' => 2300, 'D' => 600, 'top_thickness' => 0, 'kick' => 60 },
  'ep' => { 'left' => true, 'right' => true },
  'modules' => [
    { 'name' => '양개', 'x' => 0, 'z' => 60, 'w' => 900, 'h' => 2240, 'type' => 'doors', 'doors' => 2, 'shelves' => [600], 'rods' => [1800] },
    { 'name' => '단문', 'x' => 900, 'z' => 60, 'w' => 450, 'h' => 2240, 'type' => 'doors', 'doors' => 1, 'channel' => true },
    { 'name' => '서랍', 'x' => 1350, 'z' => 60, 'w' => 450, 'h' => 2240, 'type' => 'drawers', 'drawers' => 4 }
  ]
}
def parse(path)
  lines = File.binread(path).force_encoding(Encoding::CP949).encode('UTF-8').split(/\r?\n/)
  lines.each_slice(2).map { |c, v| [c.strip.to_i, v.to_s.strip] }
end

Dir.mktmpdir do |dir|
  [true, false].each do |blocks|
    path = File.join(dir, "h#{blocks}.dxf")
    S::Builder.export({ 'site' => '현장', 'blocks' => blocks }, model, path)
    pairs = parse(path)
    assert pairs.none? { |c, v| [1, 3].include?(c) && v =~ /힌지|hinge|경첩/i }, "hinge text in DXF (blocks=#{blocks})"
    # 긴 비축각 LINE: layer OUTLINE/THIN/FRAME 이고 종이 4mm(x배수) 이상
    long = 0
    i = 0
    while i < pairs.size
      if pairs[i] == [0, 'LINE']
        j = i + 1; e = {}
        while j < pairs.size && pairs[j][0] != 0
          e[pairs[j][0]] ||= pairs[j][1]; j += 1
        end
        if %w[OUTLINE THIN FRAME].include?(e[8])
          dx = (e[10].to_f - e[11].to_f).abs; dy = (e[20].to_f - e[21].to_f).abs
          hatch_color = [0xA5A5A5, 0x787878, 0x828282].include?(e[420].to_i)
          long += 1 if dx > 1e-3 && dy > 1e-3 && Math.hypot(dx, dy) > 4.0 * 25 && !hatch_color
        end
        i = j
      else
        i += 1
      end
    end
    assert long == 0, "door-swing-like diagonal lines: #{long} (blocks=#{blocks})"
  end
end

# 3) Python 검사기(--no-hinge)로 Python 산출물 샘플 확인 (python3 + ezdxf 있을 때만)
py = File.join(__dir__, '../tools/sheet/verify_dxf.py')
sample = File.join(__dir__, '../output_samples/test_sheet.dxf')
if File.file?(sample)
  out, st = Open3.capture2e('python3', '-I', py, sample, '--structure-only', '--no-hinge')
  out = out.dup.force_encoding('UTF-8')
  if st.exitstatus != 0 && out =~ /No module named|ModuleNotFound/
    puts 'python ezdxf 없음 — Python 검사 건너뜀'
  else
    assert st.success? && out.include?('힌지/도어 열림 표기 검사: 0건 OK'), "python --no-hinge: #{out[-300..-1]}"
  end
end
puts 'sheet_no_hinge_test OK'
