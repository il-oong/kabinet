module Kabinet
  module Geometry
    # Computes panel sizes & positions for a carcase given W/D/H + thicknesses.
    # Default style :sides_full — sides run full height, top/bottom captured between sides.
    # Returns an Array of Hashes describing each panel:
    #   { role:, w:, d:, t:, x:, y:, z:, material: }
    # All dimensions are SU Length (use .mm beforehand).
    module Joinery
      module_function

      def carcase_panels(width:, depth:, height:, body_t:, back_t:, has_back:, style: :sides_full)
        case style
        when :sides_full
          sides_full(width: width, depth: depth, height: height, body_t: body_t,
                     back_t: back_t, has_back: has_back)
        else
          raise ArgumentError, "unknown joinery style: #{style}"
        end
      end

      def sides_full(width:, depth:, height:, body_t:, back_t:, has_back:)
        recess = Kabinet::Constants::BACK_RECESS_MM.mm
        panels = []
        # Side L
        panels << { role: 'side_left',  w: body_t,         d: depth,             t: height,
                    x: 0,               y: 0,              z: 0,                  material: 'body' }
        # Side R
        panels << { role: 'side_right', w: body_t,         d: depth,             t: height,
                    x: width - body_t,  y: 0,              z: 0,                  material: 'body' }
        # Bottom
        panels << { role: 'bottom',     w: width - 2 * body_t, d: depth,        t: body_t,
                    x: body_t,          y: 0,              z: 0,                  material: 'body' }
        # Top
        panels << { role: 'top',        w: width - 2 * body_t, d: depth,        t: body_t,
                    x: body_t,          y: 0,              z: height - body_t,    material: 'body' }
        if has_back
          # Back panel
          panels << { role: 'back',     w: width - 2 * body_t, d: back_t,       t: height - 2 * body_t,
                      x: body_t,        y: depth - back_t - recess, z: body_t,    material: 'back' }
        end
        panels
      end
    end
  end
end
