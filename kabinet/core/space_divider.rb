module Kabinet
  module Core
    # ── 공간 인식 + 칸막이/도어 균등 분할 (순수 계산, mm Float 전용) ─────────
    #
    # SketchUp API에 의존하지 않는다. 도구(commands/space_divide.rb)가 레이캐스트로
    # 얻은 결과를 이 모듈에 넘기면 공간 박스와 부재 배치 계획이 나온다.
    #
    # 좌표계: 클릭 지점(공간 내부 한 점)을 원점으로 하는 가구 로컬 축.
    #   X = 폭, Y = 깊이(전면은 -Y 쪽), Z = 높이. 단위 mm.
    module SpaceDivider
      class Error < StandardError; end

      module_function

      MIN_SPACE_MM       = 50.0   # 이보다 작은 공간은 가구 칸으로 보지 않는다
      MIN_CELL_MM        = 50.0   # 분할 후 칸 최소 내폭
      MAX_OVERLAY_EXT_MM = 40.0   # 이웃 판 두께로 인정하는 상한 (벽·바닥 같은 큰 물체 배제)

      # hits: { [축(0=X,1=Y,2=Z), 부호(-1/+1)] => { dist:, bmin: [x,y,z], bmax: [x,y,z], thick: } }
      #   dist  = 원점에서 그 방향 첫 충돌면까지 거리(mm)
      #   bmin/bmax = 충돌한 부재(그룹) 외곽 박스, 원점 기준 로컬 mm
      #   thick = 충돌 부재의 해당 축 방향 두께(mm)
      # 열린 면(충돌 없음, 보통 전면)은 이웃 판의 끝 위치 중 원점에 가장 가까운 값으로 닫는다.
      # 반환: { lo: [x,y,z], hi: [x,y,z], size: [w,d,h], ext: {left:,right:,bottom:,top:}, front_open: }
      def resolve_space(hits)
        lo = []
        hi = []
        hits = hits.dup
        3.times do |i|
          # 둘러싼 판(측판·상하판)이 끝나는 곳보다 훨씬 멀리 맞은 물체는 이 가구가 아니다.
          # (뒤판 없는 장에서 뒷벽·창까지 깊이가 쭉 늘어나던 문제) → 그 방향은 열린 면으로 본다.
          [-1, 1].each do |sign|
            h = hits[[i, sign]]
            next unless h
            limit = frame_limit(hits, i, sign < 0 ? :lo : :hi)
            hits.delete([i, sign]) if limit && h[:dist].to_f > limit.abs + MAX_OVERLAY_EXT_MM
          end
          neg = hits[[i, -1]]
          pos = hits[[i, 1]]
          lo << (neg ? -neg[:dist].to_f : open_limit(hits, i, :lo))
          hi << (pos ? pos[:dist].to_f : open_limit(hits, i, :hi))
        end
        size = (0..2).map { |i| hi[i] - lo[i] }
        if size.any? { |s| s < MIN_SPACE_MM }
          raise Error, "인식된 공간이 너무 작습니다 (#{size.map { |s| s.round }.join(' × ')} mm)."
        end
        {
          lo: lo, hi: hi, size: size,
          ext: { left:   overlay_ext(hits[[0, -1]]), right: overlay_ext(hits[[0, 1]]),
                 bottom: overlay_ext(hits[[2, -1]]), top:   overlay_ext(hits[[2, 1]]) },
          front_open: hits[[1, -1]].nil?
        }
      end

      def open_limit(hits, axis, side)
        limit = frame_limit(hits, axis, side)
        raise Error, '공간이 열려 있어 범위를 인식할 수 없습니다. 판재로 둘러싸인 안쪽 면을 클릭하세요.' unless limit
        limit
      end

      # 다른 축 방향 판들이 이 축(side 쪽)으로 끝나는 위치 중 원점에 가장 가까운 값. 없으면 nil.
      def frame_limit(hits, axis, side)
        cands = hits.select { |(a, _), _| a != axis }.values.map do |h|
          side == :lo ? h[:bmin][axis].to_f : h[:bmax][axis].to_f
        end
        cands = side == :lo ? cands.select { |v| v < 0 } : cands.select { |v| v > 0 }
        return nil if cands.empty?
        side == :lo ? cands.max : cands.min
      end

      def overlay_ext(hit)
        t = hit ? hit[:thick].to_f : 0.0
        t > 0 && t <= MAX_OVERLAY_EXT_MM ? t : 0.0
      end

      # axis: 'x' → 세로 칸막이(폭을 가름) / 'z' → 가로 선반(높이를 가름)
      # cells: 칸 수 (칸막이 수 = cells - 1)
      # door_mode: 'overlay' | 'inset' | 'none'
      # 반환: { partitions: [{role:, pos:, dims:}], doors: [...], cell_mm:, warnings: [] }
      #   pos = 공간 최소 모서리(lo) 기준 mm, dims = [dx, dy, dz] mm
      def plan(space, axis:, cells:, thickness:, door_mode: 'overlay', door_thickness: nil)
        cells = cells.to_i
        raise Error, '칸 수는 2 이상이어야 합니다.' if cells < 2
        ai = axis.to_s == 'z' ? 2 : 0
        size = space[:size]
        t = thickness.to_f
        raise Error, '칸막이 두께가 올바르지 않습니다.' unless t > 0

        n = cells - 1
        cell = (size[ai] - n * t) / cells
        raise Error, "칸이 너무 좁습니다 (칸당 #{cell.round(1)}mm). 칸 수를 줄이세요." if cell < MIN_CELL_MM

        role = ai == 0 ? 'free_partition' : 'free_shelf'
        partitions = n.times.map do |i|
          pos = [0.0, 0.0, 0.0]
          pos[ai] = (i + 1) * cell + i * t
          dims = size.dup
          dims[ai] = t
          { role: "#{role}_#{i + 1}", pos: pos, dims: dims }
        end

        doors = []
        warnings = []
        unless door_mode.to_s == 'none'
          doors = plan_doors(space, ai, cells, door_mode.to_s,
                             (door_thickness || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM).to_f)
          doors.each do |d|
            if d[:dims][0] > Kabinet::Constants::SWING_DOOR_MAX_W_MM
              warnings << "도어 폭 #{d[:dims][0].round}mm — 여닫이 권장 #{Kabinet::Constants::SWING_DOOR_MAX_W_MM}mm 초과 (칸 수를 늘리세요)"
            end
            if d[:dims][2] > Kabinet::Constants::SWING_DOOR_MAX_H_MM
              warnings << "도어 높이 #{d[:dims][2].round}mm — 권장 #{Kabinet::Constants::SWING_DOOR_MAX_H_MM}mm 초과"
            end
          end
        end

        { partitions: partitions, doors: doors, cell_mm: cell, warnings: warnings.uniq }
      end

      # 오버레이: 공간 + 이웃 판 두께만큼 확장한 사각형을 덮음 (전면에서 front_offset 앞)
      # 인셋: 공간 개구 안에 전면과 면일치
      def plan_doors(space, ai, cells, mode, door_t)
        c = Kabinet::Constants
        size = space[:size]
        ext = space[:ext]
        if mode == 'inset'
          rx, rz = 0.0, 0.0
          rw, rh = size[0], size[2]
          y = 0.0
          side = top = bottom = c::INSET_DOOR_GAP_MM.to_f
        else
          rx, rz = -ext[:left], -ext[:bottom]
          rw = size[0] + ext[:left] + ext[:right]
          rh = size[2] + ext[:bottom] + ext[:top]
          y = -(door_t + Kabinet::Core::Gaps.front_offset)
          side = Kabinet::Core::Gaps.outside.to_f
          top = Kabinet::Core::Gaps.top.to_f
          bottom = Kabinet::Core::Gaps.bottom.to_f
        end
        Kabinet::Core::Fitting.equal_doors(
          rw, rh, cells, ai == 0 ? 'x' : 'z',
          side_gap: side, top_gap: top, bottom_gap: bottom,
          center_gap: Kabinet::Core::Gaps.between.to_f
        ).map do |d|
          { role: d[:role], pos: [rx + d[:x], y, rz + d[:z]], dims: [d[:w], door_t, d[:h]] }
        end
      end
    end
  end
end
