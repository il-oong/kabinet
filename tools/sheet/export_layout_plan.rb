# 가구 도면(LayOut) 쪽 배치 계획을 JSON 으로 내보낸다 — 미리보기(preview_layout.py)·검증용.
# 사용: ruby tools/sheet/export_layout_plan.rb W D H [iso,front,side]   (mm)
require 'json'
require_relative '../../kabinet/output/sheet_layout'
w, d, h = ARGV[0, 3].map(&:to_f)
abort '사용: ruby export_layout_plan.rb W D H [pages]' if [w, d, h].any?(&:zero?)
pages = (ARGV[3] || 'iso,front,side').split(',')
plan = Kabinet::Output::SheetLayout.plan([w, d, h], 'pages' => pages)
plan[:problems] = Kabinet::Output::SheetLayout.problems(plan)
puts JSON.generate(plan)
