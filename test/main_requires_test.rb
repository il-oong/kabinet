require 'minitest/autorun'

# 새 .rb 파일을 만들고 main.rb 의 시작 require 목록에 넣는 것을 잊으면
# 실행 중 'uninitialized constant' 가 난다(v1.32.0 3D 내보내기 사례). 그것을 막는다.
class MainRequiresTest < Minitest::Test
  ROOT = File.expand_path('../kabinet', __dir__)
  MAIN = File.read(File.join(ROOT, 'main.rb'), encoding: 'UTF-8')

  # 다른 파일이 require 하거나 단독 로드되는 파일은 제외
  SKIP = %w[main.rb].freeze

  def test_every_command_and_output_file_is_required_at_startup
    startup = MAIN.lines.select { |l| l =~ /\Arequire File\.join/ }.join
    missing = []
    Dir.glob(File.join(ROOT, '{commands,output}', '*.rb')).sort.each do |f|
      rel = f.sub(ROOT + '/', '')
      next if SKIP.include?(rel)
      dir, base = rel.sub(/\.rb\z/, '').split('/')
      missing << rel unless startup.include?("'#{dir}', '#{base}'")
    end
    assert_empty missing, "main.rb 시작 require 목록에 없음: #{missing.join(', ')}"
  end
end
