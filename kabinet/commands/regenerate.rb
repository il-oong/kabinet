module Kabinet
  module Commands
    module Regenerate
      module_function

      # Read the spec from the selected (or passed-in) assembly group, apply the updated spec,
      # rebuild in-place, and stamp the new spec back.
      def run(updated_spec = nil, group: nil, model: Sketchup.active_model)
        target = group || Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
        unless target
          UI.messagebox('Kabinet: 선택된 어셈블리 그룹을 찾을 수 없습니다.\n캐비닛 그룹을 선택한 뒤 다시 시도하세요.')
          return nil
        end

        existing_spec = Kabinet::Persistence::Attributes.read_assembly_spec(target)
        unless existing_spec
          UI.messagebox('Kabinet: 선택된 그룹에 Kabinet 파라미터가 없습니다.\n이 플러그인으로 생성한 어셈블리만 재생성할 수 있습니다.')
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
          UI.messagebox("Kabinet 재생성 오류:\n#{e.message}")
          raise
        end

        model.selection.clear
        model.selection.add(target)
        target
      end

      private

      def deep_merge(base, override)
        return override unless base.is_a?(Hash) && override.is_a?(Hash)
        base.merge(override) { |_k, old, new_v| deep_merge(old, new_v) }
      end
    end

    # SketchUp EntityObserver that blocks non-uniform scale on an assembly group.
    class ScaleGuardObserver < Sketchup::EntityObserver
      def onTransformationChange(entity)
        t = entity.transformation
        sx = t.xaxis.length
        sy = t.yaxis.length
        sz = t.zaxis.length
        # Allow only pure translations + 90° rotations (axis lengths stay 1.0)
        tolerance = 0.001
        if (sx - 1.0).abs > tolerance || (sy - 1.0).abs > tolerance || (sz - 1.0).abs > tolerance
          # Roll back the scale — reset to identity rotation/scale while keeping translation
          origin = t.origin
          clean_t = Geom::Transformation.new(origin)
          entity.model.start_operation('ScaleGuard', true)
          entity.transformation = clean_t
          entity.model.commit_operation
          UI.messagebox("Kabinet: 스케일 도구로 크기를 바꿀 수 없습니다.\n[Extensions > Kabinet > 재생성] 메뉴를 이용하세요.", MB_OK)
        end
      rescue StandardError
        # Guard must never crash SU
      end
    end
  end
end
