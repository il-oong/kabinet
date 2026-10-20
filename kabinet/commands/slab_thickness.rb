module Kabinet
  module Commands
    # 선택한 판재(또는 가구 그룹 안의 판재들)의 두께를 한 번에 바꾼다.
    # 판재 = 하위 그룹이 없는 그룹/컴포넌트 중 가장 얇은 방향이 3~60mm인 것.
    # 얇은 방향의 한쪽 면(로컬 좌표 큰 쪽)을 밀어 두께를 맞춘다. 반대쪽 면 위치는 그대로.
    module SlabThickness
      module_function

      MIN_MM = 3.0
      MAX_MM = 60.0

      # 로컬 bbox 세 변(mm, 인스턴스 배율 반영) → 판재면 얇은 축 번호(0/1/2), 아니면 nil
      def slab_axis(dims_mm)
        order = (0..2).sort_by { |i| dims_mm[i] }
        thin = dims_mm[order[0]]
        return nil unless thin >= MIN_MM && thin <= MAX_MM
        return nil if dims_mm[order[1]] < thin * 2   # 막대·각재는 제외
        order[0]
      end

      def run(thickness, model: Sketchup.active_model)
        t = thickness.to_f
        raise '두께를 3~60mm로 입력하세요.' unless t >= MIN_MM && t <= MAX_MM
        targets = model.selection.to_a.select { |e| instance?(e) }
        raise '두께를 바꿀 판재나 가구 그룹을 선택하세요.' if targets.empty?

        slabs = []
        skipped_asm = 0
        targets.each do |e|
          if Kabinet::Persistence::Attributes.assembly?(e)
            skipped_asm += 1
            next
          end
          collect(e, slabs)
        end
        if slabs.empty?
          raise skipped_asm.positive? ? 'Kabinet로 만든 가구는 "가구 공통사항"에서 두께를 바꾸세요 (다시 생성 시 유지).' :
                                        '선택 안에서 판재(두께 3~60mm)를 찾지 못했습니다.'
        end

        changed = 0
        model.start_operation("Kabinet — 판재 두께 #{t.round(1)}T로 변경", true)
        begin
          slabs.uniq.each { |inst| changed += 1 if resize(inst, t) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        msg = "판재 #{changed}장을 #{t.round(1).to_s.sub(/\.0\z/, '')}T로 바꿨습니다 (#{slabs.size - changed}장은 이미 같은 두께)."
        msg += " Kabinet 가구 #{skipped_asm}개는 제외 — 가구 공통사항에서 바꾸세요." if skipped_asm.positive?
        msg
      end

      def instance?(e)
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end

      # e 자신이 판재면 e, 아니면 안쪽 판재들 (하위 그룹 끝까지)
      def collect(e, out)
        kids = e.definition.entities.select { |c| instance?(c) }
        if kids.empty?
          # 판재 모양이면 판재, 아니면(속이 빈 상자처럼 한 덩어리 그룹) 안의 벽 면들을 대상으로 한다
          out << e if axis_of(e) || e.definition.entities.grep(Sketchup::Face).size >= 2
        else
          kids.each { |k| collect(k, out) unless Kabinet::Persistence::Attributes.assembly?(k) }
        end
        out
      end

      def scales(inst)
        tr = inst.transformation
        [tr.xaxis, tr.yaxis, tr.zaxis].map(&:length).map(&:to_f)
      end

      def dims_mm(inst)
        bb = inst.definition.bounds
        sc = scales(inst)
        [bb.width, bb.height, bb.depth].each_with_index.map { |v, i| v.to_f * 25.4 * sc[i] }
      end

      def axis_of(inst)
        slab_axis(dims_mm(inst))
      end

      WALL_PASS_MAX = 200

      # 한 덩어리 그룹(속 빈 상자 등): 서로 마주 보는 면 쌍 중 간격이 3~60mm인 것을 벽으로 보고,
      # 가운데에 가까운 쪽 면(안쪽 면)을 밀어 두께를 t로 맞춘다. 바깥 면 위치는 그대로.
      # 반환: 한 곳이라도 바꿨으면 true
      def resize_walls(inst, t)
        inst.make_unique if inst.definition.instances.size > 1
        defn = inst.definition
        changed = false
        WALL_PASS_MAX.times do
          pair = next_wall(defn, inst, t)
          break unless pair
          face, opp, cur, k = pair
          delta_local = (t - cur) / k
          sign = opp[:offset] < 0 ? 1 : -1   # 반대면이 뒤쪽(재료 쪽)이면 바깥(+)으로 밀어 두껍게
          before = face.valid? ? face.area : nil
          face.pushpull(sign * delta_local.mm)
          changed = true
          break if before.nil?
        end
        changed
      end

      # 아직 t와 다른 두께의 벽 하나: [안쪽 면, 반대 면 정보, 현재 두께(mm), 배율]
      def next_wall(defn, inst, t)
        ctr = defn.bounds.center
        defn.entities.grep(Sketchup::Face).each do |f|
          next unless f.valid?
          opp = Kabinet::Commands::FacePanel.opposite(f)
          next unless opp
          n = f.normal
          k = n.transform(inst.transformation).length / n.length
          cur = opp[:distance].to_f * 25.4 * k
          next if cur < MIN_MM || cur > MAX_MM || (cur - t).abs < 0.05
          # 마주 보는 두 면 중 가운데에 가까운 쪽을 움직인다 (이쪽이 아니면 상대 면이 같은 쌍으로 잡힘)
          next unless f.bounds.center.distance(ctr) <= opp[:face].bounds.center.distance(ctr)
          return [f, opp, cur, k]
        end
        nil
      end

      # 반환: 바꿨으면 true
      def resize(inst, t)
        i = axis_of(inst)
        return resize_walls(inst, t) unless i
        cur = dims_mm(inst)[i]
        return false if (cur - t).abs < 0.05

        inst.make_unique if inst.definition.instances.size > 1   # 선택한 것만 바뀌게
        defn = inst.definition
        bb = defn.bounds
        max_c = [bb.max.x, bb.max.y, bb.max.z][i]
        tol = 0.01.mm
        verts = defn.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.select do |v|
          ([v.position.x, v.position.y, v.position.z][i] - max_c).abs <= tol
        end
        return false if verts.empty?

        delta_local = (t - cur) / scales(inst)[i]
        vec = [0, 0, 0]
        vec[i] = delta_local.mm
        defn.entities.transform_entities(Geom::Transformation.translation(Geom::Vector3d.new(*vec)), verts)
        true
      end
    end
  end
end
