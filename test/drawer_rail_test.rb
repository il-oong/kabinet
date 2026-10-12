require 'json'
require_relative 'support/geom'
module Kabinet; end
%w[constants persistence/attributes persistence/schema geometry/transforms geometry/builder
   geometry/joinery geometry/handle_builder core/fitting core/panel core/carcase
   core/door_panel core/ep_finish_panel core/accessory core/shelf_module core/drawer_module
   core/desk_module core/assembly core/cut_list core/hardware geometry/preview_entities].each do |file|
  require_relative "../kabinet/#{file}"
end

def assert(value, message); raise message unless value; end
def near(a, b); (a - b).abs < 0.001; end

FIT = Kabinet::Core::Fitting

# ── 공식: 사이드 볼레일 기본 편측 19mm, 언더레일 5mm, 직접 지정 우선
box = FIT.drawer_box_mm(open_w_mm: 564, comp_h_mm: 200, inner_depth_mm: 480, type: 'side_mount')
assert(near(box[:w], 564 - 38), "side_mount box width must be inner - 2x19 (got #{box[:w]})")
assert(near(box[:side_clear], 19), 'side_mount default clearance 19')
assert(box[:slide_len] == 450.0, 'slide snaps to 450 for 480 inner depth')
under = FIT.drawer_box_mm(open_w_mm: 564, comp_h_mm: 200, inner_depth_mm: 480, type: 'undermount')
assert(near(under[:w], 554), 'undermount keeps 5mm per side')
custom = FIT.drawer_box_mm(open_w_mm: 564, comp_h_mm: 200, inner_depth_mm: 480,
                           type: 'side_mount', side_clear_mm: 12.7)
assert(near(custom[:w], 564 - 25.4), 'rail_clearance_mm override')

# ── 레일: 좌우 한 쌍, 사이드는 편측 공간을 정확히 채움 (몸통 측판 ~ 서랍통 옆판)
rails = FIT.drawer_rails_mm(box, 'side_mount')
assert(rails.size == 2, 'two rails per drawer')
l, r = rails
assert(near(l[:x], -19) && near(l[:w], 19), 'left rail fills 19mm gap')
assert(near(r[:x], box[:w]) && near(r[:x] + r[:w], box[:w] + 19), 'right rail fills 19mm gap')
assert(near(l[:d], 450) && near(l[:h], 45), 'rail = slide length x 45mm')
assert(l[:z] >= 0 && l[:z] + l[:h] <= box[:h], 'side rail within box side height')
ur = FIT.drawer_rails_mm(under, 'undermount')
assert(near(ur[0][:z] + ur[0][:h], 0), 'undermount rail sits under box bottom')

# ── 3D: 내부공간 564×(3단)×480 → 외경 600, 레일 그룹이 생성됨
def roles(group, out = [])
  group.entities.instance_variable_get(:@items).each do |it|
    next unless it.is_a?(Kabinet::Geometry::Preview::Group)
    out << Kabinet::Persistence::Attributes.role(it).to_s
    roles(it, out)
  end
  out
end

spec = { 'width' => 600, 'max_depth' => 499, 'base_height' => 0,
         'ep' => { 'left' => false, 'right' => false },
         'modules' => [{ 'kind' => 'drawer_module', 'width' => 600, 'depth' => 499, 'height' => 636,
                         'drawer_count' => 3, 'drawer_type' => 'side_mount', 'handle_type' => 'none' }] }
norm = Kabinet::Persistence::Schema.normalize(spec)
Kabinet::Persistence::Schema.validate!(norm)
root = Kabinet::Core::Assembly.from_hash(norm).build(Kabinet::Geometry::Preview::Entities.new)
rs = roles(root)
3.times { |i| assert(rs.include?("drawer_rails_#{i}"), "missing drawer_rails_#{i}: #{rs.uniq}") }
assert(rs.count('drawer_rail_left') == 3 && rs.count('drawer_rail_right') == 3, 'rail parts per drawer')

# ── 커트리스트 / 하드웨어: 편측 19mm 반영
rows = Kabinet::Core::CutList.generate(norm)
bottom = rows.find { |x| x[:part_name].to_s.include?('서랍-바닥') }
assert(bottom && near(bottom[:length_mm], 564 - 38), "cut list box width (got #{bottom.inspect})")
side = rows.find { |x| x[:part_name].to_s.include?('서랍-옆판') }
assert(side[:note].include?('편측 19mm'), "cut list note shows clearance: #{side[:note]}")
hw = Kabinet::Core::Hardware.generate(norm).find { |x| x[:name].include?('서랍 레일') }
assert(hw[:spec].include?('사이드 볼레일 L450') && hw[:note].include?('편측 19mm'), "hardware row: #{hw.inspect}")

puts 'PASS: drawer rails — side 19mm clearance, rail geometry, cut list, hardware'
