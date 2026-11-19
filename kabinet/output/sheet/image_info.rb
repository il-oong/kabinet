require_relative 'text'
module Kabinet
  module Output
    module Sheet
      # 이미지 파일 크기(px) 읽기 — PNG/JPEG 헤더만 파싱 (외부 라이브러리 불필요)
      module ImageInfo
        module_function

        # => [width, height] 또는 nil
        def size(path)
          File.open(Text.resolve_path(path), 'rb') do |f|
            head = (f.read(32) || ''.b).b
            if head.start_with?("\x89PNG\r\n\x1a\n".b)
              return head[16, 8].unpack('NN')
            elsif head.start_with?("\xFF\xD8".b)
              f.rewind
              return jpeg_size(f)
            end
          end
          nil
        rescue StandardError
          nil
        end

        def jpeg_size(f)
          f.read(2)
          loop do
            b = f.read(1)
            return nil if b.nil?
            next unless b == "\xFF".b
            m = f.read(1)
            return nil if m.nil?
            mm = m.ord
            next if mm == 0xFF || mm == 0xD8 || (mm >= 0xD0 && mm <= 0xD7) || mm == 0x01
            len = f.read(2).to_s.unpack1('n').to_i
            if [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].include?(mm)
              data = f.read(5).to_s
              h, w = data[1, 4].unpack('nn')
              return [w, h]
            end
            f.read(len - 2)
          end
        end

        def image?(path)
          %w[.png .jpg .jpeg].include?(File.extname(path.to_s).downcase)
        end
      end
    end
  end
end
