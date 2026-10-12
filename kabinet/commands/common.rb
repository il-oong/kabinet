module Kabinet
  module Commands
    # 가구 공통사항: 모델(프로젝트)에 저장하고, 모델 안의 모든 Kabinet 가구에 일괄 적용(재생성).
    module Common
      module_function

      DICT = 'kabinet_common'.freeze

      def load(model = Sketchup.active_model)
        raw = model.get_attribute(DICT, 'json')
        raw ? JSON.parse(raw) : {}
      rescue StandardError
        {}
      end

      def save(common, model = Sketchup.active_model)
        model.set_attribute(DICT, 'json', JSON.generate(Kabinet::Core::Common.clean(common)))
      end

      # 그룹/컴포넌트 안까지 찾되, Kabinet 가구 안으로는 들어가지 않는다. 같은 정의는 한 번만.
      def find_assemblies(model = Sketchup.active_model)
        found = []
        seen = {}
        walk = lambda do |ents|
          ents.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            if Kabinet::Persistence::Attributes.assembly?(e)
              found << e
            else
              d = e.definition
              next if seen[d]
              seen[d] = true
              walk.call(d.entities)
            end
          end
        end
        walk.call(model.entities)
        found
      end

      # 반환: { changed:, same:, skipped: [이름: 사유], total: }
      def apply_all(common, model = Sketchup.active_model)
        save(common, model)
        targets = find_assemblies(model)
        result = { changed: 0, same: 0, skipped: [], total: targets.size }
        return result if targets.empty?

        schema = Kabinet::Persistence::Schema
        model.start_operation('Kabinet — 가구 공통사항 일괄 적용', true)
        begin
          targets.each do |grp|
            name = grp.name.to_s.empty? ? '가구' : grp.name
            if grp.locked?
              result[:skipped] << "#{name}: 잠김"
              next
            end
            spec = Kabinet::Persistence::Attributes.read_assembly_spec(grp)
            next result[:skipped] << "#{name}: 데이터 없음" unless spec
            before = schema.normalize(spec)
            after = schema.normalize(Kabinet::Core::Common.apply(spec, common))
            if after == before
              result[:same] += 1
              next
            end
            begin
              schema.validate!(after)
              Kabinet::Core::Assembly.from_hash(after).build_into(grp, spec_for_persistence: after)
              result[:changed] += 1
            rescue StandardError => e
              result[:skipped] << "#{name}: #{e.message}"
            end
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        result
      end

      def message(r)
        return '모델에 Kabinet 가구가 없습니다. 공통사항은 저장되었고 새로 만드는 가구에 적용됩니다.' if r[:total].zero?
        msg = "공통사항 적용 완료 — 가구 #{r[:total]}개 중 #{r[:changed]}개 다시 생성, #{r[:same]}개는 이미 같음"
        r[:skipped].empty? ? msg : "#{msg}\n건너뜀 #{r[:skipped].size}개:\n#{r[:skipped].join("\n")}"
      end
    end
  end
end
