module Kabinet
  module UI
    module Dialog
      WEB_DIR = File.join(File.dirname(__FILE__), 'web').freeze

      module_function

      # 창이 이미 떠 있으면 앞으로 가져오고, 없으면 새로 연다.
      # 실패하면 조용히 넘어가지 않고 원인을 메시지로 보여준다.
      def show
        d = get_or_create_dialog
        if d.visible?
          d.bring_to_front
        else
          d.show
        end
      rescue StandardError => e
        @dialog = nil
        ::UI.messagebox("Kabinet 창을 열지 못했습니다:\n#{e.message}\n\n" \
                        '메뉴 > Kabinet > 플러그인 다시 로드 후 다시 시도하세요.')
      end

      def close_if_open
        @dialog.close if @dialog&.visible?
      rescue StandardError
        nil
      end

      def show_with_selection
        model = Sketchup.active_model
        grp   = Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
        @pending_selection = grp
        show
        push_pending_selection if @ready
      end

      def get_or_create_dialog
        @dialog = nil unless @dialog&.visible?
        @dialog ||= create_dialog
        @dialog
      end

      def create_dialog
        @dialog_model = Sketchup.active_model
        opts = {
          dialog_title:    'Kabinet — 카케이스 생성기',
          preferences_key: 'kabinet_dialog_v2',   # 2단 레이아웃: 이전 창 크기(500px) 무시
          width:           720,
          height:          740,
          resizable:       true
        }
        d = ::UI::HtmlDialog.new(opts)
        d.set_file(File.join(WEB_DIR, 'index.html'))
        @ready = false
        register_callbacks(d)
        d.set_on_closed { stop_preview; @ready = false }
        d
      end

      def register_callbacks(d)
        register_drawing_callbacks(d)
        d.add_action_callback('kabinet:ready') do |_ctx, _params|
          @ready = true
          push_pending_selection
        end

        d.add_action_callback('kabinet:preview') do |_ctx, json_str|
          begin
            payload = JSON.parse(json_str)
            model = Sketchup.active_model
            ensure_dialog_model!
            id = payload['entityID'].to_s
            target = id.empty? ? nil : find_entity_by_id(model, id)
            raise '수정할 가구를 찾을 수 없습니다. 선택 불러오기를 다시 실행하세요.' if !id.empty? && !target
            stop_preview if @preview && @preview.model != model
            unless @preview
              preview = LivePreview.new(model) do
                if @preview.equal?(preview)
                  @preview = nil
                  d.execute_script('kabinetLivePreview.onStopped()') if d.visible?
                end
              end
              @preview = preview
            end
            @preview.update(payload['spec'], target: target, internal: payload['internal'] == true,
                            selected_module: payload['selectedModule'])
            d.execute_script("kabinetLivePreview.onResult(#{JSON.generate({ revision: payload['revision'], ok: true })})")
          rescue StandardError => e
            stop_preview
            result = { revision: payload && payload['revision'], ok: false, message: e.message }
            d.execute_script("kabinetLivePreview.onResult(#{JSON.generate(result)})")
          end
        end
        d.add_action_callback('kabinet:preview_stop') { |_ctx, _params| stop_preview }
        d.add_action_callback('kabinet:preview_view') { |_ctx, name| @preview&.set_view(name.to_s) }

        # ── Generate: 배치 도구 → 클릭한 자리에 새 가구 ─────────────────
        d.add_action_callback('kabinet:generate') do |_ctx, json_str|
          begin
            stop_preview
            ensure_dialog_model!
            spec = JSON.parse(json_str)
            tool = Kabinet::UI::PlaceTool.new(spec) do |grp|
              if grp
                norm  = Kabinet::Persistence::Schema.normalize(spec)
                warns = Kabinet::Core::Validation.warnings(norm)
                msg   = warns.empty? ? '가구가 생성되었습니다.' : "가구 생성 완료 — 경고 #{warns.size}건:\n" + warns.join("\n")
                d.execute_script("kabinet.onSuccess(#{JSON.generate(msg)})")
                send_applied(d, grp)
              else
                d.execute_script("kabinet.onError('가구 배치를 취소했습니다.')")
              end
            end
            Sketchup.active_model.select_tool(tool)
            d.execute_script("kabinet.onSuccess('모델에서 가구를 놓을 곳을 클릭하세요 (벽을 가리키면 벽에 붙음 · Tab 회전 · Enter 원점 · Esc 취소)')")
          rescue Kabinet::Persistence::Schema::ValidationError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── Regenerate (update existing assembly group) ────────────────
        d.add_action_callback('kabinet:regenerate') do |_ctx, json_str|
          begin
            stop_preview
            ensure_dialog_model!
            payload = JSON.parse(json_str)
            spec    = payload['spec']
            entity_id = payload['entityID']
            model   = Sketchup.active_model
            grp     = entity_id ? find_entity_by_id(model, entity_id) : nil
            raise '수정할 가구를 찾을 수 없습니다. 선택 불러오기를 다시 실행하세요.' unless grp
            raise 'Kabinet 가구 그룹을 선택하세요.' unless grp.is_a?(Sketchup::Group) && Kabinet::Persistence::Attributes.assembly?(grp)
            raise '잠긴 가구는 수정할 수 없습니다.' if grp.locked?
            result  = Kabinet::Commands::Regenerate.run(spec, group: grp)
            if result
              d.execute_script("kabinet.onSuccess('재생성 완료.')")
              send_applied(d, result)
            else
              d.execute_script("kabinet.onError('가구를 수정하지 못했습니다. 선택 불러오기를 다시 실행하세요.')")
            end
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── Load selection → JS ────────────────────────────────────────
        d.add_action_callback('kabinet:load_selection') do |_ctx, _params|
          stop_preview
          model = Sketchup.active_model
          grp   = Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
          if grp
            spec = Kabinet::Persistence::Attributes.read_assembly_spec(grp)
            if spec
              @dialog_model = model
              entity_id = grp.entityID.to_s
              payload = JSON.generate({ spec: spec, entityID: entity_id })
              d.execute_script("kabinet.loadSpec(#{payload})")
            else
              d.execute_script("kabinet.onError('선택된 그룹에 Kabinet 데이터가 없습니다.')")
            end
          else
            d.execute_script("kabinet.onError('Kabinet 어셈블리를 선택하세요.')")
          end
        end

        # ── 창에서 모델링 도구 실행 (면 → 패널, 공간 분할) ─────────────
        d.add_action_callback('kabinet:tool') do |_ctx, json_str|
          begin
            opts = JSON.parse(json_str.to_s) rescue {}
            model = Sketchup.active_model
            case opts['name']
            when 'face_panel'
              t = opts['thickness'].to_f
              model.select_tool(Kabinet::UI::FacePanelTool.new(t >= 3 && t <= 100 ? t : nil))
              d.execute_script("kabinet.onSuccess('면 → 패널 도구 실행: 모델에서 면을 클릭하세요 (우클릭: 두께, Esc: 종료)')")
            when 'space_divide'
              model.select_tool(Kabinet::UI::SpaceDivideTool.new)
              d.execute_script("kabinet.onSuccess('공간 분할 도구 실행: 캐비닛 안쪽을 클릭하세요 (Esc: 종료)')")
            when 'regenerate'
              Kabinet::Commands::Regenerate.run
            else
              d.execute_script("kabinet.onError('알 수 없는 도구입니다.')")
            end
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── 설정: GitHub 업데이트 / 플러그인 다시 로드 ────────────────
        d.add_action_callback('kabinet:admin') do |_ctx, name|
          case name.to_s
          when 'update'
            Kabinet::Updater.run do |msg|
              d.execute_script("kabinet.onSuccess(#{JSON.generate(msg)})") if d.visible?
            end
          when 'reload'
            Kabinet::Updater.reload_with_message
          end
        end

        # ── 선택 그룹/컴포넌트 → 재단 목록 CSV (직접 모델링한 가구용) ───
        # 하위 그룹을 끝까지 내려가 판재(하위 그룹 없는 그룹)마다 두께×폭×길이를 잰다.
        d.add_action_callback('kabinet:export_group_cutlist') do |_ctx, _params|
          begin
            model   = Sketchup.active_model
            targets = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
            if targets.empty?
              d.execute_script("kabinet.onError('그룹 또는 컴포넌트를 먼저 선택하세요.')")
              next
            end
            rows = Kabinet::UI::Dialog.group_cut_rows(targets)
            raise '선택에 판재(면이 있는 그룹)가 없습니다.' if rows.empty?

            first = targets.first
            gname = first.name.to_s
            gname = first.definition.name.to_s if gname.empty? && first.respond_to?(:definition)
            gname = '선택가구' if gname.empty?
            safe  = gname.gsub(/[\\\/\:\*\?\"\<\>\|]/, '_')
            ts    = Time.now.strftime('%Y%m%d_%H%M%S')
            path  = ::UI.savepanel('재단 목록 CSV 저장', Dir.home, "#{safe}_재단목록_#{ts}.csv")
            if path
              path += '.csv' unless path.downcase.end_with?('.csv')
              csv = "\uFEFF부재명,두께(mm),폭(mm),길이(mm),수량\n" +
                    rows.map { |r| [r[:name], r[:t], r[:w], r[:l], r[:qty]].join(',') }.join("\n") + "\n"
              File.open(path, 'wb') { |f| f.write(csv.encode('UTF-8')) }
              total = rows.sum { |r| r[:qty] }
              d.execute_script("kabinet.onSuccess(#{JSON.generate("재단 목록 저장 완료: #{File.basename(path)} (부재 #{total}개)")})")
            end
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── Export drawings ────────────────────────────────────────────
        d.add_action_callback('kabinet:export_drawings') do |_ctx, json_str|
          begin
            stop_preview
            d.execute_script('kabinetLivePreview.onStopped()')
            ensure_dialog_model!
            payload   = JSON.parse(json_str)
            views     = (payload['views'] || %w[front right top section]).map(&:to_sym)
            entity_id = payload['entityID'].to_s.strip
            model     = Sketchup.active_model

            grp = if entity_id.length > 0
                    find_entity_by_id(model, entity_id)
                  end
            # 폴백 1: 현재 선택
            grp ||= Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
            # 폴백 2: 모델 안 Kabinet 어셈블리 중 가장 마지막 것
            grp ||= Kabinet::Persistence::Attributes.find_all_assemblies(model).last

            if grp
              model.selection.clear
              model.selection.add(grp)
              Kabinet::Commands::Export.run(views: views)
            else
              d.execute_script("kabinet.onError('모델에 Kabinet 어셈블리가 없습니다. 먼저 생성하세요.')")
            end
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── Preset management ──────────────────────────────────────────
        d.add_action_callback('kabinet:list_presets') do |_ctx, _params|
          presets = load_presets
          d.execute_script("kabinet.loadPresets(#{JSON.generate(presets)})")
        end

        d.add_action_callback('kabinet:save_preset') do |_ctx, json_str|
          begin
            payload = JSON.parse(json_str)
            save_preset(payload['name'], payload['spec'])
            pname = payload['name']
            d.execute_script("kabinet.onSuccess('프리셋 저장 완료: #{pname}')")
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        d.add_action_callback('kabinet:delete_preset') do |_ctx, name|
          delete_preset(name)
          presets = load_presets
          d.execute_script("kabinet.loadPresets(#{JSON.generate(presets)})")
        end

        # ── 발주도면 DXF export ────────────────────────────────────────
        # 현재 폼 스펙에서 직접 생성 — 모델 선택 불필요 (순수 계산).
        d.add_action_callback('kabinet:export_dxf') do |_ctx, json_str|
          begin
            spec = JSON.parse(json_str)
            norm = Kabinet::Persistence::Schema.normalize(spec)
            Kabinet::Persistence::Schema.validate!(norm)

            aname = norm['name'] || 'kabinet'
            ts    = Time.now.strftime('%Y%m%d_%H%M%S')
            safe  = aname.gsub(/[\\\/\:\*\?\"\<\>\|]/, '_')
            path  = ::UI.savepanel('발주도면 DXF 저장', Dir.home, "#{safe}_발주도면_#{ts}.dxf")
            if path
              path += '.dxf' unless path.downcase.end_with?('.dxf')
              Kabinet::Output::OrderSheet.generate(norm, path)
              d.execute_script("kabinet.onSuccess('발주도면 저장 완료: #{File.basename(path)}')")
            end
          rescue Kabinet::Persistence::Schema::ValidationError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── 선택 그룹/컴포넌트 → 발주도면 DXF (직접 모델링한 가구용) ────
        # 엣지 직교투영 3면도. 옵션(JSON): views / dim_overall / dim_units /
        # include_soft(곡면 엣지 포함) / hlr(은선 제거 레이캐스트)
        d.add_action_callback('kabinet:export_group_dxf') do |_ctx, json_str|
          begin
            opts = begin
                     JSON.parse(json_str.to_s)
                   rescue StandardError
                     {}
                   end
            want_views   = Array(opts['views']).select { |v| %w[front side top].include?(v) }
            want_views   = %w[front side top] if want_views.empty?
            dim_overall  = opts.fetch('dim_overall', true) ? true : false
            dim_units    = opts.fetch('dim_units', true) ? true : false
            include_soft = opts['include_soft'] ? true : false
            hlr          = opts.fetch('hlr', true) ? true : false
            round_mm     = opts['round_mm'].to_f
            round_mm     = 1.0 if round_mm <= 0
            eq           = opts.fetch('eq', true) ? true : false
            # 세부 치수 간소화: 전체 대비 이 비율 미만 유닛 치수 생략
            min_frac     = opts.fetch('simplify_dims', true) ? 0.1 : 0.0
            # 복잡 메시(하드 삼각분할 임포트 모델 등) 박스 대체 임계값
            mesh_box     = opts.fetch('mesh_box', true) ? true : false
            mesh_limit   = 300

            model   = Sketchup.active_model
            targets = model.selection.to_a.select { |e|
              e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            }
            if targets.empty?
              d.execute_script("kabinet.onError('그룹 또는 컴포넌트를 먼저 선택하세요.')")
            else
              gp     = Kabinet::Output::GroupProjection
              result = gp.collect_units_mm(targets, include_soft: include_soft)
              units  = result[:units]

              # 유닛별 세그먼트 조립:
              #   - 엣지가 임계값을 넘는 유닛(임포트 메시 소파/매트리스 등)이나
              #     곡면 필터로 다 사라진 유닛 → 바운딩 박스 외곽으로 대체
              segs = result[:loose].dup
              units.each do |u|
                replace = u[:segs].empty? || (mesh_box && u[:segs].size > mesh_limit)
                segs.concat(replace ? gp.bbox_segments(u[:min], u[:max]) : u[:segs])
              end
              raise '선택에 그릴 엣지가 없습니다' if segs.empty?

              # 은선 제거: 뷰별 레이캐스트로 가려진 엣지 스킵
              view_segs = nil
              if hlr
                view_segs = {}
                want_views.each { |vn| view_segs[vn] = gp.visible_segments(model, segs, vn) }
              end

              views = gp.views_from_segments(segs, units: units, view_segs: view_segs,
                                             dim_overall: dim_overall, dim_units: dim_units,
                                             round_mm: round_mm, eq: eq, min_frac: min_frac)
              views = views.select { |v| want_views.include?(v[:name]) }

              first = targets.first
              gname = first.name.to_s
              gname = first.definition.name.to_s if gname.empty? && first.respond_to?(:definition)
              gname = '선택가구' if gname.empty?

              ts   = Time.now.strftime('%Y%m%d_%H%M%S')
              safe = gname.gsub(/[\\\/\:\*\?\"\<\>\|]/, '_')
              path = ::UI.savepanel('발주도면 DXF 저장', Dir.home, "#{safe}_발주도면_#{ts}.dxf")
              if path
                path += '.dxf' unless path.downcase.end_with?('.dxf')
                dxf = Kabinet::Output::OrderSheet.compose(
                  views,
                  name:     gname,
                  size:     Kabinet::Output::GroupProjection.size_string(segs),
                  material: '-',
                  notes:    ['모든 치수 단위: mm. 도면 1:1 작도 (인쇄 축척 별도 지정)',
                             hlr ? '선택 모델 직교투영 (은선 제거 — 보이는 외곽선만)' :
                                   '선택 모델 직교투영 (전체 엣지 표시 — 내부 구조 포함)'])
                dxf.write(path)
                d.execute_script("kabinet.onSuccess('발주도면 저장 완료: #{File.basename(path)}')")
              end
            end
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── Cut list CSV export ────────────────────────────────────────
        d.add_action_callback('kabinet:export_cutlist') do |_ctx, json_str|
          begin
            spec = JSON.parse(json_str)
            norm = Kabinet::Persistence::Schema.normalize(spec)
            Kabinet::Persistence::Schema.validate!(norm)
            result = Kabinet::Core::CutList.generate_full(norm)
            csv    = Kabinet::Core::CutList.full_csv(result)

            aname = norm['name'] || 'kabinet'
            ts    = Time.now.strftime('%Y%m%d_%H%M%S')
            safe  = aname.gsub(/[\\\/\:\*\?\"\<\>\|]/, '_')
            default_name = "#{safe}_커트리스트_#{ts}.csv"

            path = ::UI.savepanel('커트리스트 CSV 저장', Dir.home, default_name)
            if path
              path += '.csv' unless path.end_with?('.csv')
              File.open(path, 'wb') { |f| f.write(csv.encode('UTF-8')) }
              d.execute_script("kabinet.onSuccess('커트리스트 저장 완료: #{File.basename(path)}')")
            end
          rescue Kabinet::Persistence::Schema::ValidationError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end
      end

      def stop_preview
        preview = @preview
        @preview = nil
        preview&.stop
      end

      def ensure_dialog_model!
        return if @dialog_model == Sketchup.active_model
        raise '다른 SketchUp 모델로 전환되었습니다. 창을 다시 열거나 선택 불러오기를 실행하세요.'
      end

      def send_applied(d, group)
        payload = { spec: Kabinet::Persistence::Attributes.read_assembly_spec(group), entityID: group.entityID.to_s }
        d.execute_script("kabinet.onApplied(#{JSON.generate(payload)})")
      end

      def push_pending_selection
        grp = @pending_selection
        @pending_selection = nil
        return unless grp && grp.valid?
        @dialog_model = Sketchup.active_model
        payload = { spec: Kabinet::Persistence::Attributes.read_assembly_spec(grp), entityID: grp.entityID.to_s }
        @dialog.execute_script("kabinet.loadSpec(#{JSON.generate(payload)})")
      end

      # ── Preset persistence via Sketchup.read/write_default ──────────
      # 판재 수집: 하위 그룹/컴포넌트가 없는 그룹 = 판재 1장.
      # 치수는 누적 변환을 적용한 로컬 바운딩박스 세 변 → 작은 순서로 두께/폭/길이.
      def group_cut_rows(targets)
        parts = []
        walk = lambda do |inst, tr|
          tr_all = tr * inst.transformation
          ents = inst.definition.entities
          kids = ents.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          if kids.empty?
            next unless ents.any? { |e| e.is_a?(Sketchup::Face) }
            bb = inst.definition.bounds
            c0 = bb.corner(0).transform(tr_all)
            dims = [1, 2, 4].map { |k| (c0.distance(bb.corner(k).transform(tr_all))).to_mm.round(1) }.sort
            label = inst.name.to_s
            label = inst.definition.name.to_s if label.empty? && inst.is_a?(Sketchup::ComponentInstance)
            label = '판재' if label.empty?
            parts << { name: label.tr(',', ' '), t: dims[0], w: dims[1], l: dims[2] }
          else
            kids.each { |k| walk.call(k, tr_all) }
          end
        end
        targets.each { |t| walk.call(t, Geom::Transformation.new) }
        fmt = ->(v) { v.to_s.sub(/\.0\z/, '') }
        parts.group_by { |p| [p[:name], p[:t], p[:w], p[:l]] }
             .map { |(n, t, w, l), list| { name: n, t: fmt.(t), w: fmt.(w), l: fmt.(l), qty: list.size } }
             .sort_by { |r| [-r[:t].to_f, -r[:l].to_f, -r[:w].to_f] }
      end

      # ── LayOut 도면 · 내 가구 보관함 · EP 판재 (Kabinet 2.0 기능을 이 창에 통합) ──
      def register_drawing_callbacks(d)
        # 주방 상판: 선택한 하부장들 인식 → 상판 생성
        d.add_action_callback('kabinet:countertop') do |_ctx, raw|
          begin
            stop_preview
            msg = Kabinet::Commands::Countertop.run(JSON.parse(raw))
            d.execute_script("kabinet.onSuccess(#{JSON.generate(msg)})")
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end
        d.add_action_callback('kabinet:countertop_materials') do |_ctx|
          names = Kabinet::Commands::Countertop.material_names rescue []
          d.execute_script("kabinet.setCountertopMaterials(#{JSON.generate(names)})")
        end

        # 창 정면도 미리보기: 실제 모델을 만드는 코드로 형상을 만들어 정면(X-Z)으로 투영
        d.add_action_callback('kabinet:preview2d') do |_ctx, raw|
          rev = nil
          begin
            o = JSON.parse(raw)
            rev = o['rev']
            d.execute_script("kabinet.onPreview2d(#{JSON.generate(front_projection(o['spec']).merge(rev: rev))})")
          rescue StandardError => e
            d.execute_script("kabinet.onPreview2d(#{JSON.generate({ rev: rev, error: e.message })})")
          end
        end

        d.add_action_callback('ep_library_list') do |_ctx|
          ep_respond(d) { ep_send_library(d); nil }
        end
        d.add_action_callback('ep_library_save') do |_ctx, raw|
          ep_respond(d) do
            o = JSON.parse(raw)
            Kabinet::FurnitureLibrary.save(o.fetch('name'), folder: o.fetch('folder', '미분류'))
            ep_send_library(d)
            "‘#{o['name']}’ 보관함에 저장 완료. 왼쪽 '내 가구 보관함'에서 불러올 수 있습니다."
          end
        end
        d.add_action_callback('ep_library_update') do |_ctx, raw|
          ep_respond(d) do
            o = JSON.parse(raw)
            Kabinet::FurnitureLibrary.update(o.fetch('id'), name: o.fetch('name'), folder: o.fetch('folder'))
            ep_send_library(d)
            '가구 이름과 폴더를 변경했습니다.'
          end
        end
        d.add_action_callback('ep_library_place') do |_ctx, id|
          ep_respond(d) do
            Kabinet::FurnitureLibrary.place(id)
            '가구를 놓을 위치를 SketchUp 화면에서 클릭하세요. Esc로 취소합니다.'
          end
        end
        d.add_action_callback('ep_create') do |_ctx, raw|
          ep_respond(d) do
            Kabinet::EPBoard.place(JSON.parse(raw))
            'EP 판재를 놓을 위치를 클릭하세요 (스냅 가능 · Esc 취소).'
          end
        end
        d.add_action_callback('ep_role') do |_ctx, role|
          ep_respond(d) { "#{Kabinet::EPBoard.mark_role(role)}개 부품 구분 완료. 가구 전체를 다시 선택하고 출력하세요." }
        end
        d.add_action_callback('ep_front') do |_ctx, action|
          ep_respond(d) do
            fs = Kabinet::Output::FurnitureSheet
            case action
            when 'set' then fs.set_front
            when 'reverse' then fs.reverse_front
            when 'status' then fs.front_status
            else raise '알 수 없는 정면 설정입니다.'
            end
          end
        end
        d.add_action_callback('ep_space_role') do |_ctx, role|
          ep_respond(d) { "#{Kabinet::Output::SpaceSheet.mark(role)}개 공간 부품 지정 완료. 공간 전체를 선택하고 출력하세요." }
        end
        d.add_action_callback('ep_export') do |_ctx, raw|
          ep_respond(d) do
            stop_preview
            o = JSON.parse(raw)
            result = o['space_mode'] ? Kabinet::Output::SpaceSheet.run(o) : Kabinet::Output::FurnitureSheet.run(o)
            result ? "도면 저장 완료 (LayOut + PDF): #{result}" : '저장을 취소했습니다.'
          end
        end
      end

      # 스펙 → 정면 투영 선분 [[x1, z1, x2, z2, 앞판여부(1/0)], ...] (mm, 중복·점 선분 제거)
      def front_projection(spec)
        norm = Kabinet::Persistence::Schema.normalize(spec)
        Kabinet::Persistence::Schema.validate!(norm)
        root = Kabinet::Core::Assembly.from_hash(norm).build(Kabinet::Geometry::Preview::Entities.new)
        seen = {}
        segs = []
        root.entities.collect.each do |b|
          front = b[:front] ? 1 : 0
          b[:points].each_slice(2) do |p, q|
            next unless q
            a = [(p.x.to_f * 25.4).round(1), (p.z.to_f * 25.4).round(1)]
            c = [(q.x.to_f * 25.4).round(1), (q.z.to_f * 25.4).round(1)]
            next if a == c
            key = [a, c].sort.flatten
            prev = seen[key]
            next if prev && prev >= front
            seen[key] = front
            segs << [*a, *c, front]
          end
        end
        xs = segs.flat_map { |s| [s[0], s[2]] }
        zs = segs.flat_map { |s| [s[1], s[3]] }
        { segs: segs, min: [xs.min || 0, zs.min || 0], max: [xs.max || 0, zs.max || 0] }
      end

      def ep_send_library(d)
        d.execute_script("epLibrary(#{JSON.generate(Kabinet::FurnitureLibrary.list)})")
      end

      def ep_respond(d)
        message = yield
        d.execute_script("epResult(#{JSON.generate(message.to_s)}, false)") if message
      rescue StandardError => e
        puts "Kabinet: #{e.full_message}"
        d.execute_script("epResult(#{JSON.generate(e.message)}, true)")
      end

      def load_presets
        raw = Sketchup.read_default('kabinet', 'presets', '{}')
        JSON.parse(raw)
      rescue StandardError
        {}
      end

      def save_preset(name, spec)
        presets = load_presets
        presets[name] = spec
        Sketchup.write_default('kabinet', 'presets', JSON.generate(presets))
      end

      def delete_preset(name)
        presets = load_presets
        presets.delete(name)
        Sketchup.write_default('kabinet', 'presets', JSON.generate(presets))
      end

      def find_entity_by_id(model, entity_id)
        id = entity_id.to_i
        model.entities.find { |e|
          (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
            e.entityID == id
        }
      end
    end
  end
end
