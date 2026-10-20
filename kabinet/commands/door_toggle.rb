module Kabinet
  module Commands
    # 도어 열기/닫기 토글 — 선택한 Kabinet 가구(없으면 모델의 모든 가구)의 여닫이 도어를
    # 경첩 쪽 세로 모서리를 축으로 앞으로 OPEN_DEG° 돌린다. 한 장이라도 열려 있으면 모두 닫는다.
    # 닫을 때는 저장해 둔 원래 변환을 그대로 복원하므로 위치가 어긋나지 않는다.
    # 대상: 여닫이(door_single / door_pair_left / door_pair_right). 미닫이·접이·리프트업은 그대로 둔다.
    module DoorToggle
      module_function

      OPEN_DEG = 100.0
      HINGE_LEFT  = %w[door_single door_pair_left].freeze
      HINGE_RIGHT = %w[door_pair_right].freeze

      # role → :left / :right / nil(대상 아님)
      def hinge_side(role)
        r = role.to_s
        return :left if HINGE_LEFT.include?(r)
        return :right if HINGE_RIGHT.include?(r)
        nil
      end

      # 열 때 회전각(라디안): 왼쪽 경첩은 −, 오른쪽 경첩은 +  (Z축 기준, 앞(−Y)으로 열림)
      def open_angle(side)
        rad = OPEN_DEG * Math::PI / 180.0
        side == :left ? -rad : rad
      end

      def instance?(e)
        e.is_a?(::Sketchup::Group) || e.is_a?(::Sketchup::ComponentInstance)
      end

      def collect(entity, out)
        return unless instance?(entity) && entity.valid?
        out << entity if hinge_side(Kabinet::Persistence::Attributes.role(entity))
        ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
        ents.each { |c| collect(c, out) }
      end

      def run(model: Sketchup.active_model)
        roots = model.selection.to_a.select { |e| instance?(e) }
        roots = model.entities.to_a.select { |e| instance?(e) && Kabinet::Persistence::Attributes.assembly?(e) } if roots.empty?
        doors = []
        roots.each { |e| collect(e, doors) }
        if doors.empty?
          ::UI.messagebox('열고 닫을 여닫이 도어를 찾지 못했습니다. (Kabinet 가구를 선택하거나, 가구가 모델에 있어야 합니다)')
          return 0
        end
        closing = doors.any? { |d| Kabinet::Persistence::Attributes.get(d, 'door_open') }
        model.start_operation(closing ? 'Kabinet — 도어 닫기' : 'Kabinet — 도어 열기', true)
        begin
          doors.each { |d| closing ? close_door(d) : open_door(d) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        doors.size
      end

      def open_door(d)
        return if Kabinet::Persistence::Attributes.get(d, 'door_open')
        side = hinge_side(Kabinet::Persistence::Attributes.role(d))
        b = d.bounds   # 부모(도어 그룹) 좌표
        pivot = ::Geom::Point3d.new(side == :left ? b.min.x : b.max.x, b.max.y, b.min.z)
        Kabinet::Persistence::Attributes.set(d, 'closed_tx', d.transformation.to_a)
        Kabinet::Persistence::Attributes.set(d, 'door_open', true)
        rot = ::Geom::Transformation.rotation(pivot, ::Geom::Vector3d.new(0, 0, 1), open_angle(side))
        d.transformation = rot * d.transformation
      end

      def close_door(d)
        return unless Kabinet::Persistence::Attributes.get(d, 'door_open')
        arr = Kabinet::Persistence::Attributes.get(d, 'closed_tx')
        d.transformation = ::Geom::Transformation.new(arr) if arr
        Kabinet::Persistence::Attributes.set(d, 'door_open', false)
      end
    end
  end
end
