# frozen_string_literal: false
# 가구 보관함: 목록(썸네일 포함), 폴더 일괄 이동, 삭제(.trash로 이동)
require 'tmpdir'
module Kabinet; end
require_relative '../kabinet/core/furniture_library'
FL = Kabinet::FurnitureLibrary
def assert(v, m); raise m unless v; end
Dir.mktmpdir do |dir|
  ids = 3.times.map do |i|
    id = format('%032x', i + 1)
    d = File.join(dir, id); Dir.mkdir(d)
    File.write(File.join(d, 'furniture.skp'), 'x')
    File.write(File.join(d, 'info.json'), JSON.generate(name: "가구#{i}", folder: '미분류', saved_at: "2026-10-0#{i + 1}T10:00:00+09:00"))
    id
  end
  File.binwrite(File.join(dir, ids[0], 'thumb.png'), "\x89PNG")
  list = FL.list(directory: dir)
  assert list.size == 3 && list.first[:name] == '가구2', 'newest first'
  assert list.find { |e| e[:id] == ids[0] }[:thumb].start_with?('data:image/png;base64,'), 'thumb data url'
  assert list.find { |e| e[:id] == ids[1] }[:thumb].nil?, 'no thumb'
  assert FL.move(ids[0, 2], '안방', directory: dir) == 2, 'move count'
  assert FL.list(directory: dir).count { |e| e[:folder] == '안방' } == 2, 'moved'
  assert FL.delete([ids[2]], directory: dir) == 1 && FL.list(directory: dir).size == 2, 'deleted'
  assert Dir.exist?(File.join(dir, '.trash', ids[2])), 'kept in trash'
  begin; FL.move(['../x'], 'a', directory: dir); raise 'x'; rescue ArgumentError; end
end
puts 'furniture_library_test: OK'
