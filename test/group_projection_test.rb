# 순수 루비 자가 검증 — SketchUp 불필요.
# 실행: ruby test/group_projection_test.rb  (또는 SketchUp Ruby 콘솔에서 load)
$LOAD_PATH.unshift(File.expand_path('..', __dir__))

module Kabinet; module Output; end; end
require_relative '../kabinet/output/dxf'
require_relative '../kabinet/output/group_projection'
require_relative '../kabinet/output/order_sheet' unless defined?(Sketchup)

GP = Kabinet::Output::GroupProjection

# 900W × 580D × 720H 박스의 12개 엣지
w, d, h = 900.0, 580.0, 720.0
pts = [[0,0,0],[w,0,0],[w,d,0],[0,d,0],[0,0,h],[w,0,h],[w,d,h],[0,d,h]]
segs = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
       .map { |a, b| [pts[a], pts[b]] }

views = GP.views_from_segments(segs)
front, side, top = views

raise "front size #{front[:width]}x#{front[:height]}" unless front[:width] == w && front[:height] == h
raise "side size"  unless side[:width] == d && side[:height] == h
raise "top size"   unless top[:width] == w && top[:height] == d

# 박스 12엣지 → 각 뷰에서 앞/뒤 면이 겹쳐 4개 선으로 dedupe, 깊이 방향 4개는 점으로 붕괴
[front, side, top].each do |v|
  raise "#{v[:name]} lines=#{v[:lines].size} (expected 4)" unless v[:lines].size == 4
end

raise 'size_string' unless GP.size_string(segs) == '900W x 580D x 720H'

# 유닛(장) 분할 치수: 400 + 500 두 장, 오른쪽 장은 높이 500 (전체 720과 다름)
units = [
  { name: 'A', min: [0, 0, 0],   max: [400, 580, 720] },
  { name: 'B', min: [400, 0, 0], max: [900, 580, 500] }
]
v2 = GP.views_from_segments(segs, units: units)
f2 = v2[0]
# 전체 2개(W,H) + 유닛 폭 체인 2개 + B 높이 1개 = 5
raise "front dims=#{f2[:dims].size} (expected 5)" unless f2[:dims].size == 5
# 체인은 안쪽(-off), 전체 폭은 바깥(-off*2.1) — 그 사이 임계값으로 분리
chain = f2[:dims].select { |dd| dd[:dir] == :h && dd[:offset] > -GP.dim_off(900, 720) * 1.5 }
raise "chain widths #{chain.map { |c| c[:text] }}" unless chain.map { |c| c[:text] }.sort == %w[400 500]
raise 'unit B height dim missing' unless f2[:dims].any? { |dd| dd[:dir] == :v && dd[:text] == '500' }

# 유닛 1개면 분할 치수 생략 (전체 치수와 중복)
v1 = GP.views_from_segments(segs, units: [units[0]])
raise 'single unit should add no dims' unless v1[0][:dims].size == 2

# 치수 끄기 옵션
v0 = GP.views_from_segments(segs, units: units, dim_overall: false, dim_units: false)
raise 'dims should be off' unless v0.all? { |vv| vv[:dims].empty? }

# 뷰별 세그먼트 오버라이드 (은선 제거 결과 주입) — front는 바닥 4엣지만
# 바닥 사각형은 정면 투영에서 수평선 1개로 합쳐짐 (앞뒤 dedupe + 깊이 붕괴)
vo = GP.views_from_segments(segs, view_segs: { 'front' => segs.first(4) })
raise "front override lines=#{vo[0][:lines].size} (expected 1)" unless vo[0][:lines].size == 1
raise 'side keeps full segs' unless vo[1][:lines].size == 4

# bbox_segments — 12엣지
bb = GP.bbox_segments([0, 0, 0], [100, 200, 300])
raise 'bbox 12 edges' unless bb.size == 12

# 치수 반올림 + 천단위 쉼표
raise 'round 1'   unless GP.fmt(899.3, 1)    == '899'
raise 'round 5'   unless GP.fmt(727.3, 5)    == '725'
raise 'round 10'  unless GP.fmt(2235.4, 10)  == '2,240'
raise 'round 0.1' unless GP.fmt(899.34, 0.1) == '899.3'
raise 'comma'     unless GP.fmt(3150, 1)     == '3,150'
raise 'no comma <1000' unless GP.fmt(900, 1) == '900'

