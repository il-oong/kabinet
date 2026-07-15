module Kabinet
  module Persistence
    module Schema
      CURRENT_VERSION = 1

      MODULE_KINDS      = %w[shelf_module drawer_module desk_module bed_gap v_gap].freeze
      BED_DRAWER_SIDES  = %w[foot left right].freeze
      BASE_TYPES        = %w[wood steel].freeze
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
        # 받침 구조: wood(목재 받침+걸레받이, 기본) / steel(철제 각파이프 프레임)
        h['base_type']       = BASE_TYPES.include?(h['base_type'].to_s) ? h['base_type'].to_s : 'wood'
        h['material']        = h['material'] || 'LPM'
        h['edge_banding_mm'] = Float(h['edge_banding_mm'] || Kabinet::Constants::DEFAULT_EDGE_THICKNESS_MM)
        # 수평 런 모드: 모듈을 X축(가로)으로 배열
        h['run_mode']      = h['run_mode'] ? true : false
        h['run_height']    = Float(h['run_height'] || 740)
        h['has_kickboard'] = h.fetch('has_kickboard', true) ? true : false

        h['ep'] ||= {}
        h['ep']['left']      = h['ep'].fetch('left', true) ? true : false
        h['ep']['right']     = h['ep'].fetch('right', true) ? true : false
        # 상부 EP: 가구 최상단을 덮는 마감판 (전체 폭, 측면 EP 위에 얹힘)
        h['ep']['top']       = h['ep'].fetch('top', false) ? true : false
        h['ep']['thickness'] = Float(h['ep'].fetch('thickness', Kabinet::Constants::DEFAULT_EP_THICKNESS_MM))
        # EP가 도어/전판 전면까지 커버 (실무 기본) — false면 카케이스 깊이까지만
        h['ep']['cover_fronts'] = h['ep'].fetch('cover_fronts', true) ? true : false
        # EP 윗면만 보이게: EP가 상판 두께 아래에서 끝나고 상판이 EP 위에 얹힘
        h['ep_top_flush'] = h.fetch('ep_top_flush', false) ? true : false

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

        # 침대 공간 — 기본은 폭만 차지하는 마커, storage: true면 수납침대
        # (서랍 플랫폼: 침대 프레임 겸 발치 서랍장, run_height 무시하고 자체 높이)
        if kind == 'bed_gap'
          out = { 'kind'    => 'bed_gap',
                  'width'   => Float(m['width'] || 1600),
                  'label'   => (m['label'] || '침대 공간').to_s,
                  'storage' => m['storage'] ? true : false }
          if out['storage']
            out['platform_height'] = Float(m['platform_height'] || 350)
            out['bed_depth']       = Float(m['bed_depth'] || 2000)
            out['drawer_count']    = [Integer(m['drawer_count'] || 2), 1].max
            out['drawer_type']     = DRAWER_TYPES.include?(m['drawer_type'].to_s) ? m['drawer_type'].to_s : 'undermount'
            out['drawer_thickness'] = Float(m['drawer_thickness'] || Kabinet::Constants::DEFAULT_DOOR_THICKNESS_MM)
            out['body_thickness']  = Float(m['body_thickness'] || Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM)
            out['back_thickness']  = Float(m['back_thickness'] || Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM)
            out['has_back']        = m.fetch('has_back', true) ? true : false
            out['material']        = (m['material'] || 'LPM').to_s
            out['door_material']   = (m['door_material'] || out['material']).to_s
            out['handle_type']     = HANDLE_TYPES.include?(m['handle_type'].to_s) ? m['handle_type'].to_s : 'none'
            out['handle_hole_mm']  = Integer(m['handle_hole_mm'] || Kabinet::Constants::DEFAULT_HANDLE_HOLE_MM)
            # 서랍 박스 깊이 상한 — 침대 길이만큼 깊은 서랍은 실물 불가
            out['box_depth_mm']    = Float(m['box_depth_mm'] || 600)
            # 서랍 위치: foot(발치, 기본) / left / right (측면 — 타워 깊이 밖 노출 구간)
            out['drawer_side']     = BED_DRAWER_SIDES.include?(m['drawer_side'].to_s) ? m['drawer_side'].to_s : 'foot'
            # 리프트업 수납: 상판(매트리스 받침)을 발치/헤드 반으로 나눠
            # 발치 쪽 절반이 가스쇼바로 열리는 수납 구조
            out['lift_up_storage'] = m['lift_up_storage'] ? true : false
          end
          return out
        end

        # 수직 빈 공간 (stack 전용) — 책상 위 개방부 등. 높이만 차지.
        if kind == 'v_gap'
          return { 'kind'   => 'v_gap',
                   'height' => Float(m['height'] || 500),
                   'label'  => (m['label'] || '개방 공간').to_s }
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
          'width'            => Float(m['width']  || 0),
          'depth'            => Float(m['depth']  || 0),
          'height'           => Float(m['height'] || 0),
          'body_thickness'   => Float(m['body_thickness'] || Kabinet::Constants::DEFAULT_BODY_THICKNESS_MM),
          'back_thickness'   => Float(m['back_thickness'] || Kabinet::Constants::DEFAULT_BACK_THICKNESS_MM),
          'has_back'         => m.fetch('has_back', true) ? true : false,
          'material'         => (m['material'] || 'LPM').to_s,
          'handle_type'      => (m['handle_type'] || 'none').to_s,
          'handle_hole_mm'   => Integer(m['handle_hole_mm'] || Kabinet::Constants::DEFAULT_HANDLE_HOLE_MM),
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
          # 도어 측면 갭: 기본 2mm (인접 모듈/벽과의 간섭 방지). 0 = 플러시.
          out['door_side_gap_mm']   = Float(m['door_side_gap_mm'] || Kabinet::Constants::DOOR_GAP_OUTSIDE_MM)
          # 단문(single) 힌지 위치 — 도면 개폐 방향 표시용. 양개(pair)는 항상
          # 바깥쪽(외측) 힌지라 자동 결정되므로 이 값을 쓰지 않는다.
          out['door_hinge_side'] = %w[left right].include?(m['door_hinge_side'].to_s) ? m['door_hinge_side'].to_s : 'left'
          # 측판 생략 옵션 (속장 적층 시 EP 또는 인접 모듈이 측벽 역할)
          out['suppress_left_side']  = m.fetch('suppress_left_side',  false) ? true : false
          out['suppress_right_side'] = m.fetch('suppress_right_side', false) ? true : false
          out['shelves']      = (m['shelves'] || []).map { |s|
            { 'height_from_bottom' => Float(s['height_from_bottom'] || 0),
              'thickness'          => Float(s['thickness'] || out['body_thickness']),
              'depth_inset'        => Float(s['depth_inset'] || 20) }
          }
          out['accessories']       = (m['accessories'] || []).map { |a| normalize_accessory(a) }
          out['vertical_dividers'] = (m['vertical_dividers'] || []).map { |d|
            { 'x'         => Float(d['x'] || 0),
              'thickness' => Float(d['thickness'] || out['body_thickness']) }
          }
          out['cell_shelves'] = (m['cell_shelves'] || []).map { |cs|
            { 'cell'              => Integer(cs['cell'] || 0),
              'height_from_bottom'=> Float(cs['height_from_bottom'] || 0),
              'thickness'         => Float(cs['thickness'] || out['body_thickness']),
              'depth_inset'       => Float(cs['depth_inset'] || 0) }
          }
          out['cell_drawers'] = (m['cell_drawers'] || []).map { |cd|
            { 'cell'         => Integer(cd['cell'] || 0),
              'count'        => Integer(cd['count'] || 2),
              'type'         => (cd['type'] || 'undermount').to_s,
              'thickness'    => Float(cd['thickness'] || out['body_thickness']) }
          }

        when 'drawer_module'
          out['drawer_count']     = Integer(m['drawer_count'] || 1)
          # 서랍 박스 깊이 직접 지정 (0/빈값이면 레일 규격 자동 스냅)
          bd = m['box_depth_mm'].to_f
          out['box_depth_mm']     = bd > 0 ? bd : nil
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
        run_mode = spec['run_mode'] ? true : false
        spec['modules'].each_with_index do |m, i|
          if m['kind'] == 'bed_gap'
            # bed_gap은 폭만 있는 마커라 height/depth가 없다. run_mode 밖에서는
            # Assembly#do_stack이 m['depth']/height를 그대로 사용해 nil.mm로
            # 크래시하므로(UI가 침대공간 버튼을 런 모드로 제한하지 않음) 여기서 차단.
            raise ValidationError,
                  "module[#{i}]: bed_gap 모듈은 수평 런 모드에서만 사용할 수 있습니다." unless run_mode
            if m['storage']
              raise ValidationError, "module[#{i}]: 수납침대 플랫폼 높이는 0보다 커야 합니다." unless m['platform_height'].to_f > 0
              raise ValidationError, "module[#{i}]: 수납침대 깊이(침대 길이)는 0보다 커야 합니다." unless m['bed_depth'].to_f > 0
            end
            next  # bed_gap has no height/depth
          end
          if m['kind'] == 'v_gap'
            raise ValidationError,
                  "module[#{i}]: v_gap(개방 공간)은 적층 모드에서만 사용할 수 있습니다." if run_mode
            raise ValidationError, "module[#{i}] v_gap height must be > 0" unless m['height'].to_f > 0
            next  # v_gap has no depth
          end
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
