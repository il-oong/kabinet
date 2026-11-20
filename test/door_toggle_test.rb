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
require_relative '../kabinet/commands/door_toggle'
D = Kabinet::Commands::DoorToggle
def assert(v, m); raise m unless v; end
class FakeEnt
  attr_reader :attrs
  def initialize(attrs = {}); @attrs = attrs; end
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
puts 'door_toggle_test: OK'
