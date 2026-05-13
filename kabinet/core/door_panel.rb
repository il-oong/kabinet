module Kabinet
  module Core
    # Door(s) mounted in front of a carcase opening.
    #
    # door_type: 'swing'    여닫이 — 오버레이 힌지, 전후 동일 레벨
    #            'sliding'  미닫이 — 전후 2개 레일, 도어가 교대로 깊이 다름
    #            'folding'  접이식 — 바이폴드: 각 도어를 반폭 2장으로 분리
    #            'lift_up'  리프트업 — 단일 패널 상개형, 좁은 클리어런스
    #            'none'     도어 없음
    #
    # opening_width / opening_height: 참조 기준 치수.
    #   swing/folding/lift_up → 모듈 전체 폭(오버레이)
    #   sliding               → 모듈 전체 폭(도어가 레일 안에서 이동)
    class DoorPanel
      attr_reader :opening_width, :opening_height, :thickness, :config, :door_type,
                  :gap_top, :gap_bottom, :gap_outside, :reveal_between, :front_offset

      def initialize(opening_width:, opening_height:, thickness:,
                     config: 'pair', door_type: 'swing',
                     gap_top:        Kabinet::Constants::DOOR_GAP_TOP_MM.mm,
                     gap_bottom:     Kabinet::Constants::DOOR_GAP_BOTTOM_MM.mm,
                     gap_outside:    Kabinet::Constants::DOOR_GAP_OUTSIDE_MM.mm,
                     reveal_between: Kabinet::Constants::DOOR_REVEAL_BETWEEN_MM.mm,
                     front_offset:   Kabinet::Constants::DOOR_FRONT_OFFSET_MM.mm)
        @opening_width  = opening_width
        @opening_height = opening_height
        @thickness      = thickness
        @config         = config.to_s
        @door_type      = door_type.to_s
        @gap_top        = gap_top
        @gap_bottom     = gap_bottom
        @gap_outside    = gap_outside
        @reveal_between = reveal_between
        @front_offset   = front_offset
      end

      # 여닫이 기준 도어 높이 (gap_top + gap_bottom 제외)
      def door_height
        @opening_height - @gap_top - @gap_bottom
      end

      # 카케이스 로컬 좌표계(원점 = 카케이스 전면-좌-하단)에서 도어를 배치.
      def build(parent_entities, carcase_origin_transform)
        return if @config == 'none' || @door_type == 'none'

        case @door_type
        when 'sliding'  then build_sliding(parent_entities, carcase_origin_transform)
        when 'folding'  then build_folding(parent_entities, carcase_origin_transform)
        when 'lift_up'  then build_lift_up(parent_entities, carcase_origin_transform)
        else                 build_swing(parent_entities, carcase_origin_transform)
        end
      end

      private

      # ── 여닫이 (Swing) ──────────────────────────────────────────────────
      # 오버레이 힌지: 도어가 측판 전면을 덮음.
      # 모든 도어가 동일 Y 레벨 (y = -(두께 + 돌출)).
      def build_swing(entities, tx)
        z0     = @gap_bottom
        y0     = -(@thickness + @front_offset)
        door_h = door_height

        case @config
        when 'single'
          door_w = @opening_width - 2 * @gap_outside
          place_door(entities, tx,
                     x: @gap_outside, y: y0, z: z0,
                     w: door_w, h: door_h, role: 'door_single')
        when 'pair'
          half_w = (@opening_width - 2 * @gap_outside - @reveal_between) / 2.0
          place_door(entities, tx,
                     x: @gap_outside, y: y0, z: z0,
                     w: half_w, h: door_h, role: 'door_pair_left')
          place_door(entities, tx,
                     x: @gap_outside + half_w + @reveal_between, y: y0, z: z0,
                     w: half_w, h: door_h, role: 'door_pair_right')
        end
      end

      # ── 미닫이 (Sliding) ────────────────────────────────────────────────
      # 전후 2개 레일에 도어를 교대 배치.
      # 전면 레일 도어(front): y = -(두께 + 돌출)
      # 후면 레일 도어(back) : y = -(두께 + track_spacing + 돌출)
      #
      # 도어 폭 = (모듈폭 + 겹침) / 도어수  → 인접 도어와 겹침 부분 발생
      # 도어 높이 = 모듈높이 - 상부레일클리어런스 - 하부가이드클리어런스
      def build_sliding(entities, tx)
        track_spacing = Kabinet::Constants::SLIDING_DOOR_TRACK_SPACING_MM.mm
        overlap       = Kabinet::Constants::SLIDING_DOOR_OVERLAP_MM.mm
        top_gap       = Kabinet::Constants::SLIDING_DOOR_TOP_GAP_MM.mm
        bot_gap       = Kabinet::Constants::SLIDING_DOOR_BOTTOM_GAP_MM.mm

        door_h  = @opening_height - top_gap - bot_gap
        z0      = bot_gap
        y_front = -(@thickness + @front_offset)
        y_back  = -(@thickness + track_spacing + @front_offset)

        case @config
        when 'single'
          # 단문 슬라이딩: 레일 1개, 전면
          place_door(entities, tx,
                     x: 0, y: y_front, z: z0,
                     w: @opening_width, h: door_h, role: 'door_sliding_single')

        when 'pair'
          # 2짝 슬라이딩: 전면 레일(좌) + 후면 레일(우)
          door_w = (@opening_width + overlap) / 2.0
          # 전면 레일: 좌측 도어
          place_door(entities, tx,
                     x: 0, y: y_front, z: z0,
                     w: door_w, h: door_h, role: 'door_sliding_front')
          # 후면 레일: 우측 도어 (우측 끝에서 door_w 만큼 걸침)
          place_door(entities, tx,
                     x: @opening_width - door_w, y: y_back, z: z0,
                     w: door_w, h: door_h, role: 'door_sliding_back')
        end
      end

      # ── 접이식 (Folding / Bi-fold) ────────────────────────────────────────
      # 각 도어를 반폭 2장 패널로 분할 (바이폴드).
      # 닫힌 상태로 렌더링 → 패널들이 나란히 펼쳐진 형태.
      # 재단표에서 반폭 패널로 집계됨.
      def build_folding(entities, tx)
        z0     = @gap_bottom
        y0     = -(@thickness + @front_offset)
        door_h = door_height

        case @config
        when 'single'
          # 단문 바이폴드: 좌측 힌지, 2장 패널
          full_w  = @opening_width - 2 * @gap_outside
          panel_w = full_w / 2.0
          place_door(entities, tx, x: @gap_outside,          y: y0, z: z0,
                     w: panel_w, h: door_h, role: 'door_fold_L1')
          place_door(entities, tx, x: @gap_outside + panel_w, y: y0, z: z0,
                     w: panel_w, h: door_h, role: 'door_fold_L2')

        when 'pair'
          # 양개 바이폴드: 좌측 2장 + 우측 2장, 총 4패널
          half_opening = (@opening_width - 2 * @gap_outside - @reveal_between) / 2.0
          panel_w      = half_opening / 2.0
          # 좌측 2장
          x0 = @gap_outside
          place_door(entities, tx, x: x0,            y: y0, z: z0,
                     w: panel_w, h: door_h, role: 'door_fold_LL')
          place_door(entities, tx, x: x0 + panel_w,  y: y0, z: z0,
                     w: panel_w, h: door_h, role: 'door_fold_LR')
          # 우측 2장
          x1 = @gap_outside + 2 * panel_w + @reveal_between
          place_door(entities, tx, x: x1,            y: y0, z: z0,
                     w: panel_w, h: door_h, role: 'door_fold_RL')
          place_door(entities, tx, x: x1 + panel_w,  y: y0, z: z0,
                     w: panel_w, h: door_h, role: 'door_fold_RR')
        end
      end

      # ── 리프트업 (Lift-Up / 상개형) ────────────────────────────────────────
      # 단일 패널이 위로 열림. 클리어런스 3mm (gas cylinder arm 고려).
      # 항상 단일 패널 (config 무시하고 single 취급).
      def build_lift_up(entities, tx)
        gap    = Kabinet::Constants::LIFT_UP_DOOR_GAP_MM.mm
        z0     = gap
        y0     = -(@thickness + @front_offset)
        door_w = @opening_width - 2 * gap
        door_h = @opening_height - 2 * gap
        place_door(entities, tx,
                   x: gap, y: y0, z: z0,
                   w: door_w, h: door_h, role: 'door_lift_up')
      end

      # ── 공통 배치 헬퍼 ───────────────────────────────────────────────────
      def place_door(parent_entities, parent_transform, x:, y:, z:, w:, h:, role:)
        local = ::Geom::Transformation.new(::Geom::Point3d.new(x, y, z))
        Kabinet::Geometry::Builder.box(parent_entities, w, @thickness, h,
                                       parent_transform * local,
                                       role: role, label: role, material_name: 'door')
      end
    end
  end
end
