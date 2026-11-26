# 가구 도면(LayOut) 쪽 배치 계획을 JSON 으로 내보낸다 — 미리보기(preview_layout.py)·검증용.
# 사용: ruby tools/sheet/export_layout_plan.rb W D H [iso,front,side] [장목록]
#   장목록 = "이름:WxDxH,이름:WxDxH,..." (mm). 주면 장별 세부 쪽을 포함한다(좌 -> 우 순서).
require 'json'
require_relative '../../kabinet/output/sheet_layout'
L = Kabinet::Output::SheetLayout
w, d, h = ARGV[0, 3].map(&:to_f)
abort '사용: ruby export_layout_plan.rb W D H [pages] [name:WxDxH,...]' if [w, d, h].any?(&:zero?)
pages = (ARGV[3] || 'iso,front,side').split(',')
opts = { 'pages' => pages }
if ARGV[4] && !ARGV[4].empty?
  opts['units'] = ARGV[4].split(',').each_with_index.map do |spec, i|
    name, dims = spec.split(':')
    { index: i, name: name, size: dims.split('x').map(&:to_f) }
  end
end
plan = L.plan([w, d, h], opts)
plan[:pages].each do |pg|
  next unless pg[:id] == 'unit'
  u = opts['units'].find { |x| x[:index] == pg[:unit] }
  uw, ud, uh = u[:size]
  parts = [{ role: 'side_left', dims: [uh, ud, 18] }, { role: 'side_right', dims: [uh, ud, 18] }, { role: 'bottom', dims: [uw - 36, ud, 18] },
           { role: 'top', dims: [uw - 36, ud, 18] }, { role: 'back', dims: [uw - 36, uh - 36, 9] }, { role: 'shelf_0', dims: [uw - 36, ud - 30, 18] },
           { role: 'drawer_front_0', dims: [uw - 4, 180, 18] }]
  n = plan[:pages].select { |x| x[:id] == 'unit' }
  pg[:table_lines] = L.unit_table_lines({ name: u[:name], size: u[:size], number: n.index(pg) + 1, count: n.length, parts: parts })
end
plan[:problems] = L.problems(plan)
puts JSON.generate(plan)
