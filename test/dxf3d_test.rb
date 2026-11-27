require 'minitest/autorun'
require_relative '../kabinet/output/dxf3d'

class Dxf3dTest < Minitest::Test
  D = Kabinet::Output::Dxf3d

  def test_layer_by_role
    assert_equal 'K3D_SIDE',   D.layer_for('side_left')
    assert_equal 'K3D_SIDE',   D.layer_for('side_right')
    assert_equal 'K3D_TOP',    D.layer_for('top_panel')
    assert_equal 'K3D_DOOR',   D.layer_for('door_pair_left')
    assert_equal 'K3D_DRAWER_FRONT', D.layer_for('drawer_front_1')
    assert_equal 'K3D_DRAWER_FRONT', D.layer_for('cell_dfr_0_1')
    assert_equal 'K3D_DRAWER', D.layer_for('drawer_box_1')
    assert_equal 'K3D_SHELF',  D.layer_for('shelf')
    assert_equal 'K3D_EP',     D.layer_for('ep_left')
    assert_equal 'K3D_PLINTH', D.layer_for('modesty_panel')
    assert_nil D.layer_for('assembly')
    assert_nil D.layer_for('body_group')
    assert_nil D.layer_for('shelf_module')
    assert_equal 'K3D_SHELF',  D.layer_for(nil, '선반 1')
  end

  def test_write_faces
    d = D.new
    d.face([[0, 0, 0], [10, 0, 0], [10, 10, 0]], 'K3D_SIDE', [1])
    d.face([[0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0]], 'NOPE')
    s = d.to_s
    assert_equal 2, d.face_count
    assert_equal 2, s.scan("3DFACE").length
    assert_includes s, "AC1009"
    assert_equal({ 'K3D_SIDE' => 1, 'K3D_OTHER' => 1 }, d.layer_counts)
    assert_match(/\n70\n2\n/, s)   # 숨김 변 비트
    assert s.end_with?("0\nEOF\n")
  end

  def test_clip_square
    sq = [[0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0]]
    left = D.clip(sq, 0, 5, :le)
    assert_equal 4, left.length
    assert_in_delta 5.0, left.map { |p| p[0] }.max, 1e-9
    assert_empty D.clip(sq, 0, -1, :le)
    assert_equal 4, D.clip(sq, 0, 20, :le).length
  end

  def test_polygon_fan
    d = D.new
    d.polygon([[0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0]], 'K3D_TOP')
    assert_equal 2, d.face_count
  end

  def test_empty_ok
    assert_includes D.new.to_s, 'EOF'
  end
end
