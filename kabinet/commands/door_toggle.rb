module Kabinet
  module Commands
    # 도어 열기/닫기 토글 — 선택한 Kabinet 가구(없으면 모델의 모든 가구)의 여닫이 도어를
    # 경첩 쪽 세로 모서리를 축으로 앞으로 OPEN_DEG° 돌린다. 한 장이라도 열려 있으면 모두 닫는다.
    # 닫을 때는 저장해 둔 원래 변환을 그대로 복원하므로 위치가 어긋나지 않는다.
    # 대상: 여닫이(door_single / door_pair_left / door_pair_right)와 사용자가 '도어로 지정'한 그룹/컴포넌트.
    # 미닫이·접이·리프트업은 그대로 둔다. 열림 각도는 호출할 때 지정(기본 80°, 5~175°).
    # 사용자 지정 도어는 가구 정면이 부모 좌표의 −Y 방향이라고 보고, 경첩 쪽 세로 모서리(뒤쪽 모서리)를 축으로 돌린다.
    module DoorToggle
      module_function

      OPEN_DEG = 80.0
      MIN_DEG  = 5.0
      MAX_DEG  = 175.0
      HINGE_LEFT  = %w[door_single door_pair_left].freeze
      HINGE_RIGHT = %w[door_pair_right].freeze

      # role → :left / :right / nil(대상 아님)
      def hinge_side(role)
        r = role.to_s
        return :left if HINGE_LEFT.include?(r)
        return :right if HINGE_RIGHT.include?(r)
        nil
      end

      # 열림 각도(도) 보정: 숫자가 아니면 기본값, 5~175° 로 제한
      def clamp_deg(deg)
        v = Float(deg) rescue OPEN_DEG
        v = OPEN_DEG if v.nan? || v <= 0
        [[v, MIN_DEG].max, MAX_DEG].min
      end

      # 열 때 회전각(라디안): 왼쪽 경첩은 −, 오른쪽 경첩은 +  (Z축 기준, 앞(−Y)으로 열림)
      def open_angle(side, deg = OPEN_DEG)
        rad = clamp_deg(deg) * Math::PI / 180.0
        side == :left ? -rad : rad
      end

      # 사용자가 '도어로 지정'한 경첩 쪽('left'/'right'), 없으면 nil
      def designated_side(entity)
        v = Kabinet::Persistence::Attributes.get(entity, 'door_hinge').to_s
        v == 'left' ? :left : (v == 'right' ? :right : nil)
      end

      # 도어 한 장의 경첩 쪽: 사용자 지정 > 단문의 가구 설정(hinge_side) > role 기본값
      def side_of(entity)
        d = designated_side(entity)
        return d if d
        role = Kabinet::Persistence::Attributes.role(entity)
        if role.to_s == 'door_single'
          return Kabinet::Persistence::Attributes.get(entity, 'hinge_side').to_s == 'right' ? :right : :left
        end
        hinge_side(role)
      end

      def instance?(e)
        e.is_a?(::Sketchup::Group) || e.is_a?(::Sketchup::ComponentInstance)
      end

      def collect(entity, out)
        return unless instance?(entity) && entity.valid?
        out << entity if side_of(entity)
        ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
        ents.each { |c| collect(c, out) }
      end

      def find_doors(model)
        roots = model.selection.to_a.select { |e| instance?(e) }
        roots = model.entities.to_a.select { |e| instance?(e) && (Kabinet::Persistence::Attributes.assembly?(e) || designated_side(e)) } if roots.empty?
        doors = []
        roots.each { |e| collect(e, doors) }
        doors
      end

      NOT_FOUND_MSG = '열고 닫을 도어를 찾지 못했습니다. Kabinet 가구를 선택하거나, 직접 만든 도어 그룹이면 먼저 도어 그룹을 선택하고 「선택 → 도어 지정」을 누르세요.'.freeze

      # 선택한 그룹/컴포넌트를 도어로 지정(side: 'left'/'right') — 이후 열기/닫기 대상이 된다. 지정된 개수 반환
      def designate(side, model: Sketchup.active_model)
        s = side.to_s == 'right' ? 'right' : 'left'
        targets = model.selection.to_a.select { |e| instance?(e) }
        return 0 if targets.empty?
        model.start_operation('Kabinet — 도어 지정', true)
        begin
          targets.each { |e| Kabinet::Persistence::Attributes.set(e, 'door_hinge', s) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        targets.size
      end

      # 선택한 그룹/컴포넌트의 도어 지정 해제(열려 있으면 먼저 닫음). 해제 개수 반환
      def undesignate(model: Sketchup.active_model)
        targets = model.selection.to_a.select { |e| instance?(e) && designated_side(e) }
        return 0 if targets.empty?
        model.start_operation('Kabinet — 도어 지정 해제', true)
        begin
          targets.each do |e|
            close_door(e)
            e.delete_attribute(Kabinet::Persistence::Attributes::DICT, 'door_hinge')
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        targets.size
      end

      # 이미 열려 있는 도어를 새 각도로 다시 연다(닫혀 있으면 그대로). 바뀐 도어 수 반환
      def reangle(deg, model: Sketchup.active_model)
        doors = find_doors(model).select { |d| Kabinet::Persistence::Attributes.get(d, 'door_open') }
        return 0 if doors.empty?
        model.start_operation('Kabinet — 도어 열림 각도 변경', true)
        begin
          doors.each { |d| close_door(d); open_door(d, deg) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        doors.size
      end

      def run(deg = OPEN_DEG, model: Sketchup.active_model)
        roots = model.selection.to_a.select { |e| instance?(e) }
        roots = model.entities.to_a.select { |e| instance?(e) && (Kabinet::Persistence::Attributes.assembly?(e) || designated_side(e)) } if roots.empty?
        doors = []
        roots.each { |e| collect(e, doors) }
        if doors.empty?
          ::UI.messagebox(NOT_FOUND_MSG)
          return 0
        end
        closing = doors.any? { |d| Kabinet::Persistence::Attributes.get(d, 'door_open') }
        model.start_operation(closing ? 'Kabinet — 도어 닫기' : 'Kabinet — 도어 열기', true)
        begin
          doors.each { |d| closing ? close_door(d) : open_door(d, deg) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        doors.size
      end

      def open_door(d, deg = OPEN_DEG)
        return if Kabinet::Persistence::Attributes.get(d, 'door_open')
        side = side_of(d)
        b = d.bounds   # 부모(도어 그룹) 좌표
        pivot = ::Geom::Point3d.new(side == :left ? b.min.x : b.max.x, b.max.y, b.min.z)
        Kabinet::Persistence::Attributes.set(d, 'closed_tx', d.transformation.to_a)
        Kabinet::Persistence::Attributes.set(d, 'door_open', true)
        Kabinet::Persistence::Attributes.set(d, 'door_open_deg', clamp_deg(deg))
        rot = ::Geom::Transformation.rotation(pivot, ::Geom::Vector3d.new(0, 0, 1), open_angle(side, deg))
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
