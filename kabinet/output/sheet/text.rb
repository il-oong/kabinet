module Kabinet
  module Output
    module Sheet
      # 문자열 인코딩 정규화 — 한글 Windows 에서 UI.openpanel / Dir / File.basename 등이 CP949(또는 BINARY) 태그
      # 문자열을 돌려줘도 UTF-8 한글 문자열과 섞일 때 Encoding::CompatibilityError 가 나지 않게 한다.
      #
      # 원칙: JSON·화면 표시·DXF 내용용 문자열은 항상 UTF-8(`utf8`)로 바꿔 다루고,
      #       파일을 실제로 열고 쓸 때는 원본 경로(또는 `resolve_path` 가 찾아 준 경로)를 쓴다.
      module Text
        module_function

        UTF8 = Encoding::UTF_8
        BIN  = Encoding::BINARY

        # => 항상 유효한 UTF-8 문자열(새 객체). nil → '', Symbol/숫자 → to_s
        def utf8(value)
          return '' if value.nil?
          s = value.is_a?(String) ? value : value.to_s
          enc = s.encoding
          return s.dup if (enc == UTF8 || enc == Encoding::US_ASCII) && s.valid_encoding? && (enc == UTF8 || s.ascii_only?)
          return s.dup.force_encoding(UTF8) if enc == Encoding::US_ASCII && s.ascii_only?
          candidates(s).each do |c|
            return c if c
          end
          s.dup.force_encoding(UTF8).scrub('?')
        end

        # 가능한 해석 후보를 순서대로 시도 (nil 이면 건너뜀)
        def candidates(s)
          enc = s.encoding
          out = []
          if enc == UTF8 || enc == BIN || enc == Encoding::US_ASCII
            # UTF-8 로 유효하면 그대로, 아니면 CP949 바이트로 재해석
            u = s.dup.force_encoding(UTF8)
            out << u if u.valid_encoding?
            out << (convert(s.dup.force_encoding('CP949'), 'CP949') if cp949_valid?(s))
            out << (convert(s.dup.force_encoding(Encoding.default_external), Encoding.default_external) if Encoding.default_external != UTF8)
          else
            out << convert(s, enc)
          end
          out
        end

        def cp949_valid?(s)
          s.dup.force_encoding('CP949').valid_encoding?
        rescue StandardError
          false
        end

        def convert(s, enc)
          return nil unless s.valid_encoding?
          s.encode(UTF8, enc, invalid: :replace, undef: :replace, replace: '?')
        rescue StandardError
          nil
        end

        # Hash/Array/String 안의 모든 문자열(키 포함)을 UTF-8 로
        def deep_utf8(obj)
          case obj
          when String then utf8(obj)
          when Hash   then obj.each_with_object({}) { |(k, v), h| h[k.is_a?(String) ? utf8(k) : k] = deep_utf8(v) }
          when Array  then obj.map { |v| deep_utf8(v) }
          else obj
          end
        end

        # 파일 시스템에서 실제로 존재하는 경로를 찾는다 (원본 → UTF-8 → CP949 → 기본 외부 인코딩).
        # 존재하지 않으면 원본을 그대로 반환.
        def resolve_path(path)
          return path unless path.is_a?(String)
          tries = [path]
          u = utf8(path)
          tries << u
          tries << (u.encode('CP949') rescue nil)
          tries << (u.encode(Encoding.default_external) rescue nil) if Encoding.default_external != UTF8
          tries.compact.each do |t|
            return t if (File.exist?(t) rescue false)
          end
          path
        end

        # UTF-8 문자열 `str` 을 `like` 와 같은 인코딩으로 (경로 조합용). 변환 불가면 UTF-8 그대로.
        def native(str, like)
          s = utf8(str)
          enc = like.is_a?(String) ? like.encoding : nil
          return s if enc.nil? || enc == UTF8 || enc == BIN || enc == Encoding::US_ASCII
          s.encode(enc)
        rescue StandardError
          s
        end

        # 경로 구성요소를 UTF-8 로 합침
        def join(*parts)
          parts.map { |p| utf8(p) }.join('/').gsub(%r{/{2,}}, '/')
        end

        # 파일명으로 쓸 수 없는 문자 제거 (UTF-8)
        def safe_name(str)
          utf8(str).gsub(%r{[\\/:*?"<>|\s]}, '_')
        end

        # DXF 본문(UTF-8) → CP949 바이트. CP949 로 표현 못 하는 문자는 \U+XXXX 이스케이프(AutoCAD·LibreCAD 해석)로.
        def to_cp949(text)
          text.encode(Encoding::CP949)
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          out = String.new(encoding: Encoding::CP949)
          text.each_char do |ch|
            begin
              out << ch.encode(Encoding::CP949)
            rescue StandardError
              out << format('\\U+%04X', ch.ord).encode(Encoding::CP949)
            end
          end
          out
        end
      end
    end
  end
end
