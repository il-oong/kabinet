# 입력 CAD 도면(DXF) → 제작도면 시트 DXF 재구성 (CLI).
#   ruby tools/sheet/import_dxf.rb 입력1.dxf [입력2.dxf ...] [--out 폴더] [--site 현장명] [--bg white|dark|none]
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'json'
require 'fileutils'
require 'kabinet/output/sheet'
S = Kabinet::Output::Sheet
args = ARGV.dup
opt = ->(k, d) { (i = args.index(k)) ? (args.slice!(i, 2)[1]) : d }
out = opt.call('--out', 'output_samples/reconstructed')
site = opt.call('--site', '')
bg = opt.call('--bg', 'white')
FileUtils.mkdir_p(out)
args.each do |f|
  r = S::DxfImport.from_file(f, site: site)
  puts "== #{File.basename(f)}"
  puts r[:report].map { |l| "  #{l}" }
  r[:models].each do |m|
    base = S::Text.safe_name(m['furniture_name'])
    path = File.join(out, "#{base}.dxf")
    S::Builder.export({ 'site' => site, 'bg' => bg }, m, path)
    File.write(File.join(out, "#{base}.json"), JSON.pretty_generate(m))
    puts "  -> #{path}"
  end
end
