# frozen_string_literal: false
# 가구 도면(LayOut) 쪽 배치 계획 — SketchUp/LayOut 없이 검증: 겹침 없음, 표준 배율, 쪽마다 단일 배율, 글자 안전화
require_relative '../kabinet/output/sheet_layout'
def assert(v, m); raise m unless v; end
L = Kabinet::Output::SheetLayout

SIZES = {
  'W600xH720 단품' => [600, 550, 720],
  'W900xH720 하부장' => [900, 580, 720],
  'W3600xH900 아일랜드' => [3600, 650, 900],
  'W2740xH2300 붙박이' => [2740, 600, 2300],
  'W1200xH2400 키큰장' => [1200, 600, 2400],
  'W9000xH2400 초대형' => [9000, 600, 2400],
  'W300xH300 소형' => [300, 300, 300]
}.freeze

SIZES.each do |name, size|
  plan = L.plan(size)
  pr = L.problems(plan)
  assert pr.empty?, "#{name}: #{pr.inspect}"
  assert plan[:pages].length.between?(2, 4), "#{name}: 쪽 수 #{plan[:pages].length}"
  plan[:pages].each do |pg|
    assert pg[:scale].nil? || L::STD_DENS.include?(pg[:scale]), "#{name}: 비표준 배율 #{pg[:scale]}"
    pg[:views].each do |v|
      assert v[:den] == pg[:scale], "#{name}: 쪽 안 배율 불일치"
      # 기하 사각형은 정확히 가구 크기 / 배율
      ai, bi = L::AXES[v[:name]]
      ext = v[:clip] ? [v[:clip][1] - v[:clip][0], size[bi]] : [size[ai], size[bi]]
      assert (v[:rect][2] - ext[0].to_f / v[:den]).abs < 1e-6 && (v[:rect][3] - ext[1].to_f / v[:den]).abs < 1e-6, "#{name}: 뷰 크기 != 크기/배율"
      assert L.rects_intersect?(v[:outer], v[:outer]) && v[:outer][0] <= v[:rect][0] && v[:outer][1] <= v[:rect][1], "#{name}: 바깥 사각형이 기하를 포함해야 함"
    end
  end
end

# 작은 가구는 2쪽(입체도 + 정면·평면·측면 한 쪽), 큰 가구는 3쪽 이상
assert L.plan([600, 550, 720])[:pages].length == 2, '작은 가구는 2쪽'
assert L.plan([3600, 650, 900])[:pages].length == 3, '큰 가구는 3쪽'
assert L.plan([600, 550, 720])[:pages].last[:views].map { |v| v[:name] }.sort == %w[front side_l side_r top], '단품은 정면·평면·좌우 측면'

# 정면이 1/50 보다 작은 배율이 필요한 초대형은 구간 분할(쪽 증가), 모든 구간 같은 배율, 구간은 서로 겹침 표시(여유)
huge = L.plan([20000, 600, 2400])
assert L.problems(huge).empty?, "초대형: #{L.problems(huge)}"
wins = huge[:pages].select { |pg| pg[:window] }
assert wins.length >= 2, '초대형은 정면 구간 분할'
assert wins.map { |pg| pg[:scale] }.uniq.length == 1, '분할 구간 배율 동일'
assert wins.first[:window][0] == 0.0 && wins.last[:window][1] == 20000.0, '구간이 전체 폭을 덮음'
assert wins.each_cons(2).all? { |a, b| b[:window][0] < a[:window][1] }, '구간 사이 겹침'

# 쪽 선택 옵션
only = L.plan([600, 550, 720], 'pages' => %w[iso])
assert only[:pages].length == 1 && only[:pages][0][:id] == 'iso', 'iso 만 선택'
fr = L.plan([3600, 650, 900], 'pages' => %w[front])
assert fr[:pages].map { |pg| pg[:id] } == %w[front], 'front 만 선택'

# 같은 입력이면 항상 같은 계획(결정적)
assert L.plan([2740, 600, 2300]) == L.plan([2740, 600, 2300]), '결정적 계획'

# 겹침 검사 자체가 동작하는지(일부러 겹친 계획)
bad = L.plan([3600, 650, 900])
bad[:pages][1][:views][1][:outer] = bad[:pages][1][:views][0][:outer].dup
assert !L.problems(bad).empty?, '겹침을 잡아야 함'
bad2 = L.plan([3600, 650, 900])
bad2[:pages][1][:views][0][:den] = 17
assert L.problems(bad2).any? { |m| m.include?('비표준') }, '비표준 배율을 잡아야 함'

