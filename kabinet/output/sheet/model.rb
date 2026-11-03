require_relative 'text'
module Kabinet
  module Output
    module Sheet
      # 시트용 정규화 가구 데이터 (output_samples/furniture.json 과 같은 개념의 일반형).
      # 순수 Ruby — Schema.normalize 를 거친 가구 spec(Hash) 또는 수작업 JSON 에서 만든다.
      #
      # {
      #   'furniture_name' =>, 'overall' => {'W','H','D','top_thickness','kick'},
      #   'ep' => {'left','right','top','thickness'},
      #   'modules' => [{'name','x','z','w','h','d','type'(doors|drawers|open),
      #                   'doors'(0..2),'drawers'(n),'shelves'=>[z...],'rods'=>[z...],'flags'=>[],'label'=>'짧은 표기'}],
      #   'type'(appliance 모듈 = 가전 자리), 'channel'(목찬넬 손잡이 → 상세 쪽), 'sink' => {'x','y','w','d'}(평면 싱크 컷),
      #   'cut_x' => 단면 1 절단 X(평면 좌표) 또는 'cuts' => [x1, x2](단면 1~2), 'table_rows' => [[항목, 가정값, 확인]...],
      #   'notes' => {'DOOR','BODY','handle'}, 'room' => {'W','D','name'}, 'flags' => []
      # (tools/sheet/build_generic.py 의 furniture.json 스키마와 같은 모양이라 같은 JSON 을 Ruby/Python 양쪽에 넣을 수 있다)
      # }
      module Model
        module_function

        DEFAULT_NOTES = {
          'DOOR' => '목림 지정 자재-안도크림 색상 (확인필요)',
          'BODY' => '목림 지정 자재 (확인필요)',
          'handle' => '지정 손잡이 (확인필요)'
        }.freeze

        def num(v, d = 0.0)
          v.nil? ? d : Float(v)
        rescue ArgumentError, TypeError
          d
        end

        # Schema.normalize 된 spec -> 시트 모델
        def from_spec(spec, furniture_name: nil)
          w = num(spec['width'])
          d = num(spec['max_depth'], 600)
          base = num(spec['base_height'])
          top = spec['top_panel'] ? num(spec['top_panel']['thickness'], 20) : 0.0
          ep = spec['ep'] || {}
          mods = []
          flags = []
          if spec['run_mode']
            x = 0.0
            (spec['modules'] || []).each_with_index do |m, i|
              mw = num(m['width'], 600)
              mods << module_from(m, i, x, base, mw, num(m['height'], num(spec['run_height'], 740)), num(m['depth'], d))
              x += mw
            end
            w = x if x > w
          else
            z = base
            (spec['modules'] || []).each_with_index do |m, i|
              mh = num(m['height'], 0)
              mods << module_from(m, i, 0.0, z, num(m['width'], 0) > 0 ? num(m['width']) : w, mh, num(m['depth'], 0) > 0 ? num(m['depth']) : d)
              z += mh
            end
          end
          h = mods.map { |m| m['z'] + m['h'] }.max.to_f + top
          channel = (spec['modules'] || []).any? { |m| m['handle_type'].to_s == 'channel' }
          normalize('furniture_name' => furniture_name || spec['name'] || 'Furniture', 'channel' => channel,
                    'overall' => { 'W' => w, 'H' => h, 'D' => d, 'top_thickness' => top, 'kick' => base },
                    'ep' => { 'left' => ep['left'], 'right' => ep['right'], 'top' => ep['top'], 'thickness' => num(ep['thickness'], 20) },
                    'modules' => mods, 'flags' => flags,
                    'notes' => { 'handle' => handle_note(spec) })
        end

        def handle_note(spec)
          types = (spec['modules'] || []).map { |m| m['handle_type'] }.compact.uniq - ['none']
          return '(확인필요)' if types.empty?
          names = { 'channel' => '목찬넬', 'push_open' => 'PUSH', 'bar' => '바 손잡이', 'knob' => '노브', 'cup_pull' => '컵 손잡이' }
          types.map { |t| names[t] || t }.join(' / ') + ' (확인필요)'
        end

        def module_from(m, i, x, z, w, h, d)
          out = { 'name' => (m['label'] || "M#{i + 1}").to_s, 'x' => x, 'z' => z, 'w' => w, 'h' => h, 'd' => d,
                  'type' => 'open', 'doors' => 0, 'drawers' => 0, 'shelves' => [], 'rods' => [], 'flags' => [] }
          case m['kind']
          when 'shelf_module'
            out['doors'] = { 'single' => 1, 'pair' => 2 }.fetch(m['door_config'].to_s, 0)
            out['type'] = out['doors'] > 0 ? 'doors' : 'open'
            out['shelves'] = (m['shelves'] || []).map { |s| num(s['height_from_bottom']) }
            out['rods'] = (m['accessories'] || []).select { |a| a['kind'] == 'hanging_rod' }.map { |a| num(a['height_from_bottom']) }
            out['dividers'] = (m['vertical_dividers'] || []).map { |v| num(v['x']) }
          when 'drawer_module'
            out['drawers'] = [m['drawer_count'].to_i, 1].max
            out['type'] = 'drawers'
          when 'desk_module'
            out['type'] = 'desk'
            out['w'] = num(m['width'], w); out['d'] = num(m['depth'], d); out['h'] = num(m['height'], h)
          else
            out['name'] = (m['label'] || '공간').to_s
          end
          out
        end

        # 누락 키를 채운 완전한 모델
        def normalize(src)
          s = deep_stringify(src)
          o = s['overall'] || {}
          out = {
            'site' => s['site'] || '', 'furniture_name' => (s['furniture_name'] || 'Furniture').to_s,
            'overall' => { 'W' => num(o['W'], 900), 'H' => num(o['H'], 900), 'D' => num(o['D'], 600),
                           'top_thickness' => num(o['top_thickness'], 0), 'kick' => num(o['kick'], 0) },
            'ep' => { 'left' => !!(s['ep'] || {})['left'], 'right' => !!(s['ep'] || {})['right'],
                      'top' => !!(s['ep'] || {})['top'], 'thickness' => num((s['ep'] || {})['thickness'], 20) },
            'modules' => (s['modules'] || []).map { |m| module_defaults(m, o) },
            'type' => (s['type'] || '가구').to_s, 'channel' => !!s['channel'],
            'sink' => s['sink'].is_a?(Hash) ? %w[x y w d].each_with_object({}) { |k, h| h[k] = num(s['sink'][k]) } : nil,
            'cuts' => cuts_from(s),
            'table_rows' => (s['table_rows'] || []).select { |r| r.is_a?(Array) && r.size >= 3 },
            'notes' => DEFAULT_NOTES.merge((s['notes'] || {}).select { |_k, v| v.to_s != '' }),
            'room' => { 'W' => num((s['room'] || {})['W'], 5200), 'D' => num((s['room'] || {})['D'], 3400),
                        'name' => ((s['room'] || {})['name'] || '공간').to_s },
            'flags' => (s['flags'] || [])
          }
          out['modules'] = [module_defaults({ 'name' => 'M1', 'w' => out['overall']['W'], 'h' => out['overall']['H'] }, o)] if out['modules'].empty?
          out
        end

        # 절단 위치 목록(최대 2). 지정이 없으면 빈 배열(= 페이지 쪽에서 가운데 모듈로 자동)
        def cuts_from(s)
          list = s['cuts'].is_a?(Array) ? s['cuts'] : (s['cut_x'].nil? ? [] : [s['cut_x']])
          list.map { |v| num(v, nil) }.compact.first(2)
        end

        def module_defaults(m, o)
          {
            'name' => (m['name'] || 'M').to_s, 'label' => (m['label'] || m['name'] || 'M').to_s, 'x' => num(m['x']), 'z' => num(m['z']),
            'w' => num(m['w'], num(o['W'], 900)), 'h' => num(m['h'], num(o['H'], 900)), 'd' => num(m['d'], num(o['D'], 600)),
            'type' => (m['type'] || 'open').to_s, 'doors' => m['doors'].to_i, 'drawers' => m['drawers'].to_i,
            'shelves' => (m['shelves'] || []).map { |v| num(v) }, 'rods' => (m['rods'] || []).map { |v| num(v) },
            'dividers' => (m['dividers'] || []).map { |v| num(v) }, 'flags' => (m['flags'] || [])
          }
        end

        def deep_stringify(o)
          case o
          when Hash then o.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
          when Array then o.map { |v| deep_stringify(v) }
          when String then Text.utf8(o)
          else o
          end
        end

        # 시트 모델의 W×H×D 요약 문자열
        def summary(m)
          o = m['overall']
          "#{Sheet.fmt(o['W'])}x#{Sheet.fmt(o['H'])}x#{Sheet.fmt(o['D'])}"
        end

        # 일반 가구에서 자동 선택하는 축척 분모 (한 시트 내 모든 뷰 동일)
        def pick_scale(m, max_w: 140.0, max_h: 92.0, max_d: 44.0)
          o = m['overall']
          [20, 25, 30, 40, 50, 60, 80, 100].find do |den|
            o['W'] / den <= max_w && o['H'] / den <= max_h && o['D'] / den <= max_d
          end || 100
        end
      end
    end
  end
end
