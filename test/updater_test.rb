# frozen_string_literal: false
# GitHub 업데이터: 버전 확인 → 확인창 → rbz 다운로드 → install_from_archive 호출 흐름 (HTTP/SketchUp 목)
MB_YESNO = 4; IDYES = 6
$log = []
module Sketchup
  module Http
    GET = 'GET'
    Response = Struct.new(:status_code, :body)
    class Request
      class << self; attr_accessor :routes; end
      def initialize(url, _method); @url = url; end
      def start
        key = Request.routes.keys.find { |k| @url.start_with?(k) }
        code, body = key ? Request.routes[key] : [404, '']
        yield self, Response.new(code, body)
      end
    end
  end
  def self.install_from_archive(path); $log << [:install, File.binread(path, 2)]; end
end
module UI
  def self.messagebox(msg, *_); $log << [:msg, msg]; IDYES; end
  def self.openURL(u); $log << [:url, u]; end
end
module Kabinet
  VERSION = '1.10.0'
  module UI; module Dialog; def self.close_if_open; end; end; end
end
require_relative '../kabinet/updater'
def assert(v, m); raise m unless v; end
U = Kabinet::Updater
H = Sketchup::Http::Request

H.routes = { U::VERSION_URL => [200, "VERSION = '1.11.0'.freeze"], U::RBZ_URL => [200, "PK\x03\x04data"] }
st = []
U.run { |m| st << m }
assert $log.any? { |k, m| k == :msg && m.include?('v1.10.0 → v1.11.0') }, "version prompt #{$log}"
assert $log.include?([:install, 'PK']), "installed #{$log}"
assert st.last.include?('설치 완료'), "status #{st}"

$log.clear
H.routes = { U::VERSION_URL => [200, "VERSION = '1.11.0'"], U::RBZ_URL => [404, ''] }
U.run
assert $log.none? { |k, _| k == :install }, 'no install on 404'
assert $log.any? { |k, m| k == :msg && m.include?('다운로드 실패') }, "404 reported #{$log}"

$log.clear
H.routes = { U::VERSION_URL => [200, "VERSION = '1.11.0'"], U::RBZ_URL => [200, '<html>not found</html>'] }
U.run
assert $log.none? { |k, _| k == :install }, 'html body rejected'
puts 'updater_test: OK'
