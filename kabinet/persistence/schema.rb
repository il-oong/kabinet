module Kabinet
  module Persistence
    module Schema
      CURRENT_VERSION = 1

      MODULE_KINDS      = %w[shelf_module drawer_module desk_module bed_gap].freeze
      DRAWER_TYPES      = %w[undermount side_mount].freeze
      DOOR_CONFIGS      = %w[none single pair].freeze
      DOOR_TYPES        = %w[swing sliding folding lift_up none].freeze
      HANDLE_TYPES      = %w[bar knob cup_pull channel push_open none].freeze
      DOOR_MOUNT_STYLES = %w[overlay inset].freeze
      MATERIALS    = %w[LPM PET MDF_paint UV_gloss acrylic high_gloss phenix plywood
                        solid_wood HPL 기타].freeze

      class ValidationError < StandardError; end

      def self.mm(value)
        Float(value).to_l_mm
      end

      def self.normalize(spec)
        h = deep_stringify(spec)
        h['version']       ||= CURRENT_VERSION
        h['name']          ||= 'Untitled'
        h['furniture_type']  = h['furniture_type'].to_s
        h['width']           = Float(h['width'])
        h['max_depth']       = Float(h['max_depth'])
        h['base_height']     = Float(h['base_height'] || 0)
        h['material']        = h['material'] || 'LPM'
        h['edge_banding_mm'] = Float(h['edge_banding_mm'] || Kabinet::Constants::DEFAULT_EDGE_THICKNESS_MM)
        # 수평 런 모드: 모듈을 X축(가로)으로 배열
        h['run_mode']      = h['run_mode'] ? true : false
        h['run_height']    = Float(h['run_height'] || 740)
        h['has_kickboard'] = h.fetch('has_kickboard', true) ? true : false

        h['ep'] ||= {}
        h['ep']['left']      = h['ep'].fetch('left', true) ? true : false
        h['ep']['right']     = h['ep'].fetch('right', true) ? true : false
        h['ep']['thickness'] = Float(h['ep'].fetch('thickness', Kabinet::Constants::DEFAULT_EP_THICKNESS_MM))

        h['top_panel'] = if h['top_panel'].nil?
                           nil
                         else
                           { 'thickness' => Float(h['top_panel'].fetch('thickness', Kabinet::Constants::DEFAULT_TOP_PANEL_MM)) }
                         end

        h['modules'] = (h['modules'] || []).map { |m| normalize_module(m) }
        h
      end

      def self.normalize_module(m)
        kind = m['kind'].to_s
        raise ValidationError, "unknown module kind: #{kind}" unless MODULE_KINDS.include?(kind)

        # 침대 공간 — 폭만 있는 단순 마커
        if kind == 'bed_gap'
          return { 'kind' => 'bed_gap',
                   'width' => Float(m['width'] || 1600),
                   'label' => (m['label'] || '침대 공간').to_s }
        end

        # 책상 모듈 — 하위 필드 그대로 통과
        if kind == 'desk_module'
          out = m.dup
          out['kind'] = 'desk_module'
          out['width']  = Float(m['width']  || 1400)
          out['depth']  = Float(m['depth']  || 700)
          out['height'] = Float(m['height'] || 750)
          return out
        end

        out = {
          'kind'             => kind,
          'width'            => Float(m['width']),
          'depth'            => Float(m['depth']),
          'height'           => Float(m['height']),
          'body_thickness'   => Float(m['body_thickness'] || Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM),
          'back_thickness'   => Float(m['back_thickness'] || Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM),
          'has_back'         => m.fetch('has_back', true) ? true : false,
          'material'         => (m['material'] || 'LPM').to_s,
          'handle_type'      => (m['handle_type'] || 'none').to_s,
          'edge_banding_mm'  => Float(m['edge_banding_mm'] || Kabinet::Constants::DEFAULT_EDGE_THICKNESS_MM)
        }

        unless HANDLE_TYPES.include?(out['handle_type'])
          out['handle_type'] = 'none'
        end

        case kind
        when 'shelf_module'
          out['door_config']  = m['door_config'] || 'none'
          unless DOOR_CONFIGS.include?(out['door_config'])
            raise ValidationError, "invalid door_config: #{out['door_config']}"
          end
          out['door_type']    = (m['door_type'] || 'swing').to_s
          out['door_type']    = 'swing' unless DOOR_TYPES.include?(out['door_type'])
          out['door_thickness'] = Float(m['door_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM)
          out['door_material']  = (m['door_material'] || out['material']).to_s
          out['door_mount']     = DOOR_MOUNT_STYLES.include?(m['door_mount'].to_s) ? m['door_mount'].to_s : 'overlay'
          out['shelves']      = (m['shelves'] || []).map { |s|
            { 'height_from_bottom' => Float(s['height_from_bottom']),
              'thickness'          => Float(s['thickness'] || out['body_thickness']),
              'depth_inset'        => Float(s['depth_inset'] || 20) }
          }
          out['accessories']  = (m['accessories'] || []).map { |a| normalize_accessory(a) }

        when 'drawer_module'
          out['drawer_count']     = Integer(m['drawer_count'] || 1)
          out['drawer_type']      = m['drawer_type'] || 'undermount'
          unless DRAWER_TYPES.include?(out['drawer_type'])
            raise ValidationError, "invalid drawer_type: #{out['drawer_type']}"
          end
          out['drawer_thickness'] = Float(m['drawer_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM)
          out['door_material']    = (m['door_material'] || out['material']).to_s
          out['handle_hole_mm']   = Integer(m['handle_hole_mm'] || Kabinet::Constants::DEFAULT_HANDLE_HOLE_MM)
        end
        out
      end

      def self.normalize_accessory(a)
        kind = a['kind'].to_s
        case kind
        when 'hanging_rod'
          { 'kind' => 'hanging_rod',
            'height_from_bottom' => Float(a['height_from_bottom']),
            'depth_inset'        => Float(a['depth_inset'] || 75),
            'diameter'           => Float(a['diameter'] || Kabinet::Constants::HANGING_ROD_DIAMETER_MM) }
        when 'system_hanger'
          { 'kind' => 'system_hanger',
            'height_from_bottom' => Float(a['height_from_bottom']),
            'rail_height'        => Float(a['rail_height'] || 30),
            'rail_thickness'     => Float(a['rail_thickness'] || 5) }
        when 'shelf_accessory'
          { 'kind' => 'shelf_accessory',
            'height_from_bottom' => Float(a['height_from_bottom']),
            'thickness'          => Float(a['thickness'] || 18),
            'depth_inset'        => Float(a['depth_inset'] || 20) }
        else
          raise ValidationError, "unknown accessory kind: #{kind}"
        end
      end

      def self.validate!(spec)
        raise ValidationError, 'spec must be a Hash' unless spec.is_a?(Hash)
        raise ValidationError, 'width must be > 0'     unless spec['width'].to_f > 0
        raise ValidationError, 'max_depth must be > 0' unless spec['max_depth'].to_f > 0
        spec['modules'].each_with_index do |m, i|
          next if m['kind'] == 'bed_gap'  # bed_gap has no height/depth
          raise ValidationError, "module[#{i}] height must be > 0" unless m['height'].to_f > 0
          raise ValidationError, "module[#{i}] depth must be > 0"  unless m['depth'].to_f > 0
        end
        true
      end

      def self.deep_stringify(obj)
        case obj
        when Hash  then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
        when Array then obj.map { |v| deep_stringify(v) }
        else obj
        end
      end
    end
  end
end

class Numeric
  # Convenience: 900.to_l_mm => SketchUp Length representing 900mm
  def to_l_mm
    self.to_f.mm
  end
end
