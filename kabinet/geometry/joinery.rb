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
                        suppress_left_side: false, suppress_right_side: false)
        case style
        when :sides_full
          sides_full(width: width, depth: depth, height: height, body_t: body_t,
                     back_t: back_t, has_back: has_back, suppress_bottom: suppress_bottom,
                     suppress_left_side: suppress_left_side, suppress_right_side: suppress_right_side)
        else
          raise ArgumentError, "unknown joinery style: #{style}"
        end
      end

      # suppress_bottom:      true → 하판 생략. 적층 시 아래 모듈 상판을 공유.
      # suppress_left_side:   true → 좌 측판 생략. EP 또는 인접 모듈이 측벽 역할.
      # suppress_right_side:  true → 우 측판 생략.
      def sides_full(width:, depth:, height:, body_t:, back_t:, has_back:,
                     suppress_bottom: false,
                     suppress_left_side: false, suppress_right_side: false)
        recess = Kabinet::Constants::BACK_RECESS_MM.mm
        panels = []
        # Side L
        unless suppress_left_side
          panels << { role: 'side_left',  w: body_t,         d: depth,          t: height,
                      x: 0,               y: 0,               z: 0,               material: 'body' }
        end
        # Side R
        unless suppress_right_side
          panels << { role: 'side_right', w: body_t,         d: depth,          t: height,
                      x: width - body_t,  y: 0,               z: 0,               material: 'body' }
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
        panels << { role: 'top', w: inner_w, d: depth, t: body_t,
                    x: hx_left, y: 0, z: height - body_t, material: 'body' }
        if has_back
          # Back panel (하판 없어도 뒷판 높이는 변하지 않음 — 실제 시공과 동일)
          panels << { role: 'back', w: inner_w, d: back_t, t: height - 2 * body_t,
                      x: hx_left, y: depth - back_t - recess, z: body_t, material: 'back' }
        end
        panels
      end
    end
  end
end