# 표제란 영역을 침범하지 않음(내용 영역 아래 끝 < 표제란 위)
assert L::AREA[:y1] < L::TITLE_BLOCK[:y], '표제란 분리'

# 선분 자르기(구간 분할용)
assert L.clip_segment([0, 5, 10, 5], nil, nil) == [0, 5, 10, 5], 'clip nil'
assert L.clip_segment([0, 5, 10, 5], 2, 6) == [0.0, 5.0, 4.0, 5.0], 'clip 가로선'
assert L.clip_segment([3, 0, 3, 9], 2, 6) == [1, 0, 1, 9], 'clip 세로선 이동'
assert L.clip_segment([8, 0, 8, 9], 2, 6).nil?, 'clip 밖'

# 글자 안전화: CP949 에 없는 em dash 등은 치환(예전 제목 '가구 도면 ?상세 도면' 원인)
em = "—"
assert L.clean_text("가구 도면 #{em} 상세 도면") == '가구 도면 - 상세 도면', 'em dash 치환'
assert L.clean_text("정면도·평면도 × 2") == "정면도·평면도 × 2", 'CP949 문자는 유지'
assert L.clean_text("😀A") == ' A', '이모지 제거'
assert L.scale_label(20) == '1/20' && L.scale_label(nil) == 'N.T.S', 'scale label'
puts 'sheet_layout_test: OK'

# ── 장(유닛) 세부 쪽 ──
units = [{ index: 0, name: '하부장 1', size: [800, 580, 720] }, { index: 1, name: '서랍장', size: [600, 580, 720] }, { index: 2, name: '키큰장', size: [450, 600, 2100] }]
[[3600, 650, 900], [600, 550, 720]].each do |sz|
  plan = L.plan(sz, 'units' => units)
  assert L.problems(plan).empty?, "units: #{L.problems(plan)}"
  ups = plan[:pages].select { |pg| pg[:id] == 'unit' }
  assert ups.length == 3, '장마다 한 쪽'
  assert ups.map { |pg| pg[:unit] } == [0, 1, 2], '장 순서 유지'
  ups.each_with_index do |pg, i|
    assert pg[:title].start_with?("장 #{i + 1} / 3 - "), "장 쪽 제목 #{pg[:title]}"
    assert L::STD_DENS.include?(pg[:scale]), '장 쪽 표준 배율'
    assert pg[:views].map { |v| v[:name] } .sort == %w[u_front u_inner u_section u_top], '장 쪽 뷰 구성'
    assert pg[:boxes][:table][2] == L::TABLE_W, '장 표 폭'
    assert pg[:views].all? { |v| v[:den] == pg[:scale] }, '장 쪽 단일 배율'
  end
  assert plan[:pages].last[:total] == plan[:pages].length && plan[:pages].last[:number] == plan[:pages].length, '쪽 번호'
end
assert L.plan([600, 550, 720], 'pages' => %w[iso], 'units' => units)[:pages].length == 4, '입체도 + 장 3쪽'
big = (0...20).map { |i| { index: i, name: "m#{i}", size: [400, 580, 720] } }
begin
  L.plan([3600, 650, 900], 'units' => big)
  assert false, '장 너무 많음'
rescue RuntimeError => e
  assert e.message.include?('장이 너무 많습니다'), e.message
end
lines = L.unit_table_lines({ name: '서랍장', size: [600.0, 580.0, 720.0], number: 2, count: 3,
  parts: [{ role: 'side_left', dims: [720, 580, 18] }, { role: 'side_right', dims: [18, 580, 720] }, { role: 'bottom', dims: [564, 560, 18] },
          { role: 'drawer_front_0', dims: [596, 200, 18] }, { role: 'drawer_front_1', dims: [596, 200, 18] }, { role: 'drawer_side_left', dims: [500, 150, 15] }, { role: 'shelf_0', dims: [564, 540, 18] }] })
text = lines.join("\n")
assert text.include?('내경(= 외곽 - 36): 564'), '내경 = 외곽 - 36'
assert text.include?('서랍 2단') && text.include?('선반 1장') && text.include?('도어 0장'), "수량 #{text}"
assert text.include?('측판  720 x 580 x 18T  x2'), "측판 2장 목록 #{text}"
assert text.include?('서랍 부재'), '서랍 측판은 측판이 아님'
puts 'sheet_layout units: OK'
