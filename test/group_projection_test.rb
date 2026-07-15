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
chain = f2[:dims].select { |dd| dd[:dir] == :h && dd[:offset] > -GP.dim_off(900, 720) }
raise "chain widths #{chain.map { |c| c[:text] }}" unless chain.map { |c| c[:text] }.sort == %w[400 500]
raise 'unit B height dim missing' unless f2[:dims].any? { |dd| dd[:dir] == :v && dd[:text] == '500' }

# 유닛 1개면 분할 치수 생략 (전체 치수와 중복)
v1 = GP.views_from_segments(segs, units: [units[0]])
raise 'single unit should add no dims' unless v1[0][:dims].size == 2

# OrderSheet.compose → DXF 직렬화 (SketchUp 밖에서만 — order_sheet는 독립 로드 가능)
if defined?(Kabinet::Output::OrderSheet)
  dxf = Kabinet::Output::OrderSheet.compose(views, name: '테스트장', size: GP.size_string(segs),
                                            material: '-', notes: ['비고 1'])
  s = dxf.to_s
  raise 'DXF EOF missing'   unless s.include?("EOF")
  raise 'DXF title missing' unless s.include?('품명: 테스트장')
end

puts 'group_projection_test: OK'
