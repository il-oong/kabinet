module Kabinet
  module Commands
    module Generate
      module_function

      # Build a fresh assembly from a spec hash (mm units).
      # transform/entities: 배치 위치(PlaceTool). 생략하면 월드 원점.
      # Returns the root assembly group.
      def run_assembly(spec, model: Sketchup.active_model,
                       transform: Kabinet::Geometry::Transforms::IDENTITY, entities: nil)
        spec = Kabinet::Persistence::Schema.normalize(spec)
        Kabinet::Persistence::Schema.validate!(spec)
        root = nil
        model.start_operation('Kabinet — 어셈블리 생성', true)
        begin
          asm = Kabinet::Core::Assembly.from_hash(spec)
          root = asm.build(entities || model.entities, transform,
                           spec_for_persistence: spec)
          install_observer(root)
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          raise
        end
        model.selection.clear
        model.selection.add(root) if root
        root
      end

      # Convenience for Phase-1-style single carcase from raw mm dimensions.
      def run_carcase(width:, depth:, height:,
                      thickness: Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM,
                      back_thickness: Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM,
                      door_config: 'none',
                      model: Sketchup.active_model)
        spec = {
          'version'   => Kabinet::Persistence::Schema::CURRENT_VERSION,
          'name'      => 'Carcase',
          'width'     => width,
          'max_depth' => depth,
          'ep'        => { 'left' => false, 'right' => false, 'thickness' => 0 },
          'top_panel' => nil,
          'modules'   => [
            { 'kind' => 'shelf_module', 'width' => width, 'depth' => depth, 'height' => height,
              'body_thickness' => thickness, 'back_thickness' => back_thickness,
              'door_config' => door_config }
          ]
        }
        run_assembly(spec, model: model)
      end

      def install_observer(root)
        return unless defined?(Kabinet::Commands::ScaleAutoRegenObserver)
        key = [root.model.guid, root.entityID]
        # 재생성/재선택 때마다 달았다간 스케일이 중복 적용되므로 그룹당 하나만
        @observed ||= {}
        return if @observed[key]
        root.add_observer(Kabinet::Commands::ScaleAutoRegenObserver.new)
        @observed[key] = true
      rescue StandardError
        # observer is best-effort; never break generation if it fails
      end
    end
  end
end
