require_relative 'canvas'
module Kabinet
  module Output
    module Sheet
      # 양식 틀 (SHEET_FORMAT_ANALYSIS.md §2) — 좌표는 샘플 PDF 4쪽 실측.
      module Frame
        module_function

        # info: { site:, title:, subject:, sheet_no:, date:, scale: (Integer 분모 또는 nil) }
        def title_block(c, info)
          tag = lambda do |x, y, label, w|
            c.rect(x, y, x + w, y + 2.7, 'OUT')
            c.fill([[x, y], [x + w, y], [x + w, y + 2.7], [x, y + 2.7]], [85, 85, 85])
            c.text(x + 0.8, y + 2.05, label, 1.7, 'w', 'l')
          end
          c.line(9.4, 267.5, 410.6, 267.5, 'SEC')
          tag.call(58.2, 272.7, 'SITE LOCATION', 22.0);  c.line(58.2, 276.2, 218.0, 276.2, 'OUT')
          tag.call(58.2, 283.4, 'PROJECT TITLE', 22.0);  c.line(58.2, 286.4, 218.0, 286.4, 'OUT')
          tag.call(230.3, 272.7, 'SHEET NO.', 22.0);     c.line(230.3, 276.2, 294.3, 276.2, 'OUT')
          tag.call(230.3, 283.4, 'SUBJECT TITLE', 22.0); c.line(230.3, 286.4, 294.3, 286.4, 'OUT')
          tag.call(306.9, 272.7, 'DATE', 10.5);          c.line(306.9, 276.2, 363.4, 276.2, 'OUT')
          tag.call(306.9, 283.4, 'SCALE', 10.5);         c.line(306.9, 286.4, 363.4, 286.4, 'OUT')
          site_text(c, info[:site])
          c.text(84.0, 285.2, info[:title], 4.2)
          c.text(256.0, 275.0, info[:sheet_no], 4.2)
          c.text(256.0, 285.2, info[:subject], 3.4)
          c.text(321.0, 275.0, info[:date], 3.4)
          c.text(321.0, 285.2, info[:scale] ? "1/#{info[:scale]}" : '', 4.2)
        end

        # SITE LOCATION 칸(폭 약 134mm): 한 줄에 들어가면 4.2, 길면 도로명 번지(숫자) 뒤에서 2줄(3.0), 그래도 넘치면 글자 축소
        def site_text(c, text, x = 84.0, maxw = 110.0)
          text = text.to_s
          return if text.empty?
          if Sheet.text_width(text, 4.2) <= maxw
            c.text(x, 275.0, text, 4.2)
            return
          end
          words = text.split(' ')
          cut = (1...words.size).find { |k| words[k - 1] =~ /\A\d+\z/ && words[k] !~ /\A\d+\z/ }
          cut ||= (1...words.size).min_by { |k| (Sheet.text_width(words[0...k].join(' '), 3.0) - Sheet.text_width(words[k..-1].join(' '), 3.0)).abs } || 1
          l1 = words[0...cut].join(' '); l2 = words[cut..-1].to_a.join(' ')
          w = [Sheet.text_width(l1, 3.0), Sheet.text_width(l2, 3.0)].max
          sz = w > maxw ? 3.0 * maxw / w : 3.0
          c.text(x, 271.9, l1, sz)
          c.text(x, 275.3, l2, sz) unless l2.empty?
        end

        # '현장 안내' 쪽 틀: 헤더 SITE INFO(좌) / NOTE(우), 가운데 세로선, 표제란은 다른 시트와 같은 양식
        def info(c, info)
          l = 9.4; r = 410.6
          c.rect(4.5, 3.2, 415.5, 293.9, 'FR')
          c.rect(l, 8.1, r, 289.0, 'FRTH')
          c.line(l, 18.0, r, 18.0, 'SEC')
          c.text(17.2, 14.5, 'SITE INFO', 4.2)
          c.text(218.3, 14.5, 'NOTE', 4.2)
          c.line(210.3, 8.6, 210.3, 267.5, 'SEC')
          title_block(c, info)
        end

        # TOP VIEW / NOTE / FRONT 헤더가 있는 가구 시트 틀
        def furniture(c, info, hdr: 'TOP VIEW', hdr2: ['FRONT VIEW_ DOOR', 'FRONT VIEW_ BODY'], boundary: 114.3, note: true)
          l = 9.4; r = 410.6
          c.rect(4.5, 3.2, 415.5, 293.9, 'FR')
          c.rect(l, 8.1, r, 289.0, 'FRTH')
          c.line(l, 18.0, r, 18.0, 'SEC')
          c.text(17.2, 14.5, hdr, 4.2)
          if note
            c.text(218.3, 14.5, 'NOTE', 4.2)
            c.line(210.3, 8.6, 210.3, boundary, 'SEC')
            [30.1, 42.1, 54.2].each { |y| c.line(210.3, y, r, y, 'FR') }
          end
          c.line(l, boundary, r, boundary, 'SEC')
          c.line(l, boundary + 9.9, r, boundary + 9.9, 'SEC')
          c.text(17.2, boundary + 6.5, hdr2[0], 4.2)
          c.text(218.3, boundary + 6.5, hdr2[1], 4.2)
          title_block(c, info)
        end

        # 헤더 한 줄(예: SITE PHOTO) + 표제란만 있는 틀
        def simple(c, info, header)
          c.rect(4.5, 3.2, 415.5, 293.9, 'FR')
          c.rect(9.4, 8.1, 410.6, 289.0, 'FRTH')
          c.line(9.4, 18.0, 410.6, 18.0, 'SEC')
          c.text(17.2, 14.5, header, 4.2)
          title_block(c, info)
        end

        # 평면도 시트(도곽 없음): 방 이름 + 하단 문구 + SCALE
        def plan(c, info, room_title, sub_title)
          c.rect(4.5, 3.2, 415.5, 293.9, 'FR')
          c.text(17.0, 21.0, room_title, 8.5)
          c.text(19.0, 277.0, info[:site], 4.9)
          c.text(19.0, 286.4, sub_title, 4.9)
          c.text(400.0, 286.4, info[:scale] ? "SCALE 1/#{info[:scale]}" : '', 4.9, 'k', 'r')
        end

        # 표(생산 확인표 등)용 틀
        def table(c, info, title)
          c.rect(4.5, 3.2, 415.5, 293.9, 'FR')
          c.text(17.0, 21.0, title, 8.5)
          c.text(19.0, 277.0, info[:site], 4.9)
          c.text(19.0, 286.4, "#{info[:title]} #{title}", 4.9)
        end
      end
    end
  end
end
