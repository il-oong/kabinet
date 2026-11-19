require_relative 'text'
module Kabinet
  module Output
    module Sheet
      # 순수 Ruby DXF 리더 (입력 CAD 도면 → 엔티티 Hash 목록).
      # 지원: LINE ARC CIRCLE LWPOLYLINE POLYLINE/VERTEX INSERT MTEXT TEXT DIMENSION. 나머지는 건너뜀.
      # 좌표는 도면 단위(대부분 mm). 문자열은 UTF-8.
      module DxfReader
        module_function

        KEEP = %w[LINE ARC CIRCLE LWPOLYLINE POLYLINE VERTEX SEQEND INSERT MTEXT TEXT DIMENSION].freeze

        Doc = Struct.new(:entities, :blocks, :insunits) do
          def of(type)
            entities.select { |e| e[:type] == type }
          end
        end

        def read(path)
          parse(File.binread(Text.resolve_path(path)))
        end

        def parse(bytes)
          text = decode(bytes)
          lines = text.split(/\r?\n/)
          sec = nil
          blk = nil
          cur = nil
          ents = []
          blocks = {}
          insunits = nil
          i = 0
          n = lines.size
          flush = lambda do
            if cur
              target = sec == 'BLOCKS' ? (blk && blk[:list]) : ents
              target << cur if target && KEEP.include?(cur[:type])
              cur = nil
            end
          end
          last_header = nil
          while i + 1 < n
            code = lines[i].strip.to_i
            val = lines[i + 1]
            i += 2
            if code.zero?
              flush.call
              v = val.strip
              case v
              when 'SECTION' then next
              when 'ENDSEC' then sec = nil; blk = nil
              when 'BLOCK' then blk = { name: nil, list: [] }; cur = { type: 'BLOCK_HDR', layer: '0' }
              when 'ENDBLK' then (blocks[blk[:name]] = blk[:list]) if blk && blk[:name]; blk = nil
              else
                cur = { type: v, layer: '0' } if KEEP.include?(v) && %w[ENTITIES BLOCKS].include?(sec)
                cur = nil if !KEEP.include?(v) && v != 'BLOCK_HDR'
              end
              next
            end
            if sec.nil? && code == 2
              sec = val.strip
              next
            end
            if sec == 'HEADER'
              last_header = val.strip if code == 9
              insunits = val.strip.to_i if code == 70 && last_header == '$INSUNITS'
              next
            end
            next unless cur
            if cur[:type] == 'BLOCK_HDR'
              blk[:name] = Text.utf8(val.strip) if code == 2 && blk[:name].nil?
              next
            end
            assign(cur, code, val)
          end
          flush.call
          Doc.new(group_polylines(ents), blocks.transform_values { |l| group_polylines(l) }, insunits)
        end

        def decode(bytes)
          s = bytes.dup.force_encoding(Encoding::UTF_8)
          return s if s.valid_encoding?
          Text.utf8(bytes.dup.force_encoding(Encoding::CP949)) rescue bytes.dup.force_encoding('BINARY').encode('UTF-8', invalid: :replace, undef: :replace)
        end

        def assign(e, code, val)
          f = val.strip
          case code
          when 8 then e[:layer] = Text.utf8(f)
          when 2 then e[:name] = Text.utf8(f)
          when 10
            if e[:type] == 'LWPOLYLINE' then (e[:pts] ||= []) << [f.to_f, 0.0]
            else e[:x] = f.to_f
            end
          when 20
            if e[:type] == 'LWPOLYLINE' then e[:pts].last[1] = f.to_f
            else e[:y] = f.to_f
            end
          when 11 then e[:x2] = f.to_f
          when 21 then e[:y2] = f.to_f
          when 13 then e[:x3] = f.to_f
          when 23 then e[:y3] = f.to_f
          when 14 then e[:x4] = f.to_f
          when 24 then e[:y4] = f.to_f
          when 40 then e[:h] = f.to_f
          when 41 then e[:sx] = f.to_f
          when 42
            if e[:type] == 'DIMENSION' then e[:meas] = f.to_f else e[:sy] = f.to_f end
          when 50 then e[:rot] = f.to_f
          when 70
            if e[:type] == 'DIMENSION' then e[:dimtype] = f.to_i & 7
            elsif e[:type] == 'LWPOLYLINE' then e[:closed] = (f.to_i & 1) == 1
            elsif e[:type] == 'POLYLINE' then e[:closed] = (f.to_i & 1) == 1
            end
          when 1
            e[:text] = (e[:text] || +'') << Text.utf8(f)
          when 3
            e[:text] = (e[:text] || +'') << Text.utf8(f) if e[:type] == 'MTEXT'
          end
        end

        # 앞에서부터 보지 않고 끝에서 잇는 MTEXT 청크 순서 보정: code 3(청크)가 code 1 보다 먼저 오므로 그대로 이어붙이면 안 됨 → 단순화: 최종 텍스트 정리
        def clean_mtext(s)
          s.to_s.gsub(/\\P/, "\n").gsub(/\\[A-Za-z][^;]*;/, '').gsub(/[{}]/, '').gsub(/%%[cC]/, 'Φ').strip
        end

        # POLYLINE/VERTEX/SEQEND → LWPOLYLINE 하나로
        def group_polylines(list)
          out = []
          cur = nil
          list.each do |e|
            case e[:type]
            when 'POLYLINE' then cur = { type: 'LWPOLYLINE', layer: e[:layer], pts: [], closed: e[:closed] }
            when 'VERTEX' then cur[:pts] << [e[:x].to_f, e[:y].to_f] if cur
            when 'SEQEND' then (out << cur; cur = nil) if cur
            else out << e
            end
          end
          out
        end

        # 폴리선/라인 → 선분 [[x1,y1,x2,y2],...]
        def segments(e)
          case e[:type]
          when 'LINE' then [[e[:x], e[:y], e[:x2], e[:y2]]]
          when 'LWPOLYLINE'
            p = e[:pts] || []
            segs = (0...p.size - 1).map { |k| [p[k][0], p[k][1], p[k + 1][0], p[k + 1][1]] }
            segs << [p[-1][0], p[-1][1], p[0][0], p[0][1]] if e[:closed] && p.size > 2
            segs
          else []
          end
        end
      end
    end
  end
end
