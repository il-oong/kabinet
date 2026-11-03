# 입력 CAD DXF(치수·라벨) → 시트 모델 재구성 단위 테스트 (합성 DXF, 순수 Ruby)
require 'tmpdir'
require_relative '../kabinet/output/sheet'
S = Kabinet::Output::Sheet
def assert(v, m); raise m unless v; end

def pairs(*kv) = kv.each_slice(2).map { |c, v| "#{c}\n#{v}" }.join("\n")
def dim(x, y, x3, y3, x4, y4, meas, rot = 0)
  pairs(0, 'DIMENSION', 8, 'SH-DIM', 10, x, 20, y, 13, x3, 23, y3, 14, x4, 24, y4, 70, 0, 50, rot, 42, meas)
end
def mtext(x, y, h, t) = pairs(0, 'MTEXT', 8, 'TXT', 10, x, 20, y, 40, h, 1, t)

# 주방 하부장 모양: 평면(위) 900+652 / 깊이 600, 정면(아래) 높이 912 = 900 + 상판 12, 걸레받이 100
body = [
  dim(2321, -2303, 769, -2383, 2321, -2383, 1552),
  dim(639, -2433, 719, -3033, 719, -2433, 600, 90),
  dim(1669, -3163, 769, -3083, 1669, -3083, 900),
  dim(2321, -3163, 1669, -3083, 2321, -3083, 652),
  dim(860, -3782, 940, -4694, 940, -3782, 912, 90),
  dim(2802, -3782, 2722, -3794, 2722, -3782, 12, 90),
  dim(2802, -4594, 2722, -4694, 2722, -4594, 100, 90),
  mtext(1215, -2729, 50, '조리장(2D)B'), mtext(1992, -2729, 50, '서랍장(2단)M'),
  mtext(2730, -955, 92.8, '주방 하부장-1'),
  mtext(3000, -3000, 50, 'EP 판넬 / 밑장용 [18T]'),
  mtext(3500, -2703, 42, '주방장 도어\\P공용 부엌 도어')
]
dxf = ["0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n0\nSECTION\n2\nENTITIES", *body, "0\nENDSEC\n0\nEOF"].join("\n")

doc = S::DxfReader.parse(dxf)
assert doc.of('DIMENSION').size == 7 && doc.insunits == 4, 'reader counts'
assert doc.of('MTEXT').map { |e| S::DxfReader.clean_mtext(e[:text]) }.include?('주방장 도어' + "\n" + '공용 부엌 도어'), 'mtext \\P'

r = S::DxfImport.from_doc(doc, name_hint: 'x')
assert r[:name] == '주방 하부장', "title #{r[:name]}"
assert r[:models].size == 1, 'one side'
m = r[:models][0]
o = m['overall']
assert [o['W'], o['D'], o['H'], o['top_thickness'], o['kick']] == [1552.0, 600.0, 912.0, 12.0, 100.0], "overall #{o}"
assert m['modules'].map { |x| x['name'] } == ['조리장(2D)B', '서랍장(2단)M'], 'module names'
assert m['modules'].map { |x| x['w'] } == [900.0, 652.0] && m['modules'].map { |x| x['x'] } == [0.0, 900.0], 'module widths/x'
assert m['modules'][0]['type'] == 'doors' && m['modules'][0]['doors'] == 2, 'doors'
assert m['modules'][1]['type'] == 'drawers' && m['modules'][1]['drawers'] == 2, 'drawers'
assert m['ep']['left'] && m['ep']['thickness'] == 18.0, 'ep'
assert m['notes']['DOOR'].include?('공용 부엌 도어'), 'door note'
assert m['flags'].any? { |f| f.include?('확인필요') }, 'flag'

# 모델 → 시트 DXF 까지 이어짐
Dir.mktmpdir do |dir|
  out = File.join(dir, '재구성.dxf')
  res = S::Builder.export({ 'bg' => 'white' }, m, out)
  assert File.size(out) > 1000 && res[:pages] >= 4, 'sheet exported'
end

# 치수가 없으면 기본 모델 + 확인필요
r0 = S::DxfImport.from_doc(S::DxfReader.parse("0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF"), name_hint: '빈도면')
assert r0[:models][0]['flags'].any? { |f| f.include?('읽지 못함') }, 'empty fallback'
puts 'sheet_import_test OK'
