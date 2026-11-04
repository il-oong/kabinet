# EP(마감판) 두께 구간에 몸통 선(OUTLINE/THIN)이 겹치지 않는다 — 시트 캔버스 기하 검사
require_relative '../kabinet/output/sheet'
S = Kabinet::Output::Sheet
def assert(v, m); raise m unless v; end

# 선분 p-q 가 사각 r=[x0,y0,x1,y1] 내부에 놓인 길이 (Liang-Barsky)
def clip_len(p, q, r)
  dx = q[0] - p[0]; dy = q[1] - p[1]; t0 = 0.0; t1 = 1.0
  [[-dx, p[0] - r[0]], [dx, r[2] - p[0]], [-dy, p[1] - r[1]], [dy, r[3] - p[1]]].each do |pp, qq|
    if pp.abs < 1e-12
      return 0.0 if qq < 0
    else
      t = qq / pp
      pp < 0 ? t0 = [t0, t].max : t1 = [t1, t].min
      return 0.0 if t0 > t1
    end
  end
  (t1 - t0) * Math.hypot(dx, dy)
end

def overlaps(canvas, tol)
  regions = canvas.items.select { |it| it[0] == :H }.map do |it|
    xs = it[1].map(&:first); ys = it[1].map(&:last)
    [xs.min, ys.min, xs.max, ys.max]
  end
  segs = []
  canvas.items.each do |it|
    case it[0]
    when :L then segs << [[it[1], it[2]], [it[3], it[4]]] if %w[OUT THIN].include?(it[5])
    when :P
      next unless %w[OUT THIN].include?(it[2])
      pts = it[1]
      pts.each_cons(2) { |a, b| segs << [a, b] }
      segs << [pts.last, pts.first] if it[3]
    end
  end
  bad = []
  regions.each do |r|
    next if r[2] - r[0] <= 4 * tol || r[3] - r[1] <= 4 * tol
    inner = [r[0] + tol, r[1] + tol, r[2] - tol, r[3] - tol]
    n = segs.count { |a, b| clip_len(a, b, inner) > tol }
    bad << [r.map { |v| v.round(1) }, n] if n > 0
  end
  bad
end

model = {
  'furniture_name' => 'EP장', 'overall' => { 'W' => 1800, 'H' => 900, 'D' => 600, 'top_thickness' => 80, 'kick' => 100 },
  'ep' => { 'left' => true, 'right' => true, 'top' => true, 'thickness' => 20 },
  'modules' => [
    { 'name' => '도어', 'x' => 0, 'z' => 100, 'w' => 900, 'h' => 720, 'type' => 'doors', 'doors' => 2, 'shelves' => [300] },
    { 'name' => '서랍', 'x' => 900, 'z' => 100, 'w' => 900, 'h' => 720, 'type' => 'drawers', 'drawers' => 2 }
  ]
}
m = S::Model.normalize(model)
info = { scale: 25, subject: 's', sheet_no: '', site: '', title: 't', date: '' }
{ 'furniture' => S::Pages.furniture(m, info), 'side' => S::Pages.side(m, info) }.each do |name, cv|
  bad = overlaps(cv, 0.02)
  assert bad.empty?, "EP overlap on #{name}: #{bad.first(4)}"
end
# 끝 모듈이 줄었는지: 첫 모듈 몸통 시작 = EP 두께, 마지막 모듈 끝 = W - EP
cl = S::Pages.clipped(m)
assert cl.first['x'] == 20 && cl.first['w'] == 880 && cl.last['x'] + cl.last['w'] == 1780, "clipped #{cl.map { |c| [c['x'], c['w']] }}"
# EP 없는 가구는 그대로
m2 = S::Model.normalize(model.merge('ep' => {}))
assert S::Pages.clipped(m2).map { |c| [c['x'], c['w']] } == [[0, 900], [900, 900]], 'no EP -> unchanged'
puts 'sheet_no_overlap_ep_test OK'
