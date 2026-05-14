module Kabinet
  module Commands
    module Generate
      module_function

      # Build a fresh assembly at world origin from a normalized spec hash (mm units).
      # Returns the root assembly group.
      def run_assembly(spec, model: Sketchup.active_model)
        spec = Kabinet::Persistence::Schema.normalize(spec)
        Kabinet::Persistence::Schema.validate!(spec)
        root = nil
        model.start_operation('Kabinet — 어셈블리 생성', true)
        begin
          asm = Kabinet::Core::Assembly.from_hash(spec)
          root = asm.build(model.entities, Kabinet::Geometry::Transforms::IDENTITY,
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
        observer = Kabinet::Commands::ScaleAutoRegenObserver.new
        root.add_observer(observer)
      rescue StandardError
        # observer is best-effort; never break generation if it fails
      end
    end
  end
end
