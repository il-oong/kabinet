# 도어 열기/닫기: 경첩 방향·회전각·사용자 도어 지정·열림 각도 규칙
module Kabinet
  module Persistence
    module Attributes
      DICT = 'kabinet'
      def self.get(e, k); e.attrs[k.to_s]; end
      def self.role(e); get(e, 'role'); end
    end
  end
end
module Sketchup
  class Group; end
  class ComponentInstance; end
end
require_relative '../kabinet/commands/door_toggle'
D = Kabinet::Commands::DoorToggle
def assert(v, m); raise m unless v; end
class FakeEnt
  attr_reader :attrs
  def initialize(attrs = {}); @attrs = attrs; end
end
# 그룹 흉내: entities(하위 개체)와 attrs. Sketchup::Group 을 상속해 instance? 를 통과한다.
class FakeGroup < Sketchup::Group
  attr_reader :attrs, :entities
  def initialize(attrs = {}, children = []); @attrs = attrs; @entities = children; end
  def valid?; true; end
end
class FakeModel
  attr_reader :entities, :selection
  def initialize(entities, selection = []); @entities = entities; @selection = selection; end
end

assert D.hinge_side('door_single') == :left && D.hinge_side('door_pair_left') == :left, 'left hinge'
assert D.hinge_side('door_pair_right') == :right, 'right hinge'
assert D.hinge_side('door_sliding_front').nil? && D.hinge_side('door_lift_up').nil? && D.hinge_side(nil).nil?, 'non-swing ignored'
assert D.open_angle(:left) < 0 && D.open_angle(:right) > 0, 'opposite directions'
assert (D.open_angle(:right).abs * 180 / Math::PI - 80).abs < 1e-6, 'open degrees default 80'

# 열림 각도: 지정값 사용, 범위 5~175, 잘못된 값은 기본 80
assert (D.open_angle(:right, 110).abs * 180 / Math::PI - 110).abs < 1e-6, 'custom 110'
assert (D.open_angle(:left, 45).abs * 180 / Math::PI - 45).abs < 1e-6, 'custom 45'
assert D.clamp_deg(200) == 175.0 && D.clamp_deg(1) == 5.0, 'clamp range'
assert D.clamp_deg(nil) == 80.0 && D.clamp_deg('abc') == 80.0 && D.clamp_deg(0) == 80.0 && D.clamp_deg(-10) == 80.0, 'invalid -> 80'
assert D.clamp_deg('95') == 95.0, 'numeric string'

# 경첩 쪽 결정: 사용자 지정 > 단문 hinge_side 속성 > role 기본값
assert D.side_of(FakeEnt.new('role' => 'door_single')) == :left, 'single default left'
assert D.side_of(FakeEnt.new('role' => 'door_single', 'hinge_side' => 'right')) == :right, 'single hinge right'
assert D.side_of(FakeEnt.new('role' => 'door_pair_right', 'hinge_side' => 'left')) == :right, 'pair ignores hinge_side'
assert D.side_of(FakeEnt.new('role' => 'door_pair_left')) == :left, 'pair left'
assert D.side_of(FakeEnt.new('role' => 'panel')).nil?, 'non door'
assert D.side_of(FakeEnt.new('role' => 'panel', 'door_hinge' => 'right')) == :right, 'designated right on any entity'
assert D.side_of(FakeEnt.new('role' => 'door_single', 'door_hinge' => 'right')) == :right, 'designation overrides role'
assert D.side_of(FakeEnt.new('door_hinge' => 'left')) == :left, 'designated left without role'
assert D.designated_side(FakeEnt.new('door_hinge' => 'bogus')).nil?, 'bogus designation ignored'

# 선택이 없을 때: 직접 만든 일반 캐비닛 그룹 안(중첩)의 지정 도어도 찾아야 한다
door  = FakeGroup.new('door_hinge' => 'left')
shelf = FakeGroup.new({}, [FakeGroup.new({})])
cab   = FakeGroup.new({ 'label' => 'custom' }, [shelf, door])      # 지정도 role 도 없는 일반 그룹
other = FakeGroup.new({}, [FakeGroup.new('role' => 'door_pair_right')])
plain = FakeGroup.new({})
model = FakeModel.new([cab, other, plain, FakeEnt.new])           # FakeEnt 는 그룹이 아님 → 무시
assert D.top_level_roots(model).size == 3, 'top-level roots are all groups'
found = D.find_doors(model)
assert found.include?(door) && found.size == 2, 'nested designated + role door found without selection: ' + found.size.to_s
# 선택이 있으면 선택한 것만
assert D.find_doors(FakeModel.new([cab, other], [other])).size == 1, 'selection limits search'
# 같은 정의를 가리키는 중복 방문 없이 도어는 한 번만
dup = FakeGroup.new({}, [door])
assert D.find_doors(FakeModel.new([dup, dup])).size == 1, 'no duplicates'

# 클릭 도구: 경로(루트→말단)에서 가장 안쪽 도어와 그 부모 인스턴스 찾기
class FakeFace; end   # 면/엣지 등 인스턴스가 아닌 개체 흉내
door2 = FakeGroup.new('role' => 'door_pair_left', 'x' => 1)
handle = FakeGroup.new('role' => 'handle_knob')
cab2 = FakeGroup.new({}, [door2])
r = D.door_in_path([cab2, door2, handle, FakeFace.new])      # 손잡이/면을 눌러도 도어를 찾는다
assert r && r[0].equal?(door2) && r[1].size == 1 && r[1][0].equal?(cab2), 'door in path with parents'
assert D.door_in_path([cab2, FakeGroup.new({}), FakeFace.new]).nil?, 'no door in path'
assert D.door_in_path(nil).nil? && D.door_in_path([]).nil?, 'empty path'
# 안쪽 도어가 우선(도어 안의 도어는 가장 안쪽)
inner = FakeGroup.new('door_hinge' => 'right')
outer = FakeGroup.new({ 'door_hinge' => 'left' }, [inner])
assert D.door_in_path([outer, inner])[0].equal?(inner), 'innermost door wins'
# 열기/닫기 판단: 하나라도 열려 있으면 닫기
assert D.closing?([FakeGroup.new('door_open' => false), FakeGroup.new('door_open' => true)]), 'any open -> closing'
assert !D.closing?([FakeGroup.new({}), FakeGroup.new('door_open' => false)]), 'all closed -> opening'
puts 'door_toggle_test: OK'
