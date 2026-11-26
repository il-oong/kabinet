# frozen_string_literal: false
# 측면도·평면도 방향 검증(순수 계산): 정면에서 본 사람 기준 좌/우, 전/후가 도면에서 규칙대로 나오는지.
#   정면도: 왼쪽 = 가구의 왼쪽 / 평면도: 전면이 아래 / 우측면도: 전면이 왼쪽 / 좌측면도: 전면이 오른쪽(3각법)
module Kabinet; end
require_relative '../kabinet/constants'
module Kabinet; module Persistence; module Attributes; def self.role(e); e.role; end; end; end; end
module Sketchup; class Group; end; class ComponentInstance; end; class Edge; end; class Face; end; end
module Geom; class Point3d; end; class Transformation; end; end
class Numeric; def to_mm; self; end; end
require_relative '../kabinet/output/group_projection'
require_relative '../kabinet/output/sheet_layout'
require_relative '../kabinet/output/furniture_sheet'
def assert(v, m); raise m unless v; end
FS = Kabinet::Output::FurnitureSheet
L = Kabinet::Output::SheetLayout

# 보는 사람이 가구를 정면에서 바라볼 때의 (오른쪽 vx, 깊이 vd(뒤 +), 높이 z) → 월드 (x, y).
# 월드는 물리적으로 직접 적었다(보는 사람이 서 있는 쪽 기준, 규칙 코드의 공식과 독립).
WORLD = {
  '-Y' => ->(vx, vd) { [vx, vd] },        # 남쪽에서 북을 봄: 오른쪽 = +X, 뒤 = +Y
  '+Y' => ->(vx, vd) { [-vx, -vd] },      # 북쪽에서 남을 봄: 오른쪽 = -X, 뒤 = -Y
  '-X' => ->(vx, vd) { [vd, -vx] },       # 서쪽에서 동을 봄: 오른쪽 = -Y, 뒤 = +X
  '+X' => ->(vx, vd) { [-vd, vx] }        # 동쪽에서 서를 봄: 오른쪽 = +Y, 뒤 = -X
}.freeze

W, D, H = 1000.0, 500.0, 800.0
# 비대칭 특징(가구 기준): 왼쪽 서랍 측판선(vx=100, 전면), 오른쪽 손잡이(vx=900, 전면), 가운데 뒷판선(vx=500, 뒤)
FEATURES = {
  left_front: [[100, 0, 0], [100, 0, H]],
  right_front: [[900, 0, 100], [900, 0, 700]],
  back_panel: [[500, D, 0], [500, D, H]],
  top_front_edge: [[0, 0, H], [W, 0, H]],
  back_edge: [[400, D, H], [600, D, H]],
  pad_left: [[100, 0, H], [100, 100, H]],
  pad_right: [[900, 0, H], [900, 100, H]]
}.freeze

