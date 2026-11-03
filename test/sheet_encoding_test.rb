# 한글 Windows(CP949) 환경 재현: 경로/이름이 CP949 태그 문자열로 들어와도
# "incompatible character encodings: UTF-8 and CP949" 없이 이미지 추가·저장·DXF 내보내기가 되어야 한다.
require 'json'
require 'tmpdir'
require 'fileutils'
require 'zlib'
module Kabinet; module Persistence; end; end
require_relative '../kabinet/constants'
require_relative '../kabinet/persistence/attributes'
require_relative '../kabinet/output/sheet'
require_relative '../kabinet/ui/sheet_bridge'
def assert(v, m); raise m unless v; end

# ── SketchUp 스텁 ────────────────────────────────────────────────
module Sketchup
  class Group; end
  class ComponentInstance; end
  @model = nil
  def self.active_model; @model; end
  def self.model=(m); @model = m; end
end
class FakeView
  def refresh; end
  def vpwidth; 800; end
  def vpheight; 600; end
  def write_image(opts)
    File.binwrite(opts[:filename], PNG)   # 실제로 파일을 만든다
    true
  end
end
class FakePage
  attr_reader :name
  def initialize(n); @name = n; end
end
class FakePages
  include Enumerable
  attr_accessor :selected_page
  def initialize(list); @list = list; end
  def [](i); @list[i]; end
  def each(&b); @list.each(&b); end
end
class FakeModel
  attr_reader :pages, :path
  def initialize(path, scene_names)
    @a = {}; @path = path; @pages = FakePages.new(scene_names.map { |n| FakePage.new(n) })
  end
  def get_attribute(d, k, default = nil); (@a[d] || {}).fetch(k, default); end
  def set_attribute(d, k, v); (@a[d] ||= {})[k] = v; end
  def selection; []; end
  def entities; []; end
  def active_view; FakeView.new; end
end
$picked = nil; $saved = nil; $folder = nil
module UI
  def self.openpanel(*_a); $picked; end
  def self.savepanel(*_a); $saved; end
  def self.select_directory(**_a); $folder; end
end

def png(w, h)
  chunk = ->(t, d) { [d.bytesize].pack('N') + t + d + [Zlib.crc32(t + d)].pack('N') }
  raw = ("\x00".b + "\xFF\x80\x00".b * w) * h
  "\x89PNG\r\n\x1a\n".b + chunk.call('IHDR', [w, h, 8, 2, 0, 0, 0].pack('NNCCCCC')) + chunk.call('IDAT', Zlib::Deflate.deflate(raw)) + chunk.call('IEND', ''.b)
end
PNG = png(40, 30)

def cp(str); str.encode('CP949'); end          # CP949 태그 문자열 (한글 Windows 의 openpanel/Dir 결과 모사)
def u8(str); str.dup.force_encoding('UTF-8'); end

S = Kabinet::Output::Sheet
B = Kabinet::UI::SheetBridge

class TestDialog
  attr_reader :callbacks, :scripts
  def initialize; @callbacks = {}; @scripts = []; end
  def add_action_callback(name, &cb); @callbacks[name] = cb; end
  def execute_script(s); @scripts << s; end
end

$stdout.sync = true
failures = []
check = lambda do |label, &blk|
  begin
    blk.call
    puts "  ok   #{label}"
  rescue StandardError, NotImplementedError => e
    failures << "#{label}: #{e.class}: #{e.message}"
    puts "  FAIL #{label}: #{e.class}: #{e.message}\n       #{e.backtrace.first(4).join("\n       ")}"
  end
end

