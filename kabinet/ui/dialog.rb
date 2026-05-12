module Kabinet
  module UI
    module Dialog
      WEB_DIR = File.join(File.dirname(__FILE__), 'web').freeze

      module_function

      def show
        d = get_or_create_dialog
        d.show
      end

      def show_with_selection
        d = get_or_create_dialog
        d.show
        # After dialog is visible, push current selection's spec into the form
        model = Sketchup.active_model
        grp   = Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
        if grp
          spec = Kabinet::Persistence::Attributes.read_assembly_spec(grp)
          if spec
            json = JSON.generate(spec)
            safe = json.gsub("'", "\\'")
            d.execute_script("kabinet.loadSpec('#{safe}')")
          end
        end
      end

      def get_or_create_dialog
        @dialog = nil unless @dialog&.visible?
        @dialog ||= create_dialog
        @dialog
      end

      def create_dialog
        opts = {
          dialog_title:    'Kabinet — 카케이스 생성기',
          preferences_key: 'kabinet_dialog',
          width:           500,
          height:          740,
          resizable:       true
        }
        d = ::UI::HtmlDialog.new(opts)
        d.set_file(File.join(WEB_DIR, 'index.html'))
        register_callbacks(d)
        d
      end

      def register_callbacks(d)
        # ── Generate (fresh assembly at world origin) ──────────────────
        d.add_action_callback('kabinet:generate') do |_ctx, json_str|
          begin
            spec = JSON.parse(json_str)
            grp  = Kabinet::Commands::Generate.run_assembly(spec)
            if grp
              d.execute_script("kabinet.onSuccess('어셈블리가 생성되었습니다.')")
            end
          rescue Kabinet::Persistence::Schema::ValidationError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── Regenerate (update existing assembly group) ────────────────
        d.add_action_callback('kabinet:regenerate') do |_ctx, json_str|
          begin
            payload = JSON.parse(json_str)
            spec    = payload['spec']
            entity_id = payload['entityID']
            model   = Sketchup.active_model
            grp     = entity_id ? find_entity_by_id(model, entity_id) : nil
            result  = Kabinet::Commands::Regenerate.run(spec, group: grp)
            if result
              d.execute_script("kabinet.onSuccess('재생성 완료.')")
            end
          rescue StandardError => e
            d.execute_script("kabinet.onError(#{JSON.generate(e.message)})")
          end
        end

        # ── Load selection → JS ────────────────────────────────────────
        d.add_action_callback('kabinet:load_selection') do |_ctx, _params|
          model = Sketchup.active_model
          grp   = Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
          if grp
            spec = Kabinet::Persistence::Attributes.read_assembly_spec(grp)
            if spec
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

        # ── Export drawings ────────────────────────────────────────────
        d.add_action_callback('kabinet:export_drawings') do |_ctx, json_str|
          begin
            payload = JSON.parse(json_str)
            views   = (payload['views'] || %w[front right top section]).map(&:to_sym)
            entity_id = payload['entityID']
            model   = Sketchup.active_model
            grp     = entity_id ? find_entity_by_id(model, entity_id) :
                                   Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
            if grp
              model.selection.clear
              model.selection.add(grp)
              Kabinet::Commands::Export.run(views: views)
            else
              d.execute_script("kabinet.onError('어셈블리를 선택하세요.')")
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

        # ── Cut list CSV export ────────────────────────────────────────
        d.add_action_callback('kabinet:export_cutlist') do |_ctx, json_str|
          begin
            spec = JSON.parse(json_str)
            norm = Kabinet::Persistence::Schema.normalize(spec)
            Kabinet::Persistence::Schema.validate!(norm)
            rows = Kabinet::Core::CutList.generate(norm)
            csv  = Kabinet::Core::CutList.to_csv(rows)

            aname = norm['name'] || 'kabinet'
            ts    = Time.now.strftime('%Y%m%d_%H%M%S')
            safe  = aname.gsub(/[\\\/\:\*\?\"\<\>\|]/, '_')
            default_name = "#{safe}_커트리스트_#{ts}.csv"

            path = UI.savepanel('커트리스트 CSV 저장', Dir.home, default_name)
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

      # ── Preset persistence via Sketchup.read/write_default ──────────
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
