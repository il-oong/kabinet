module Kabinet
  module Core
    # ── 도어 · 서랍 전판 간격 (가구별/공통사항으로 바꿀 수 있는 값) ─────────────
    #
    # 기본값은 Constants. 가구 스펙의 'door_gaps' 해시가 있으면 그 값을 쓴다.
    # 생성·커트리스트·경고·도면 진입점에서 Gaps.with(spec['door_gaps']) { ... } 로 감싼다.
    #   top / bottom    : 도어 위·아래 간격
    #   outside         : 도어 바깥(벽·측판 쪽) 간격
    #   between         : 도어 사이 간격
    #   front_offset    : 몸통 앞면 ~ 도어 뒷면 간격 (도어 띄움)
    #   drawer_gap      : 서랍 전판 상하/좌우 간격
    #   drawer_between  : 서랍 전판 사이 간격
    module Gaps
      module_function

      KEYS = %w[top bottom outside between front_offset drawer_gap drawer_between].freeze

      def defaults
        c = Kabinet::Constants
        { 'top' => c::DOOR_GAP_TOP_MM, 'bottom' => c::DOOR_GAP_BOTTOM_MM, 'outside' => c::DOOR_GAP_OUTSIDE_MM,
          'between' => c::DOOR_REVEAL_BETWEEN_MM, 'front_offset' => c::DOOR_FRONT_OFFSET_MM,
          'drawer_gap' => c::DRAWER_FRONT_GAP_MM, 'drawer_between' => c::DRAWER_REVEAL_BETWEEN_MM }
      end

      # 숫자만, 0~50mm 범위만 남김
      def clean(h)
        (h || {}).each_with_object({}) do |(k, v), out|
          k = k.to_s
          next unless KEYS.include?(k)
          next if v.nil? || v.to_s.strip.empty?
          f = Float(v) rescue nil
          out[k] = f if f && f >= 0 && f <= 50
        end
      end

      def with(gaps)
        prev = @current
        @current = clean(gaps)
        yield
      ensure
        @current = prev
      end

      def value(key)
        v = @current && @current[key]
        (v.nil? ? defaults[key] : v).to_f
      end

      def top;            value('top'); end
      def bottom;         value('bottom'); end
      def outside;        value('outside'); end
      def between;        value('between'); end
      def front_offset;   value('front_offset'); end
      def drawer_gap;     value('drawer_gap'); end
      def drawer_between; value('drawer_between'); end
    end
  end
end
