require_relative 'text'
require_relative 'dxf_reader'
require_relative 'model'
module Kabinet
  module Output
    module Sheet
      # 입력 CAD 도면(DXF: 평면·정면·측면 + 치수 엔티티 + 모듈 라벨)에서 시트 모델(Model)을 재구성한다.
      # 순수 Ruby. 치수(DIMENSION)가 가진 실측값과 모듈 라벨 문자(예: '서랍장(2단)M', '조리장(1D)L/R')를 읽는다.
      # 읽지 못한 값은 기본값을 쓰고 모델 flags 에 '확인필요' 로 남긴다 (추측을 확정처럼 쓰지 않는다).
      #
      #   r = DxfImport.from_file('주방 하부장.dxf')
      #   r[:models]  # => [Model.normalize 된 Hash, ...]  (면(A/B)이 둘이면 둘)
      #   r[:report]  # => ['읽은 값 요약', ...]
      module DxfImport
        module_function

        TOL = 4.0
        LABEL_RE = /\(\s*\d+\s*(?:D|d|단)\s*\)|(?:식기세척기|오븐|쿡탑|냉장고|세탁기|건조기)\s*장|^\s*OPEN|오픈장/
        Dim = Struct.new(:vertical, :a0, :a1, :pos, :meas)
        Chain = Struct.new(:tiles, :y) do
          def x0 = tiles.first[0]
          def x1 = tiles.last[1]
          def span = x1 - x0
        end

        def from_file(path, site: '')
          from_doc(DxfReader.read(path), name_hint: File.basename(Text.utf8(path), '.*'), site: site)
        end

        def from_doc(doc, name_hint: 'Furniture', site: '')
          report = []
          dims = dims_of(doc)
          texts = texts_of(doc)
          labels = texts.select { |t| t[:text] =~ LABEL_RE && t[:text] !~ /EP|도어/ && t[:h] < 80 }
          name = title_of(texts, name_hint)
          report << "가구명 #{name} / 치수 #{dims.size}개 / 모듈 라벨 #{labels.size}개"
          chains = chains_of(dims.reject(&:vertical))
          bands = bands_of(labels)
          sides = []
          if bands.empty?
            ch = chains.max_by { |c| [c.tiles.size > 1 ? 1 : 0, c.span] }
            ch ||= single_chain(dims)
            sides << { chain: ch, labels: [], y: ch ? ch.y : 0.0 } if ch
          else
            bands.each do |b|
              ch = best_chain(chains, b) || single_chain(dims, b[:labels])
              sides << { chain: ch, labels: b[:labels], y: b[:y] } if ch
            end
          end
          if sides.empty?
            report << '치수에서 폭 구간을 찾지 못해 기본 크기를 사용'
            return { name: name, models: [Model.normalize('furniture_name' => name, 'site' => site,
                                                          'flags' => ['도면에서 치수를 읽지 못함 - 확인필요'])], report: report }
          end
          ep_t = texts.map { |t| t[:text][/\[(\d+)\s*T\]/, 1] }.compact.map(&:to_f).max
          ep = texts.any? { |t| t[:text] =~ /EP/ }
          markers = texts.select { |t| t[:text] =~ /\A[A-D]\z/ }
          door = texts.select { |t| t[:text] =~ /도어/ }.map { |t| t[:text].gsub(/\s*\n\s*/, ' / ') }.uniq.first(2).join(' ; ')
          allx0 = sides.map { |s| s[:chain].x0 }.min
          allx1 = sides.map { |s| s[:chain].x1 }.max
          h = heights(dims, allx0, allx1, sides.map { |s| s[:y] }.max)
          models = sides.each_with_index.map do |s, i|
            ch = s[:chain]
            w = ch.span
            d = depth_for(dims, s[:y], ch) || depth_overall(dims, ch) || 600.0
            mods = ch.tiles.each_with_index.map do |(x0, x1), k|
              lab = s[:labels].find { |l| l[:x] >= x0 - TOL && l[:x] <= x1 + TOL }
              module_from(lab && lab[:text], k, x0 - ch.x0, h[:kick], x1 - x0, h[:total] - h[:kick] - h[:top], d)
            end
            tag = marker_for(markers, ch, s[:y]) || (sides.size > 1 ? (i + 1).to_s : nil)
            fname = tag ? "#{name} #{tag}면" : name
            flags = ['도면(DXF)에서 자동 재구성 - 치수·구성 확인필요']
            flags << '높이를 읽지 못해 기본값 사용' if h[:guess]
            flags << 'EP 위치는 추정(양측)' if ep
            report << format('%s: W%s D%s H%s 모듈 %d개 [%s]', fname, w.round, d.round, h[:total].round, mods.size, mods.map { |m| m['name'] }.join(' | '))
            Model.normalize(
              'furniture_name' => fname, 'site' => site,
              'overall' => { 'W' => w, 'H' => h[:total], 'D' => d, 'top_thickness' => h[:top], 'kick' => h[:kick] },
              'ep' => { 'left' => ep, 'right' => ep, 'top' => false, 'thickness' => ep_t || 20.0 },
              'modules' => mods, 'flags' => flags,
              'notes' => door.empty? ? {} : { 'DOOR' => door }
            )
          end
          { name: name, models: models, report: report }
        end

        # --- 입력 수집 -------------------------------------------------------
        def dims_of(doc)
          doc.of('DIMENSION').select { |e| [0, 1].include?(e[:dimtype].to_i) && e[:x3] && e[:x4] }.map do |e|
            dx = (e[:x3] - e[:x4]).abs
            dy = (e[:y3].to_f - e[:y4].to_f).abs
            rot = e[:rot].to_f % 180
            vertical = e[:dimtype] == 1 ? dy > dx : (rot - 90).abs < 1
            meas = e[:meas].to_f
            meas = (vertical ? dy : dx) if meas <= 0
            if vertical
              Dim.new(true, [e[:y3], e[:y4]].min, [e[:y3], e[:y4]].max, e[:x].to_f, meas)
            else
              Dim.new(false, [e[:x3], e[:x4]].min, [e[:x3], e[:x4]].max, e[:y].to_f, meas)
            end
          end
        end

        def texts_of(doc)
          doc.entities.select { |e| %w[MTEXT TEXT].include?(e[:type]) && e[:text] }.map do |e|
            { text: DxfReader.clean_mtext(e[:text]), x: e[:x].to_f, y: e[:y].to_f, h: e[:h].to_f }
          end.reject { |t| t[:text].empty? }
        end

        def title_of(texts, hint)
          big = texts.reject { |t| t[:text] =~ /도어|EP 판넬|스트로만|\A[A-D]\z/ }.max_by { |t| t[:h] }
          t = big && big[:h] >= 60 ? big[:text] : hint
          t.sub(/\s*-\s*\d+\z/, '').strip
        end

        # --- 폭 구간(타일) --------------------------------------------------
        # 같은 높이(y)에서 끝점이 이어지는 가로 치수 묶음 = 모듈 폭 분할 행
        def chains_of(hdims)
          rows = hdims.group_by { |d| (d.pos / 20.0).round }
          out = []
          rows.each_value do |row|
            cur = []
            row.sort_by(&:a0).each do |d|
              if cur.empty? || (d.a0 - cur.last.a1).abs <= TOL then cur << d
              else out << mk_chain(cur); cur = [d]
              end
            end
            out << mk_chain(cur) unless cur.empty?
          end
          out.select { |c| c.tiles.size >= 2 }
        end

        def mk_chain(ds)
          Chain.new(ds.map { |d| [d.a0, d.a1] }, ds.first.pos)
        end

        # 폭 분할 행이 없을 때: 가장 긴 가로 치수 하나를 한 구간으로 (라벨이 있으면 라벨 x 를 덮는 치수만)
        def single_chain(dims, labels = nil)
          hd = dims.reject(&:vertical)
          hd = hd.select { |d| labels.any? { |l| l[:x] >= d.a0 - TOL && l[:x] <= d.a1 + TOL } } if labels
          d = hd.max_by(&:meas)
          d && Chain.new([[d.a0, d.a1]], d.pos)
        end

        # 라벨 y 밴드 (간격 250 초과면 다른 면)
        def bands_of(labels)
          bands = []
          labels.sort_by { |l| -l[:y] }.each do |l|
            if bands.last && (bands.last[:labels].last[:y] - l[:y]) <= 250 then bands.last[:labels] << l
            else bands << { labels: [l] }
            end
          end
          bands.each { |b| b[:y] = b[:labels].sum { |l| l[:y] } / b[:labels].size }
          bands
        end

        def best_chain(chains, band)
          scored = chains.map do |c|
            hit = band[:labels].count { |l| l[:x] >= c.x0 - TOL && l[:x] <= c.x1 + TOL }
            [c, hit, (c.y - band[:y]).abs]
          end.select { |_c, hit, _| hit > 0 }
          return nil if scored.empty?
          best = scored.max_by { |_c, hit, dist| [hit, -dist] }
          best[0]
        end

        # --- 깊이·높이 --------------------------------------------------------
        def depth_for(dims, y, chain)
          vs = dims.select { |d| d.vertical && d.meas.between?(200, 1300) && d.a0 - TOL <= y && y <= d.a1 + TOL &&
                                  d.pos >= chain.x0 - 800 && d.pos <= chain.x1 + 800 }
          vs.min_by { |d| d.meas }&.meas
        end

        def depth_overall(dims, chain)
          vs = dims.select { |d| d.vertical && d.meas.between?(250, 1300) && d.pos >= chain.x0 - 800 && d.pos <= chain.x1 + 800 }
          vs.max_by(&:meas)&.meas
        end

        def heights(dims, x0, x1, plan_y)
          vs = dims.select { |d| d.vertical && d.meas.between?(500, 3000) && d.pos >= x0 - 900 && d.pos <= x1 + 900 && d.a1 < plan_y - 100 }
          hd = vs.max_by(&:meas)
          return { total: 900.0, kick: 0.0, top: 0.0, guess: true } unless hd
          kicks = dims.select { |d| d.vertical && d.meas.between?(50, 200) && (d.a0 - hd.a0).abs <= TOL && d.pos >= x0 - 900 && d.pos <= x1 + 900 }
          tops = dims.select { |d| d.vertical && d.meas <= 60 && (d.a1 - hd.a1).abs <= TOL && d.pos >= x0 - 900 && d.pos <= x1 + 900 }
          { total: hd.meas, kick: kicks.map(&:meas).max || 0.0, top: tops.map(&:meas).max || 0.0, guess: false }
        end

        def marker_for(markers, chain, y)
          cand = markers.select { |m| m[:x] >= chain.x0 - 200 && m[:x] <= chain.x1 + 200 }
          cand.min_by { |m| (m[:y] - y).abs }&.dig(:text)
        end

        # --- 모듈 --------------------------------------------------------------
        def module_from(label, k, x, z, w, h, d)
          out = { 'name' => (label || "M#{k + 1}"), 'x' => x, 'z' => z, 'w' => w, 'h' => h, 'd' => d,
                  'type' => 'open', 'doors' => 0, 'drawers' => 0, 'flags' => [] }
          if label
            if (m = label.match(/\(\s*(\d+)\s*(D|d)\s*\)/))
              out['type'] = 'doors'
              out['doors'] = [m[1].to_i, 2].min
            elsif (m = label.match(/\(\s*(\d+)\s*단\s*\)/))
              out['type'] = 'drawers'
              out['drawers'] = m[1].to_i
            end
            if label =~ /식기세척기|오븐|쿡탑|냉장고/
              out['flags'] << '가전/수납 여유 확인필요'
              out['type'] = 'open' if label =~ /식기세척기|오븐/
            end
          else
            out['flags'] << '라벨 없음(구성 확인필요)'
          end
          out
        end
      end
    end
  end
end
