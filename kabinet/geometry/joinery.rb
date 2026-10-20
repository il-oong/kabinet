module Kabinet
  module Geometry
    # Computes panel sizes & positions for a carcase given W/D/H + thicknesses.
    # Default style :sides_full — sides run full height, top/bottom captured between sides.
    # Returns an Array of Hashes describing each panel:
    #   { role:, w:, d:, t:, x:, y:, z:, material: }
    # All dimensions are SU Length (use .mm beforehand).
    module Joinery
      module_function

      def carcase_panels(width:, depth:, height:, body_t:, back_t:, has_back:,
                        style: :sides_full, suppress_bottom: false,
                        suppress_left_side: false, suppress_right_side: false,
                        channel_top: false, open_top: false, channel_tops: [])
        case style
        when :sides_full
          sides_full(width: width, depth: depth, height: height, body_t: body_t,
                     back_t: back_t, has_back: has_back, suppress_bottom: suppress_bottom,
                     suppress_left_side: suppress_left_side, suppress_right_side: suppress_right_side,
                     channel_top: channel_top, open_top: open_top, channel_tops: channel_tops)
        else
          raise ArgumentError, "unknown joinery style: #{style}"
        end
      end

      # suppress_bottom:      true → 하판 생략. 적층 시 아래 모듈 상판을 공유.
      # suppress_left_side:   true → 좌 측판 생략. EP 또는 인접 모듈이 측벽 역할.
      # suppress_right_side:  true → 우 측판 생략.
      # channel_top: 찬넬 — 상판 앞을 (포켓+이마 두께)만큼 물리고, 이마(세로)·받침(가로)으로 ㄴ자 포켓을 만든다.
      def sides_full(width:, depth:, height:, body_t:, back_t:, has_back:,
                     suppress_bottom: false,
                     suppress_left_side: false, suppress_right_side: false,
                     channel_top: false, open_top: false, channel_tops: [])
        recess = Kabinet::Constants::BACK_RECESS_MM.mm
        panels = []
        # 찬넬은 측판에 막히지 않고 모듈 끝까지 간다 → 측판 앞을 찬넬 자리(포켓+이마 두께 × 이마 높이)만큼 따냄.
        # channel_tops: 찬넬 윗선 높이 목록 (서랍 사이 찬넬). channel_top 이면 몸통 윗면도 포함.
        tops    = channel_tops.dup
        tops   << height if channel_top
        rail_h  = Kabinet::Constants::CHANNEL_RAIL_H_MM.mm
        notch   = tops.empty? ? {} :
                  { notch_d: Kabinet::Constants::CHANNEL_POCKET_D_MM.mm + body_t,
                    notches: tops.sort.map { |zt| [zt - rail_h, zt] } }
        # Side L
        unless suppress_left_side
          panels << { role: 'side_left',  w: body_t,         d: depth,          t: height,
                      x: 0,               y: 0,               z: 0,               material: 'body' }.merge(notch)
        end
        # Side R
        unless suppress_right_side
          panels << { role: 'side_right', w: body_t,         d: depth,          t: height,
                      x: width - body_t,  y: 0,               z: 0,               material: 'body' }.merge(notch)
        end

        # 수평 패널(하판·상판·뒷판) X 범위: 측판 생략 시 해당 방향으로 확장
        hx_left  = suppress_left_side  ? 0         : body_t
        hx_right = suppress_right_side ? width     : width - body_t
        inner_w  = hx_right - hx_left

        # Bottom (suppress하면 생략 — 아래 모듈 상판과 공유)
        unless suppress_bottom
          panels << { role: 'bottom', w: inner_w, d: depth, t: body_t,
                      x: hx_left, y: 0, z: 0, material: 'body' }
        end
        # Top
        top_y = channel_top ? Kabinet::Constants::CHANNEL_POCKET_D_MM.mm + body_t : 0
        if open_top
          # 위가 뚫린 구조 (주방 하부장): 천판 대신 앞·뒤 목대만
          rail_w = Kabinet::Constants::TOP_RAIL_W_MM.mm
          panels << { role: 'top_rail_front', w: inner_w, d: rail_w, t: body_t,
                      x: hx_left, y: top_y, z: height - body_t, material: 'body' }
          panels << { role: 'top_rail_back',  w: inner_w, d: rail_w, t: body_t,
                      x: hx_left, y: depth - rail_w, z: height - body_t, material: 'body' }
        else
          panels << { role: 'top', w: inner_w, d: depth - top_y, t: body_t,
                      x: hx_left, y: top_y, z: height - body_t, material: 'body' }
        end
        panels.concat(channel_rail(width, 0, height, body_t)) if channel_top
        if has_back
          # Back panel (하판 없어도 뒷판 높이는 변하지 않음 — 실제 시공과 동일)
          panels << { role: 'back', w: inner_w, d: back_t, t: height - 2 * body_t,
                      x: hx_left, y: depth - back_t - recess, z: body_t, material: 'back' }
        end
        panels
      end

      # 찬넬 ㄴ자 — 모듈 전체 폭(측판 위를 지나 끝까지). z_top = 몸통 윗면 또는 위 서랍 전판 아랫선.
      #   이마: 세로판 body_t × RAIL_H, 몸통 앞에서 POCKET_D 뒤
      #   받침: 가로판 POCKET_D × body_t, 이마 아랫선에서 몸통 앞면까지
      def channel_rail(run_w, x, z_top, body_t)
        rail_h = Kabinet::Constants::CHANNEL_RAIL_H_MM.mm
        pocket = Kabinet::Constants::CHANNEL_POCKET_D_MM.mm
        [{ role: 'channel_rail',  w: run_w, d: body_t, t: rail_h,
           x: x, y: pocket, z: z_top - rail_h, material: 'body' },
         { role: 'channel_ledge', w: run_w, d: pocket, t: body_t,
           x: x, y: 0, z: z_top - rail_h, material: 'body' }]
      end
    end
  end
end