WORLD.each do |axis, map|
  to_local, right, back = FS.local_frame(axis)
  segs = FEATURES.transform_values do |(a, b)|
    [a, b].map { |vx, vd, z| x, y = map.call(vx, vd); to_local.call([x, y, z]) }
  end
  # 로컬 좌표가 곧 (vx, vd, z) 여야 한다(정면 기준 좌표계)
  FEATURES.each do |name, (a, b)|
    la, lb = segs[name]
    assert la.zip(a).all? { |u, v| (u - v).abs < 1e-9 } && lb.zip(b).all? { |u, v| (u - v).abs < 1e-9 }, "#{axis} #{name}: 로컬 좌표 != (오른쪽, 뒤, 위) #{la.inspect}"
  end
  # 시선 방향: 정면도 시선 = 정면 방향 = 월드에서 보는 사람 쪽
  fx, fy = FS::FRONT_AXES.fetch(axis)
  dirs = FS::VIEW_DIRS_LOCAL.keys.to_h { |n| [n, FS.world_view_direction(n, right, back)] }
  assert dirs['front'][0..1].zip([fx, fy]).all? { |a, b| (a - b).abs < 1e-9 }, "#{axis}: 정면도 시선이 정면 방향이 아님"
  # 우측면도 시선 = 보는 사람 오른쪽, 좌측면도 시선 = 보는 사람 왼쪽
  assert dirs['side'][0..1].zip(right).all? { |a, b| (a - b).abs < 1e-9 }, "#{axis}: 우측면도 시선 != 오른쪽"
  assert dirs['side_left'][0..1].zip(right.map { |v| -v }).all? { |a, b| (a - b).abs < 1e-9 }, "#{axis}: 좌측면도 시선 != 왼쪽"

  all = segs.values
  size = [W, D, H]
  lo = [0.0, 0.0, 0.0]
  seg1 = ->(view, key) { FS.view_segments(view, [segs.fetch(key)], lo, size).first }
  # 정면도: 왼쪽 특징이 오른쪽 특징보다 왼쪽
  assert seg1.call('front', :left_front)[0] < seg1.call('front', :right_front)[0], "#{axis}: 정면도 좌우 반전"
  # 평면도: 전면(손잡이쪽 가장자리, vd=0)이 아래(작은 y), 뒷판(vd=D)이 위
  assert seg1.call('top', :top_front_edge)[1] < seg1.call('top', :back_edge)[1], "#{axis}: 평면도 앞뒤 반전"
  assert seg1.call('top', :pad_left)[0] < seg1.call('top', :pad_right)[0], "#{axis}: 평면도 좌우 반전"
  assert seg1.call('top', :pad_left)[3] > seg1.call('top', :pad_left)[1], "#{axis}: 평면도 깊이 방향(뒤가 위)"
  # 우측면도: 전면이 왼쪽, 뒷판이 오른쪽
  assert seg1.call('side_r', :left_front)[0] < seg1.call('side_r', :back_panel)[0], "#{axis}: 우측면도 전면이 왼쪽이 아님"
  # 좌측면도: 전면이 오른쪽, 뒷판이 왼쪽
  assert seg1.call('side_l', :left_front)[0] > seg1.call('side_l', :back_panel)[0], "#{axis}: 좌측면도 전면이 오른쪽이 아님"
  # 높이는 모든 뷰에서 위가 큼
  %w[front side_r side_l].each { |v| assert [seg1.call(v, :left_front)[1], seg1.call(v, :left_front)[3]].max == H, "#{axis} #{v}: 높이(위가 큼)" }
  # 좌/우 측면도는 서로 정확히 좌우 반전
  l = seg1.call('side_l', :back_panel); r = seg1.call('side_r', :back_panel)
  assert (l[0] - (D - r[0])).abs < 1e-6, "#{axis}: 좌측면도 != 우측면도 좌우 반전"
end

# 쪽 배치: 좌측면도는 정면도 왼쪽, 우측면도는 정면도 오른쪽, 평면도는 정면도 위(3각법)
[[600, 550, 720], [3600, 650, 900]].each do |size|
  L.plan(size)[:pages].each do |pg|
    v = pg[:views].to_h { |x| [x[:name], x] }
    if v['side_l'] && v['front']
      assert v['side_l'][:rect][0] < v['front'][:rect][0] && v['front'][:rect][0] < v['side_r'][:rect][0], '쪽 안 좌/정/우 순서'
    end
    assert v['top'][:rect][1] < v['front'][:rect][1], '평면도는 정면도 위' if v['top'] && v['front']
    assert v['side_l'][:rect][0] < v['side_r'][:rect][0], '측면도 쪽: 좌측면도가 왼쪽' if v['side_l'] && v['side_r'] && !v['front']
    # 전면 표시: 방향과 위치
    mk = ->(n) { v[n] && v[n][:marker] }
    if mk.call('side_r')
      a = mk.call('side_r')[:arrow]
      assert mk.call('side_r')[:dir] == 'left' && a[2] < a[0], '우측면도 전면 표시는 왼쪽 향함'
    end
    if mk.call('side_l')
      a = mk.call('side_l')[:arrow]
      assert mk.call('side_l')[:dir] == 'right' && a[2] > a[0], '좌측면도 전면 표시는 오른쪽 향함'
    end
    if mk.call('top')
      a = mk.call('top')[:arrow]
      assert mk.call('top')[:dir] == 'down' && a[3] > a[1], '평면도 전면 표시는 아래 향함'
    end
    assert v['front'][:marker].nil?, '정면도에는 전면 표시 없음' if v['front']
    pg[:views].each do |vw|
      next unless vw[:marker]
      o = vw[:outer]
      ax1, ay1, ax2, ay2 = vw[:marker][:arrow]
      tx, ty, tw, th = vw[:marker][:text]
      pts = [[ax1, ay1], [ax2, ay2], [tx, ty], [tx + tw, ty + th]]
      assert pts.all? { |x, y| x >= o[0] - 1e-6 && x <= o[0] + o[2] + 1e-6 && y >= o[1] - 1e-6 && y <= o[1] + o[3] + 1e-6 }, "#{vw[:name]}: 전면 표시가 뷰 영역 밖"
    end
  end
end
assert L.problems(L.plan([600, 550, 720])).empty?, 'problems'
puts 'sheet_view_direction_test: OK'
