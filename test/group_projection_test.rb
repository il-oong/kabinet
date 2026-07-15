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

# OrderSheet.compose → DXF 직렬화 (SketchUp 밖에서만 — order_sheet는 독립 로드 가능)
if defined?(Kabinet::Output::OrderSheet)
  dxf = Kabinet::Output::OrderSheet.compose(views, name: '테스트장', size: GP.size_string(segs),
                                            material: '-', notes: ['비고 1'])
  s = dxf.to_s
  raise 'DXF EOF missing'   unless s.include?("EOF")
  raise 'DXF title missing' unless s.include?('품명: 테스트장')
end

puts 'group_projection_test: OK'