# 소단위/대단위 레벨 분리: 세부(높이)는 안쪽(l1), 전체는 바깥(l2), 모두 우측
units3 = [
  { name: 'A', min: [0, 0, 0],   max: [300, 580, 500] },
  { name: 'B', min: [300, 0, 0], max: [600, 580, 500] },
  { name: 'C', min: [600, 0, 0], max: [900, 580, 720] }
]
v3 = GP.views_from_segments(segs, units: units3)
vdims = v3[0][:dims].select { |dd| dd[:dir] == :v && dd[:x1] == 900.0 }
# 세부 높이 500(1회, 720은 전체와 같아 생략) + 전체 높이 720 = 2, 모두 우측
raise "right v-dims=#{vdims.size} (expected 2)" unless vdims.size == 2
sub  = vdims.select { |dd| dd[:text] == '500' }
over = vdims.select { |dd| dd[:text] == '720' }
raise 'sub height 500 missing' unless sub.size == 1
raise 'overall height 720 missing' unless over.size == 1
# 대단위(전체) 오프셋이 소단위(세부)보다 바깥
raise 'overall must be outermost' unless over.first[:offset] > sub.first[:offset]

# EQ: 300폭 3연속(A/B/C) → EQ 텍스트 3개
eqv = GP.views_from_segments(segs, units: [
  { name: 'A', min: [0, 0, 0],   max: [300, 580, 720] },
  { name: 'B', min: [300, 0, 0], max: [600, 580, 720] },
  { name: 'C', min: [600, 0, 0], max: [900, 580, 720] }
], eq: true)
raise 'EQ texts expected 3' unless eqv[0][:texts].count { |t| t[:text] == 'EQ' } == 3
# eq 끄면 EQ 없음
noeq = GP.views_from_segments(segs, units: [
  { name: 'A', min: [0, 0, 0],   max: [300, 580, 720] },
  { name: 'B', min: [300, 0, 0], max: [600, 580, 720] },
  { name: 'C', min: [600, 0, 0], max: [900, 580, 720] }
], eq: false)
raise 'EQ off should add none' unless noeq[0][:texts].none? { |t| t[:text] == 'EQ' }

# 세부 치수 간소화: 전체(900) 10%=90 미만 유닛 폭 생략
# 850 + 50 → 50짜리 유닛 치수 생략, 850만 표기
uf = GP.views_from_segments(segs, units: [
  { name: 'big',  min: [0, 0, 0],   max: [850, 580, 720] },
  { name: 'tiny', min: [850, 0, 0], max: [900, 580, 720] }
], min_frac: 0.1)
wchain = uf[0][:dims].select { |dd| dd[:dir] == :h && dd[:offset] > -GP.dim_off(900, 720) * 1.5 }
raise "simplify: #{wchain.map { |c| c[:text] }}" unless wchain.map { |c| c[:text] } == %w[850]

# min_frac 0이면 전부 표기 (850, 50 둘 다)
uf0 = GP.views_from_segments(segs, units: [
  { name: 'big',  min: [0, 0, 0],   max: [850, 580, 720] },
  { name: 'tiny', min: [850, 0, 0], max: [900, 580, 720] }
], min_frac: 0.0)
w0 = uf0[0][:dims].select { |dd| dd[:dir] == :h && dd[:offset] > -GP.dim_off(900, 720) * 1.5 }
raise 'min_frac 0 keeps all' unless w0.map { |c| c[:text] }.sort == %w[50 850]

# OrderSheet.compose → DXF 직렬화 (SketchUp 밖에서만 — order_sheet는 독립 로드 가능)
if defined?(Kabinet::Output::OrderSheet)
  dxf = Kabinet::Output::OrderSheet.compose(views, name: '테스트장', size: GP.size_string(segs),
                                            material: '-', notes: ['비고 1'])
  s = dxf.to_s
  raise 'DXF EOF missing'   unless s.include?("EOF")
  raise 'DXF title missing' unless s.include?('품명: 테스트장')
  raise 'KABINET style missing' unless s.include?('KABINET')
  raise 'malgun font missing'   unless s.include?('malgun.ttf')
end

puts 'group_projection_test: OK'
