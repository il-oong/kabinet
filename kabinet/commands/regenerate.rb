module Kabinet
  module Commands
    module Regenerate
      module_function

      # Read the spec from the selected (or passed-in) assembly group, apply the updated spec,
      # rebuild in-place, and stamp the new spec back.
      def run(updated_spec = nil, group: nil, model: Sketchup.active_model)
        target = group || Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
        unless target
          ::UI.messagebox('Kabinet: 선택된 어셈블리 그룹을 찾을 수 없습니다.\n캐비닛 그룹을 선택한 뒤 다시 시도하세요.')
          return nil
        end

        existing_spec = Kabinet::Persistence::Attributes.read_assembly_spec(target)
        unless existing_spec
          ::UI.messagebox('Kabinet: 선택된 그룹에 Kabinet 파라미터가 없습니다.\n이 플러그인으로 생성한 어셈블리만 재생성할 수 있습니다.')
          return nil
        end

        # Merge updated_spec on top of existing (so caller only needs to send changed keys)
        spec = if updated_spec
                 Kabinet::Persistence::Schema.normalize(deep_merge(existing_spec, updated_spec))
               else
                 Kabinet::Persistence::Schema.normalize(existing_spec)
               end

        Kabinet::Persistence::Schema.validate!(spec)

        model.start_operation('Kabinet — 재생성', true)
        begin
          asm = Kabinet::Core::Assembly.from_hash(spec)
          asm.build_into(target, spec_for_persistence: spec)
          Kabinet::Commands::Generate.install_observer(target)
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          ::UI.messagebox("Kabinet 재생성 오류:\n#{e.message}")
          raise
        end

        model.selection.clear
        model.selection.add(target)
        target
      end

      # module_function 블록 안에 있어야 run에서 호출 가능
      def deep_merge(base, override)
        return override unless base.is_a?(Hash) && override.is_a?(Hash)
        base.merge(override) { |_k, old, new_v| deep_merge(old, new_v) }
      end
    end

    # SketchUp EntityObserver that intercepts scale-tool transforms on an assembly group,
    # reads the new bounding-box scale factors, updates only the dimensional spec keys
    # (width / depth / height / run_height / base_height — NOT thicknesses), then
    # rebuilds the assembly in-place so panel thicknesses are always preserved.
    class ScaleAutoRegenObserver < Sketchup::EntityObserver
      SCALE_TOL = 0.002  # ignore sub-0.2% floating-point drift
      MIN_MM    = 50     # floor for any single dimension

      def initialize
        @busy     = false
        @timer_id = nil
        @last_sx  = 1.0
        @last_sy  = 1.0
        @last_sz  = 1.0
        @entity_ref = nil
      end

      def onTransformationChange(entity)
        return if @busy

        t  = entity.transformation
        sx = t.xaxis.length.to_f   # SU returns inches-per-inch, so unitless scale factor
        sy = t.yaxis.length.to_f
        sz = t.zaxis.length.to_f

        # Ignore pure translation / rotation (scale stays 1.0)
        return if (sx - 1.0).abs < SCALE_TOL &&
                  (sy - 1.0).abs < SCALE_TOL &&
                  (sz - 1.0).abs < SCALE_TOL

        @last_sx    = sx
        @last_sy    = sy
        @last_sz    = sz
        @entity_ref = entity

        # Debounce: cancel any pending timer and restart. The 50 ms gap lets
        # SketchUp finish its own scale commit before we start_operation.
        ::UI.stop_timer(@timer_id) if @timer_id
        @timer_id = ::UI.start_timer(0.05, false) { _do_regen }
      rescue StandardError
        # Observer must never crash SketchUp
      end

      private

      def _do_regen
        @timer_id = nil
        return unless @entity_ref&.valid? && !@busy

        spec = Kabinet::Persistence::Attributes.read_assembly_spec(@entity_ref)
        return unless spec

        @busy = true
        begin
          _apply_scale_and_rebuild(@entity_ref, spec, @last_sx, @last_sy, @last_sz)
        rescue => e
          puts "Kabinet ScaleObserver 오류: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        ensure
          @busy = false
        end
      end

      def _apply_scale_and_rebuild(entity, spec, sx, sy, sz)
        model = entity.model

        if spec['run_mode']
          # Run mode: X scales each module width proportionally, Y scales depth, Z scales heights.
          spec['max_depth']   = _clamp((spec['max_depth'].to_f  * sy).round)
          spec['run_height']  = _clamp((spec['run_height'].to_f * sz).round)
          spec['base_height'] = [(spec['base_height'].to_f * sz).round, 0].max
          spec['modules'].each do |m|
            m['width'] = _clamp((m['width'].to_f * sx).round)
            m['depth'] = _clamp((m['depth'].to_f * sy).round) if m.key?('depth')
          end
        else
          # Stack mode: X→overall width (applied to all modules), Y→depth, Z→each module height.
          new_w = _clamp((spec['width'].to_f * sx).round)
          spec['width']       = new_w
          spec['max_depth']   = _clamp((spec['max_depth'].to_f  * sy).round)
          spec['base_height'] = [(spec['base_height'].to_f * sz).round, 0].max
          spec['modules'].each do |m|
            m['width'] = new_w
            m['depth'] = _clamp((m['depth'].to_f  * sy).round) if m.key?('depth')
            m['height']= _clamp((m['height'].to_f * sz).round) if m.key?('height')
          end
        end

        # Strip scale from the transformation while keeping origin + rotation.
        t = entity.transformation
        clean_t = ::Geom::Transformation.axes(
          t.origin,
          t.xaxis.normalize,
          t.yaxis.normalize,
          t.zaxis.normalize
        )

        norm = Kabinet::Persistence::Schema.normalize(spec)
        Kabinet::Persistence::Schema.validate!(norm)

        model.start_operation('Kabinet — 스케일 재생성', true)
        begin
          entity.transformation = clean_t
          asm = Kabinet::Core::Assembly.from_hash(norm)
          asm.build_into(entity, spec_for_persistence: norm)
          model.commit_operation
        rescue => e
          model.abort_operation
          raise
        end

        # Sync the HtmlDialog form if it's open.
        dlg = Kabinet::UI::Dialog.instance_variable_get(:@dialog)
        if dlg&.visible?
          payload = ::JSON.generate({ spec: norm, entityID: entity.entityID.to_s })
          dlg.execute_script("kabinet.loadSpec(#{payload})")
          dlg.execute_script("kabinet.onSuccess('✓ 스케일 재생성 완료 — 판재 두께 유지')")
        end
      end

      # Round and apply minimum-dimension floor.
      def _clamp(v)
        [v.to_i, MIN_MM].max
      end
    end
  end
end
