# 순수 루비 자가 검증 — SketchUp 불필요. 실행: ruby test/space_divider_test.rb
require_relative 'support/geom'
module Kabinet; end
%w[constants core/fitting core/space_divider].each { |f| require_relative "../kabinet/#{f}" }

SD = Kabinet::Core::SpaceDivider
def assert(v, msg); raise msg unless v; end
def near(a, b, tol = 1e-6); (a - b).abs < tol; end

# 900W × 580D × 720H 캐비닛 내부 (18T 몸통, 뒷판 9T, 전면 열림). 원점 = 내부 한 점.
# 내부 폭 864 = 좌 18 + 우 18 제외, 높이 684, 깊이 방향: 뒷판까지 561 (전면 -580+... 임의)
ox, oy, oz = 300.0, 200.0, 400.0
side_l = { dist: ox,           bmin: [-318.0, -580.0, -400.0], bmax: [-300.0, 0.0, 320.0], thick: 18.0 }
side_r = { dist: 864.0 - ox,   bmin: [564.0 - 0, -580.0, -400.0], bmax: [582.0, 0.0, 320.0], thick: 18.0 }
bottom = { dist: oz,           bmin: [-318.0, -580.0, -418.0], bmax: [582.0, 0.0, -400.0], thick: 18.0 }
top    = { dist: 684.0 - oz,   bmin: [-318.0, -560.0, 284.0], bmax: [582.0, 0.0, 302.0], thick: 18.0 }
back   = { dist: 20.0,         bmin: [-300.0, 20.0, -400.0], bmax: [564.0, 29.0, 284.0], thick: 9.0 }
hits = { [0, -1] => side_l, [0, 1] => side_r, [2, -1] => bottom, [2, 1] => top, [1, 1] => back }

sp = SD.resolve_space(hits)
assert near(sp[:size][0], 864.0), "width #{sp[:size][0]}"
assert near(sp[:size][2], 684.0), "height #{sp[:size][2]}"
assert sp[:front_open], 'front should be open'
# 전면 열림: 이웃 판 중 원점에 가장 가까운 앞면(상판 -560)이 아니라 가장 가까운 값
assert near(sp[:lo][1], -560.0), "front limit #{sp[:lo][1]}"
assert near(sp[:ext][:left], 18.0) && near(sp[:ext][:top], 18.0), 'ext'

# 세로 칸막이 3칸 + 오버레이 도어 3장
pl = SD.plan(sp, axis: 'x', cells: 3, thickness: 18.0, door_mode: 'overlay', door_thickness: 20.0)
assert pl[:partitions].size == 2, 'partition count'
assert near(pl[:cell_mm], (864.0 - 2 * 18) / 3), 'cell width'
p1, p2 = pl[:partitions]
assert near(p1[:pos][0], pl[:cell_mm]) && near(p2[:pos][0], 2 * pl[:cell_mm] + 18.0), 'partition x'
assert p1[:dims] == [18.0, sp[:size][1], 684.0], "dims #{p1[:dims]}"
assert pl[:doors].size == 3, 'door count'
widths = pl[:doors].map { |d| d[:dims][0] }
assert widths.all? { |w| near(w, widths[0]) }, 'doors equal width'
# 도어 전체 = 몸통 외곽(864+36=900) − 2×2 외곽 갭 − 2×3 중앙 갭
assert near(widths.sum, 900.0 - 4.0 - 6.0), "door total #{widths.sum}"
assert near(pl[:doors][0][:pos][0], -18.0 + 2.0), 'first door x'
assert near(pl[:doors][0][:pos][1], -22.0), 'door y (20T + 2 offset in front)'
assert near(pl[:doors][0][:dims][2], 720.0 - 4.0), 'door height'
assert pl[:warnings].empty?, "unexpected warn #{pl[:warnings]}"

# 인셋 도어 2칸: 개구 864 − 2×2 − 3 = 857 / 2
pi = SD.plan(sp, axis: 'x', cells: 2, thickness: 18.0, door_mode: 'inset')
assert near(pi[:doors][0][:dims][0], (864.0 - 4.0 - 3.0) / 2), 'inset door width'
assert near(pi[:doors][0][:pos][1], 0.0), 'inset y'

# 가로 선반 4칸 → 3장 선반, 도어 4장 위아래 균등
ph = SD.plan(sp, axis: 'z', cells: 4, thickness: 18.0, door_mode: 'overlay')
assert ph[:partitions].size == 3 && ph[:partitions][0][:dims] == [864.0, sp[:size][1], 18.0], 'shelf dims'
hs = ph[:doors].map { |d| d[:dims][2] }
assert hs.all? { |h| near(h, hs[0]) } && ph[:doors].size == 4, 'doors equal height'
assert near(hs.sum, 720.0 - 4.0 - 9.0), "door total h #{hs.sum}"

# 도어 없음
assert SD.plan(sp, axis: 'x', cells: 2, thickness: 18.0, door_mode: 'none')[:doors].empty?, 'no door'

# 넓은 칸 → 폭 경고
wide = sp.merge(size: [1764.0, sp[:size][1], 684.0], ext: { left: 18.0, right: 18.0, bottom: 18.0, top: 18.0 })
w1 = SD.plan(wide, axis: 'x', cells: 2, thickness: 18.0)
assert w1[:warnings].size == 1, 'wide door warning'
assert SD.plan(wide, axis: 'x', cells: 3, thickness: 18.0)[:warnings].empty?, 'no warning at 3 cells'

# 오류 경로
[->{ SD.plan(sp, axis: 'x', cells: 1, thickness: 18.0) },
 ->{ SD.plan(sp, axis: 'x', cells: 40, thickness: 18.0) },
 ->{ SD.resolve_space({}) }].each { |f| begin; f.call; raise 'expected error'; rescue SD::Error; end }

# 닫힌 6면(전면 포함)이면 front_open=false
closed = hits.merge([1, -1] => { dist: 200.0, bmin: [0,0,0], bmax: [0,0,0], thick: 18.0 })
assert !SD.resolve_space(closed)[:front_open], 'closed front'
puts 'space_divider_test OK'
