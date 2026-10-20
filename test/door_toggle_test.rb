# 도어 열기/닫기: 경첩 방향·회전각 규칙
module Kabinet; end
require_relative '../kabinet/commands/door_toggle'
D = Kabinet::Commands::DoorToggle
def assert(v, m); raise m unless v; end
assert D.hinge_side('door_single') == :left && D.hinge_side('door_pair_left') == :left, 'left hinge'
assert D.hinge_side('door_pair_right') == :right, 'right hinge'
assert D.hinge_side('door_sliding_front').nil? && D.hinge_side('door_lift_up').nil? && D.hinge_side(nil).nil?, 'non-swing ignored'
assert D.open_angle(:left) < 0 && D.open_angle(:right) > 0, 'opposite directions'
assert (D.open_angle(:right).abs * 180 / Math::PI - 80).abs < 1e-6, 'open degrees'
puts 'door_toggle_test: OK'
