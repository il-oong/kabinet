# 정규화 가구 JSON(furniture.json) -> Ruby 시트 DXF (플러그인과 같은 코드 경로). 비교/검증용 CLI.
#   ruby tools/sheet/export_sheet.rb furniture.json out.dxf [--bg white|dark|none] [--scale N]
#        [--paper] (종이 mm 좌표, 기본은 1:1 실치수)  [--no-images]  [--site 현장명]
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'json'
require 'kabinet/output/sheet'
S = Kabinet::Output::Sheet
args = ARGV.dup
flag = ->(k) { args.delete(k) ? true : false }
opt = ->(k, d) { (i = args.index(k)) ? args.slice!(i, 2)[1] : d }
paper = flag.call('--paper'); no_img = flag.call('--no-images')
bg = opt.call('--bg', 'white'); scale = opt.call('--scale', nil); site = opt.call('--site', nil)
src, out = args
abort 'usage: export_sheet.rb furniture.json out.dxf' unless src && out
data = JSON.parse(File.read(src, encoding: 'UTF-8'))
cfg = { 'bg' => bg, 'real_scale' => !paper, 'images' => !no_img, 'site' => site || data['site'].to_s,
        'furniture_name' => data['furniture_name'].to_s,
        'pages' => [%w[floor 평면도], %w[furniture 가구\ 시트], %w[side 측면·단면], %w[detail 상세], %w[table 생산\ 확인표]].map do |t, n|
          S::Builder.page(t, n, 'scale' => scale.to_s)
        end }
r = S::Builder.export(cfg, data, out)
puts "ok pages=#{r[:pages]} real_scale=#{r[:real_scale]}"