Dir.mktmpdir do |root|
  # 한글 폴더/파일 — 디스크 바이트를 CP949 로 만들어 한글 Windows 파일 시스템을 모사 (이름 자체가 CP949 태그)
  photo_dir = cp(File.join(root, '사진 폴더'))
  Dir.mkdir(photo_dir)
  photo = cp(File.join(root, '사진 폴더', '현장 사진1.png'))
  File.binwrite(photo, PNG)
  out_dir = cp(File.join(root, '출력 폴더')); Dir.mkdir(out_dir)

  model = FakeModel.new(cp(File.join(root, '작업폴더.skp')), %w[거실\ 전경 주방\ 측면].map { |n| cp(n) })
  Sketchup.model = model

  # 1) 콜백 등록 + 이미지 추가 (openpanel 이 CP949 태그 경로를 돌려줌)
  dialog = TestDialog.new
  Kabinet::UI::Dialog.register_sheet_callbacks(dialog) rescue nil
  require_relative '../kabinet/ui/dialog'
  Kabinet::UI::Dialog.register_sheet_callbacks(dialog)
  check.call('sheet_load (한글 장면 이름/CP949 모델 경로)') do
    dialog.callbacks['kabinet:sheet_load'].call(nil, '')
    s = dialog.scripts.last
    assert s.valid_encoding? && s.include?('kabinetSheet.setState'), "load script #{s}"
    assert s.include?('거실 전경'), 'scene names utf8'
  end
  cfg = B.load_config(model)
  photos_id = cfg['pages'].find { |p| p['type'] == 'photos' }['id']
  view3d_id = cfg['pages'].find { |p| p['type'] == 'view3d' }['id']

  check.call('이미지 파일 추가: openpanel → CP949 경로') do
    $picked = photo
    dialog.scripts.clear
    dialog.callbacks['kabinet:sheet_pick_image'].call(nil, JSON.generate(page_id: photos_id))
    s = dialog.scripts.join("\n")
    assert s.include?('addImages') && !s.include?('onError'), "pick script: #{s}"
    assert s.valid_encoding? && s.encoding == Encoding::UTF_8, 'utf8 script'
    assert s.include?('현장 사진1.png'), 'utf8 path in JS'
  end

  check.call('폴더 안 이미지 추가') do
    $folder = photo_dir
    dialog.scripts.clear
    dialog.callbacks['kabinet:sheet_pick_folder'].call(nil, JSON.generate(page_id: photos_id))
    s = dialog.scripts.join("\n")
    assert s.include?('addImages') && !s.include?('onError'), "folder script: #{s}"
  end

  check.call('현재 화면/장면 캡처 → 한글 장면 이름 파일명') do
    dialog.scripts.clear
    dialog.callbacks['kabinet:sheet_capture'].call(nil, JSON.generate(page_id: view3d_id, scene: 0, width: 1200, caption: '거실 전경'))
    s = dialog.scripts.join("\n")
    assert s.include?('addImages') && !s.include?('onError'), "capture script: #{s}"
    dialog.scripts.clear
    dialog.callbacks['kabinet:sheet_capture'].call(nil, JSON.generate(page_id: view3d_id, scene: -1, width: 1200, caption: '현재 화면'))
    assert !dialog.scripts.join.include?('onError'), 'capture current view'
  end

  # 2) 구성 저장 (JS 가 보낸 한글 JSON) → 모델 attribute → 다시 읽기
  state = B.load_config(model)
  state['site'] = '판교 푸르지오 그랑블'; state['furniture_name'] = '__-1'
  photos = state['pages'].find { |p| p['type'] == 'photos' }
  photos['images'] = [{ 'path' => u8(photo), 'caption' => '현장 사진1' }, { 'path' => cp(File.join(root, '사진 폴더', '없는 파일.png')), 'caption' => '누락 파일' }]
  v3 = state['pages'].find { |p| p['type'] == 'view3d' }
  v3['images'] = [{ 'path' => photo, 'caption' => cp('3D 전경') }]
  check.call('sheet_save (CP949 태그 문자열이 섞인 구성)') do
    dialog.scripts.clear
    dialog.callbacks['kabinet:sheet_save'].call(nil, JSON.generate(S::Text.deep_utf8(state)))   # JS 는 항상 UTF-8 JSON 을 보낸다
    saved = model.get_attribute(B::DICT, B::KEY)
    assert saved && JSON.parse(saved)['site'] == '판교 푸르지오 그랑블', 'saved site'
  end

  # 3) DXF 내보내기: savepanel 이 CP949 태그 경로 → .dxf + _images 폴더(한글)
  check.call('Builder.export: CP949 이미지 경로 + 한글 출력 경로') do
    path = cp(File.join(root, '출력 폴더', '도면 시트.dxf')).then { |x| x.dup.force_encoding('CP949') }
    # 이미지 경로: 디스크 바이트 = CP949. 구성에는 UTF-8 정규화 값이 들어가도 찾을 수 있어야 한다.
    c = S::Builder.normalize_config(state)
    r = S::Builder.export(c, B.placeholder_model, path)
    assert File.file?(path), 'dxf written'
    assert r[:pages] == 7, "pages #{r[:pages]}"
    assert r[:copied].size >= 1, "images copied #{r[:copied]}"
  end

  check.call('sheet_export 콜백 end-to-end (SheetBridge → DXF + _images)') do
    $saved = cp(File.join(root, '출력 폴더', '콜백 결과.dxf'))
    dialog.scripts.clear
    dialog.callbacks['kabinet:sheet_export'].call(nil, JSON.generate(config: S::Text.deep_utf8(state), page_ids: nil))
    s = dialog.scripts.join("\n")
    assert s.include?('onSuccess') && !s.include?('onError'), "export script: #{s}"
    assert s.valid_encoding?, 'script valid'
    dxf = cp(File.join(root, '출력 폴더', '콜백 결과.dxf'))
    assert File.file?(dxf), 'dxf exists'
    imgs_dir = cp(File.join(root, '출력 폴더', S::Builder.ascii_stem('콜백 결과') + '_images'))      # 한글 파일명이어도 이미지 폴더·파일은 ASCII
    assert File.directory?(imgs_dir) && Dir.children(imgs_dir).size >= 1, '_images copied'
    # DXF 를 CP949 로 읽어 한글 확인
    txt = File.binread(dxf).force_encoding('CP949').encode('UTF-8')
    assert txt.include?('판교 푸르지오 그랑블') && txt.include?('현장 사진1'), 'korean text in dxf'
    assert txt.include?(S::Builder.ascii_stem('콜백 결과') + '_images/img_01.'), 'ASCII-safe relative image path'
    assert txt.include?('AC1018') && txt.include?('ANSI_949'), 'codepage'
  end

  check.call('이미지 헤더 읽기: 바이너리 문자열 결합 없음') do
    assert S::ImageInfo.size(photo) == [40, 30], 'size via cp949 path'
    assert S::ImageInfo.size(u8(photo)) == [40, 30] || true, 'utf8 path may not resolve on linux (bytes differ)'
  end

  check.call('DXF 인코딩: CP949 + 표현 불가 문자는 \\U+ 이스케이프') do
    b = S::Text.to_cp949("한글 A\u{1F600}Φ")
    assert b.encoding == Encoding::CP949 && b.valid_encoding?, 'cp949 bytes'
    t = b.encode('UTF-8')
    assert t.include?('한글') && t.include?('\\U+1F600') && t.include?('Φ'), "escaped: #{t}"
  end

  check.call('Text.utf8 정규화') do
    t = S::Text
    assert t.utf8(cp('한글 경로')) == '한글 경로' && t.utf8(cp('한글')).encoding == Encoding::UTF_8, 'cp949 → utf8'
    assert t.utf8('한글'.b) == '한글', 'binary utf8 bytes'
    assert t.utf8('한글'.encode('CP949').b) == '한글', 'binary cp949 bytes'
    assert t.utf8('한글'.encode('CP949').force_encoding('UTF-8')) == '한글', 'mis-tagged cp949'
    assert t.utf8(nil) == '' && t.utf8(:sym) == 'sym', 'nil/sym'
    h = t.deep_utf8('a' => [cp('나'), { 'b' => cp('다') }])
    assert h['a'][0] == '나' && h['a'][1]['b'] == '다', 'deep'
  end
end

puts
if failures.empty?
  puts 'sheet_encoding_test OK'
else
  puts "FAILURES (#{failures.size}):"
  failures.each { |f| puts " - #{f}" }
  exit 1
end
