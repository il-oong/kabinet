# 시트 구성 저장/불러오기(모델 attribute) + spec → 시트 모델 변환 — SketchUp 없이 가짜 모델로 검증
require 'json'
module Kabinet; module Persistence; end; end
require_relative '../kabinet/constants' rescue nil
require_relative '../kabinet/output/sheet'
require_relative '../kabinet/ui/sheet_bridge'
def assert(v, m); raise m unless v; end

class FakeModel
  def initialize; @a = {}; end
  def get_attribute(d, k, default = nil); (@a[d] || {}).fetch(k, default); end
  def set_attribute(d, k, v); (@a[d] ||= {})[k] = v; end
end
B = Kabinet::UI::SheetBridge
S = Kabinet::Output::Sheet

m = FakeModel.new
cfg = B.load_config(m)
assert cfg['pages'].size == 8 && cfg['pages'].map { |p| p['type'] } == %w[info photos view3d floor furniture side detail table], 'default pages'

# 순서 변경·숨김·제목/번호/축척 저장 → 다시 열어도 유지
c2 = Marshal.load(Marshal.dump(cfg))
c2['pages'].reverse!
c2['pages'][0]['subject'] = '확인표'
c2['pages'][1]['hidden'] = true
c2['pages'][2]['sheet_no'] = 'NO.009'; c2['pages'][2]['scale'] = '30'
c2['site'] = '판교 푸르지오 그랑블'; c2['furniture_name'] = '__-1'; c2['date'] = '2026.04.10'; c2['bg'] = 'dark'
B.save_config(m, c2)
r = B.load_config(m)
assert r['pages'].map { |p| p['id'] } == c2['pages'].map { |p| p['id'] }, 'order/ids persisted'
assert r['pages'][0]['subject'] == '확인표' && r['pages'][1]['hidden'] && r['pages'][2]['sheet_no'] == 'NO.009' && r['pages'][2]['scale'] == '30', 'fields'
assert r['site'] == '판교 푸르지오 그랑블' && r['bg'] == 'dark' && r['date'] == '2026.04.10', 'common fields'

# 가구 spec(Schema.normalize 결과 형태) → 시트 모델
spec = { 'name' => '붙박이장', 'width' => 1800, 'max_depth' => 600, 'base_height' => 60, 'ep' => { 'left' => true, 'right' => true, 'thickness' => 20 },
         'modules' => [
           { 'kind' => 'shelf_module', 'width' => 1800, 'height' => 2240, 'depth' => 600, 'door_config' => 'pair', 'handle_type' => 'push_open',
             'shelves' => [{ 'height_from_bottom' => 800 }, { 'height_from_bottom' => 1400 }],
             'accessories' => [{ 'kind' => 'hanging_rod', 'height_from_bottom' => 1900 }] }] }
data = S::Model.from_spec(spec)
o = data['overall']
assert o['W'] == 1800 && o['D'] == 600 && o['H'] == 2300 && o['kick'] == 60, "overall #{o}"
md = data['modules'][0]
assert md['doors'] == 2 && md['type'] == 'doors' && md['shelves'] == [800.0, 1400.0] && md['rods'] == [1900.0] && md['z'] == 60, "module #{md}"
assert data['notes']['handle'].include?('PUSH'), 'handle note'
assert data['ep']['left'] && data['ep']['right'], 'ep'

# run_mode: X 방향으로 누적
run = { 'name' => '런', 'width' => 1500, 'max_depth' => 600, 'run_mode' => true, 'run_height' => 800,
        'modules' => [{ 'kind' => 'drawer_module', 'width' => 600, 'height' => 800, 'depth' => 600, 'drawer_count' => 3 },
                      { 'kind' => 'shelf_module', 'width' => 900, 'height' => 800, 'depth' => 600, 'door_config' => 'single' }] }
rd = S::Model.from_spec(run)
assert rd['modules'].map { |x| x['x'] } == [0.0, 600.0] && rd['overall']['W'] == 1500.0, 'run mode x'
assert rd['modules'][0]['drawers'] == 3, 'drawers'

# 모델 → DXF 한 번에
require 'tmpdir'
Dir.mktmpdir do |dir|
  out = S::Builder.export(r, data, File.join(dir, 'a.dxf'))
  assert File.size(out[:path]) > 10_000 && out[:pages] == 7, "export pages #{out[:pages]}"   # table 위치 바뀜, 사진/3D 포함 8 중 숨김 1 = 7
end
puts 'sheet_bridge_test OK'
