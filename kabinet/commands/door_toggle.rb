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

      # 도어(경첩 쪽이 정해진 그룹/컴포넌트)를 안쪽 끝까지 찾아 out 에 모은다.
      # seen: 같은 정의(definition)를 여러 번 훑지 않도록 하는 방문 기록(컴포넌트 복제본이 많을 때 중복·지연 방지)
      def collect(entity, out, seen = {})
        return unless instance?(entity) && entity.valid?
        out << entity if side_of(entity) && !out.include?(entity)
        ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
        key = entity.respond_to?(:definition) ? entity.definition : entity
        return if seen[key]
        seen[key] = true
        ents.each { |c| collect(c, out, seen) }
      end

      # 클릭/호버로 얻은 경로(루트→말단)에서 가장 안쪽 도어를 찾는다.
      # prefix: 편집 중인 컨텍스트(model.active_path, 루트→활성 그룹). PickHelper 의 경로는 활성 엔티티부터 시작하므로
      #         편집 중인 그룹 안을 클릭하면 조상이 빠진다 — 앞에 붙여서 월드 변환·'같은 가구 전체'가 맞게 한다.
      # 반환: [도어, 도어의 부모 인스턴스들(루트→부모)] 또는 nil
      def door_in_path(path, prefix = nil)
        list = (prefix || []).to_a + (path || []).to_a
        idx = (list.size - 1).downto(0).find { |i| instance?(list[i]) && side_of(list[i]) }
        idx ? [list[idx], list[0...idx].select { |e| instance?(e) }] : nil
      end

      # 같은 도어라도 부모 경로(복제된 가구 인스턴스)가 다르면 다른 대상 — 호버 캐시 키
      def pick_key(found)
        found ? (found[1] + [found[0]]).map(&:entityID) : nil
      end

      # 한 장이라도 열려 있으면 '닫기', 모두 닫혀 있으면 '열기'
      def closing?(doors)
        doors.any? { |d| Kabinet::Persistence::Attributes.get(d, 'door_open') }
      end

      # 주어진 도어들을 한 번의 되돌리기 단위로 열거나 닫는다. 닫는 중이면 true 반환
      def toggle(doors, deg = OPEN_DEG, model: Sketchup.active_model)
        closing = closing?(doors)
        model.start_operation(closing ? 'Kabinet — 도어 닫기' : 'Kabinet — 도어 열기', true)
        begin
          doors.each { |d| closing ? close_door(d) : open_door(d, deg) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        closing
      end

      # 선택이 없을 때 훑을 최상위 개체: 모든 그룹/컴포넌트(직접 만든 가구 안에 지정한 도어도 찾기 위해)
      def top_level_roots(model)
        model.entities.to_a.select { |e| instance?(e) }
      end

      def find_doors(model)
        roots = model.selection.to_a.select { |e| instance?(e) }
        roots = top_level_roots(model) if roots.empty?
        doors = []
        seen = {}
        roots.each { |e| collect(e, doors, seen) }
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
        doors = find_doors(model)
        if doors.empty?
          ::UI.messagebox(NOT_FOUND_MSG)
          return 0
        end
        toggle(doors, deg, model: model)
        doors.size
      end

      # 경첩 축의 x(부모 좌표): 90°로 열었을 때 도어 안쪽 면이 '몸통 외면 선'에 맞도록 축을 몸통 선에 둔다.
      # 우선순위: ① Kabinet 도어가 저장한 몸통 선(body_x0/body_x1, 도어 그룹 좌표) ② 같은 부모 안의 도어 아닌 형제 개체의
      #           경첩 쪽 끝(직접 만든 가구) ③ 도어 자신의 경첩 쪽 모서리(이전 동작)
      # 인자: edge_min/edge_max = 도어 bounds 의 x 범위, sibling = 형제 개체 범위(없으면 nil)
      def hinge_line(side, edge_min, edge_max, body_x0 = nil, body_x1 = nil, sibling = nil)
        v = side == :left ? body_x0 : body_x1
        return v.to_f if v.is_a?(Numeric)
        if sibling
          lo, hi = sibling
          overlap = hi > edge_min && lo < edge_max          # 도어와 x 범위가 겹치는 몸통일 때만
          return (side == :left ? lo : hi) if overlap
        end
        side == :left ? edge_min : edge_max
      end

      # 같은 부모 안의 도어가 아닌 형제 개체(직접 만든 가구의 몸통)의 x 범위 [min, max], 없으면 nil
      def sibling_x_range(door)
        parent = door.respond_to?(:parent) ? door.parent : nil
        return nil unless parent && parent.respond_to?(:entities)
        others = parent.entities.to_a.reject do |e|
          e.equal?(door) || !e.respond_to?(:bounds) || (instance?(e) && side_of(e))
        end
        return nil if others.empty?
        bb = ::Geom::BoundingBox.new
        others.each { |e| bb.add(e.bounds) }
        bb.empty? ? nil : [bb.min.x, bb.max.x]
      rescue StandardError
        nil
      end

      def open_door(d, deg = OPEN_DEG)
        return if Kabinet::Persistence::Attributes.get(d, 'door_open')
        side = side_of(d)
        b = d.bounds   # 부모(도어 그룹) 좌표
        px = hinge_line(side, b.min.x, b.max.x,
                        Kabinet::Persistence::Attributes.get(d, 'body_x0'),
                        Kabinet::Persistence::Attributes.get(d, 'body_x1'), sibling_x_range(d))
        pivot = ::Geom::Point3d.new(px, b.max.y, b.min.z)
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
