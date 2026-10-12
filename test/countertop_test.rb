# 주방 상판 평면: 일자 / ㄱ자 / 높이 경고
module Kabinet; end
require_relative '../kabinet/core/countertop'
CT = Kabinet::Core::Countertop
def assert(v, m); raise m unless v; end
def area(cells); cells.sum { |c| (c[2] - c[0]) * (c[3] - c[1]) }; end
FRONT = [0, -1]   # 앞 = -Y

# 일자 2칸 (600 + 900, 깊이 600 — 도어 포함), 앞 20 · 노출 옆 20 · 뒤 0
run = [{ rect: [0, 0, 600, 600], front: FRONT, top: 860 }, { rect: [600, 0, 1500, 600], front: FRONT, top: 860 }]
pl = CT.plan(run, front_overhang: 20, side_overhang: 20, back_gap: 0)
xs = pl[:cells].flat_map { |c| [c[0], c[2]] }
ys = pl[:cells].flat_map { |c| [c[1], c[3]] }
assert xs.min == -20 && xs.max == 1520, "x #{xs.minmax}"       # 양끝만 옆 돌출, 가운데 이음부는 없음
assert ys.min == -20 && ys.max == 600, "y #{ys.minmax}"        # 앞으로 20, 뒤는 벽에 붙음
assert area(pl[:cells]) == 1540 * 620, "area #{area(pl[:cells])}"
assert pl[:top] == 860 && pl[:warnings].empty?, 'top'

# 벽 쪽 옆면은 돌출 안 함 처리는 사용자가 옆 돌출 0으로 지정
pl0 = CT.plan(run, front_overhang: 20, side_overhang: 0)
assert area(pl0[:cells]) == 1500 * 620, 'no side'

# ㄱ자: 가로 런 (0..2400, 앞 -Y) + 오른쪽 끝에서 앞쪽(-Y)으로 꺾인 세로 런 (x 1800..2400, y -1200..0, 앞 -X)
l = [{ rect: [0, 0, 2400, 600], front: FRONT, top: 860 },
     { rect: [1800, -1200, 2400, 0], front: [-1, 0], top: 860 }]
pl = CT.plan(l, front_overhang: 20, side_overhang: 20)
cells = pl[:cells]
covered = ->(x, y) { cells.any? { |c| x > c[0] && x < c[2] && y > c[1] && y < c[3] } }
assert covered.(10, 300), 'run covered'
assert covered.(-10, 300), 'left end side overhang'
assert covered.(2410, 300), 'run right end is exposed → side overhang'
assert !covered.(2410, -600), 'leg back (+X) stays on wall'
assert covered.(1790, -600), 'L leg front overhang (-X)'
assert covered.(2100, -1210), 'L leg exposed end overhang'
assert !covered.(1000, -100), 'no top in open floor'
# 겹침 없는 조각
cells.combination(2).each do |a, b|
  ov = [a[2], b[2]].min > [a[0], b[0]].max && [a[3], b[3]].min > [a[1], b[1]].max
  raise "overlap #{a} #{b}" if ov
end

# 높이 차 경고
w = CT.plan([{ rect: [0, 0, 600, 600], front: FRONT, top: 860 }, { rect: [600, 0, 1200, 600], front: FRONT, top: 900 }])
assert w[:top] == 900 && w[:warnings].size == 1, 'height warning'
begin; CT.plan([]); raise 'expected'; rescue CT::Error; end
puts 'countertop_test: OK'
