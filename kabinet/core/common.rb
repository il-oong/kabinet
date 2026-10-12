module Kabinet
  module Core
    # ── 가구 공통사항 (프로젝트 전체 파라미터) ────────────────────────────────
    #
    # 몸통·뒷판·도어·선반 두께, 소재, 도어 소재, 손잡이, EP 두께를 한 곳에서 정하고
    # 모든 Kabinet 가구 스펙에 덮어쓴다. 빈 값(nil/'')인 항목은 각 가구 값을 그대로 둔다.
    # 웹 창(app.js applyCommon)과 같은 규칙 — 두 곳을 함께 고칠 것.
    module Common
      module_function

      KEYS = %w[material door_material body_thickness back_thickness door_thickness
                shelf_thickness ep_thickness handle_type].freeze
      NUMERIC = %w[body_thickness back_thickness door_thickness shelf_thickness ep_thickness].freeze
      CASE_KINDS = %w[shelf_module drawer_module].freeze

      # 사용자가 입력한 공통값 → 쓸 수 있는 값만 남긴 해시
      def clean(common)
        (common || {}).each_with_object({}) do |(k, v), out|
          k = k.to_s
          next unless KEYS.include?(k)
          next if v.nil? || v.to_s.strip.empty?
          if NUMERIC.include?(k)
            f = Float(v) rescue nil
            out[k] = f if f && f > 0 && f <= 100
          else
            out[k] = v.to_s.strip
          end
        end
      end

      # spec(Hash, 문자열 키)에 공통값을 적용한 새 스펙
      def apply(spec, common)
        c = clean(common)
        s = Marshal.load(Marshal.dump(spec))
        return s if c.empty?

        s['material'] = c['material'] if c['material']
        if c['ep_thickness']
          s['ep'] = (s['ep'] || {}).merge('thickness' => c['ep_thickness'])
        end
        (s['modules'] || []).each do |m|
          kind = m['kind'].to_s
          m['material'] = c['material'] if c['material'] && kind != 'bed_gap' && kind != 'v_gap'
          next unless CASE_KINDS.include?(kind)

          m['door_material'] = c['door_material'] if c['door_material']
          m['body_thickness'] = c['body_thickness'] if c['body_thickness']
          m['back_thickness'] = c['back_thickness'] if c['back_thickness']
          m['handle_type'] = c['handle_type'] if c['handle_type']
          if c['door_thickness']
            m['door_thickness'] = c['door_thickness'] if kind == 'shelf_module'
            m['drawer_thickness'] = c['door_thickness'] if kind == 'drawer_module' || m.key?('drawer_thickness')
          end
          next unless c['shelf_thickness']

          %w[shelves cell_shelves vertical_dividers].each do |key|
            (m[key] || []).each { |p| p['thickness'] = c['shelf_thickness'] if p.is_a?(Hash) }
          end
        end
        s
      end
    end
  end
end
