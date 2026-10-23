module Kabinet
  module Commands
    # 도면 치수표(여러 가구 spec + 위치)를 SketchUp 모델에 한 번에 생성.
    # item: { 'spec' => {...}, 'x' => mm(왼쪽), 'y' => mm(앞면 위치), 'z' => mm(바닥 띄움), 'rot' => 도(Z축 회전) }
    module DrawingImport
      module_function

      # item → [x, y, z, rot] (mm, 도). 숫자가 아니면 0.
      def placement(item)
        %w[x y z rot].map { |k| item[k].to_f }
      end

      def transform_for(item)
        x, y, z, rot = placement(item)
        origin = ::Geom::Point3d.new(x.mm, y.mm, z.mm)
        tr = ::Geom::Transformation.new(origin)
        return tr if rot.abs < 0.001
        tr * ::Geom::Transformation.rotation(::Geom::Point3d.new(0, 0, 0), ::Geom::Vector3d.new(0, 0, 1), rot.degrees)
      end

      # 반환: { roots: [...], warnings: [...] }
      # 전부 먼저 검증하고, 생성 중 하나라도 실패하면 이번에 만든 가구를 모두 지운다(부분 생성 방지).
      def run(items, model: Sketchup.active_model)
        raise '생성할 가구가 없습니다.' if items.nil? || items.empty?
        warnings = []
        items.each_with_index do |it, i|
          spec = it['spec']
          raise "#{i + 1}번째 가구의 설정이 비어 있습니다." unless spec.is_a?(Hash)
          begin
            norm = Kabinet::Persistence::Schema.normalize(spec)
            Kabinet::Persistence::Schema.validate!(norm)
            warnings.concat(Kabinet::Core::Validation.warnings(norm).map { |w| "#{spec['name'] || (i + 1)}: #{w}" })
          rescue StandardError => e
            raise "#{i + 1}번째 가구(#{spec['name']}) 설정 오류: #{e.message}"
          end
        end

        roots = []
        items.each_with_index do |it, i|
          begin
            roots << Kabinet::Commands::Generate.run_assembly(it['spec'], model: model, transform: transform_for(it))
          rescue StandardError => e
            rollback(roots, model)
            raise "#{i + 1}번째 가구(#{it['spec']['name']}) 생성 실패 — 이번에 만든 가구는 모두 취소했습니다: #{e.message}"
          end
        end
        model.selection.clear
        roots.each { |r| model.selection.add(r) }
        { roots: roots, warnings: warnings }
      end

      def rollback(roots, model)
        model.start_operation('Kabinet — 도면 생성 취소', true)
        roots.each { |r| r.erase! if r.respond_to?(:valid?) && r.valid? }
        model.commit_operation
      rescue StandardError
        model.abort_operation
      end
    end
  end
end
