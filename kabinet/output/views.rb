module Kabinet
  module Output
    module Views
      VIEW_DEFS = {
        front:   { name: '정면도',   label: 'FRONT ELEVATION',       eye_dir: [0, -1, 0], up: [0, 0, 1] },
        right:   { name: '우측면도', label: 'RIGHT SIDE ELEVATION',  eye_dir: [1,  0, 0], up: [0, 0, 1] },
        left:    { name: '좌측면도', label: 'LEFT SIDE ELEVATION',   eye_dir: [-1, 0, 0], up: [0, 0, 1] },
        top:     { name: '평면도',   label: 'PLAN VIEW',             eye_dir: [0,  0, -1], up: [0, 1, 0] },
        section: { name: '단면도',   label: 'SECTION (MID-DEPTH)',   eye_dir: [0, -1, 0], up: [0, 0, 1] }
      }.freeze

      # 2D 도면 렌더링 옵션 (Hidden Line — 흰 면 + 검은 엣지)
      DRAWING_OPTS = {
        'RenderMode'      => 1,    # 1 = Hidden Line
        'DrawEdges'       => true,
        'DrawFaces'       => true,
        'DrawHorizon'     => false,
        'Shadows'         => false,
        'FogOn'           => false,
      }.freeze

      module_function

      # Generate SketchUp scenes for the listed views + draw dimensions.
      # Returns: array of { name:, label: } hashes (used by PngExport).
      def generate(assembly_group, views: %i[front right top section],
                   draw_dimensions: true, model: Sketchup.active_model)
        bb     = assembly_group.bounds
        center = bb.center
        span   = [bb.width, bb.depth, bb.height].max * 2.5

        # Save original rendering state before we touch it
        saved_opts = save_rendering_opts(model)

        results = []
        model.start_operation('Kabinet — 도면 장면 생성', true)
        begin
          # 이전 Kabinet 치수선/단면 평면 모두 제거 (중복·누적 방지)
          Output::Dimensions.clear_kabinet_dimensions(model)
          erase_kabinet_section_planes(model)

          # 치수선을 뷰별 태그로 먼저 모두 그려둔다 (뷰마다 자기 것만 표시)
          if draw_dimensions
            views.each do |view_key|
              next unless VIEW_DEFS[view_key]
              Output::Dimensions.draw_for_assembly(assembly_group, view_key, model: model)
            end
          end

          views.each do |view_key|
            defn = VIEW_DEFS[view_key]
            next unless defn

            # 페이지(씬) 생성 또는 기존 것 재사용
            page = find_or_create_page(model, "[Kabinet] #{defn[:name]}")
            page.transition_time = 0 if page.respond_to?(:transition_time=)

            # ★ 순서 중요 (기존 버그의 원인):
            #   selected_page= 는 페이지에 '저장된' 카메라로 뷰를 되돌리므로
            #   반드시 페이지 선택 → 카메라 설정 → page.update 순서여야 한다.
            #   (기존 코드는 카메라 설정 후 selected_page= 를 호출해
            #    기본 3D 카메라가 씬에 저장됐음)
            model.pages.selected_page = page

            # 2D 도면 스타일 적용
            apply_drawing_style(model)

            # 단면 평면 처리
            if view_key == :section
              add_section_plane(assembly_group, model)
            else
              deactivate_section_planes(model)
            end

            # 이 뷰의 치수 태그만 표시
            Output::Dimensions.show_only(model, view_key) if draw_dimensions

            # 카메라 설정 (평행 투영) — zoom_extents는 표시 중인 엔티티 기준
            setup_camera(model.active_view, center, span, defn)
            model.active_view.zoom_extents
            model.active_view.invalidate

            # 씬 저장 (카메라=1, 렌더=2, 그림자=4, 레이어=32, 스타일=64, 단면=128)
            page.update(1 | 2 | 4 | 32 | 64 | 128)

            results << { name: page.name, label: defn[:label], view: view_key }
          end

          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          raise
        ensure
          # 원래 렌더링 복원
          restore_rendering_opts(model, saved_opts)
          Output::Dimensions.hide_all(model) if draw_dimensions
        end

        results
      end

      # ── 2D 도면 스타일 적용 ──────────────────────────────────────────────
      def apply_drawing_style(model)
        opts = model.rendering_options
        DRAWING_OPTS.each { |k, v| opts[k] = v rescue nil }
        # 배경 흰색 강제 (도면 배경)
        opts['BackgroundColor'] = Sketchup::Color.new(255, 255, 255) rescue nil
        opts['GroundColor']     = Sketchup::Color.new(255, 255, 255) rescue nil
        opts['SkyColor']        = Sketchup::Color.new(255, 255, 255) rescue nil
      rescue StandardError
        nil  # best-effort
      end

      def save_rendering_opts(model)
        keys = %w[RenderMode DrawEdges DrawFaces DrawHorizon Shadows FogOn
                  BackgroundColor GroundColor SkyColor]
        keys.each_with_object({}) do |k, h|
          h[k] = model.rendering_options[k] rescue nil
        end
      end

      def restore_rendering_opts(model, saved)
        saved.each { |k, v| model.rendering_options[k] = v rescue nil }
      rescue StandardError
        nil
      end

      # ── 카메라 (평행 투영) ───────────────────────────────────────────────
      def setup_camera(view, center, span, defn)
        eye_dir = ::Geom::Vector3d.new(*defn[:eye_dir])
        up_vec  = ::Geom::Vector3d.new(*defn[:up])
        eye     = center.offset(eye_dir, span)
        cam = Sketchup::Camera.new(eye, center, up_vec)
        cam.perspective = false
        view.camera = cam
        view.zoom_extents
      end

      def find_or_create_page(model, name)
        model.pages.find { |p| p.name == name } || model.pages.add(name)
      end

      # ── 단면 평면 (Y축 중간 수직 절단) ──────────────────────────────────
      # 정면도 기준에서 깊이(Y) 절반 위치에 수직으로 잘라 단면 생성.
      # 단면 평면의 법선 = +Y 방향 (앞→뒤).
      # SketchUp 단면 평면은 로컬 Z 축이 법선 → X축 기준 -90° 회전 필요.
      def add_section_plane(assembly_group, model)
        deactivate_section_planes(model)
        bb        = assembly_group.bounds
        mid_y     = (bb.min.y + bb.max.y) / 2.0
        origin    = ::Geom::Point3d.new(bb.center.x, mid_y, bb.center.z)
        # 법선을 +Y 방향으로 만들기: 기본 Z법선을 X축 기준 -90° 회전
        t = ::Geom::Transformation.rotation(
          origin,
          ::Geom::Vector3d.new(1, 0, 0),
          -90.degrees
        )
        sp = model.entities.add_section_plane(t)
        if sp
          # Kabinet 소유 표시 — 다음 생성 시 지워서 누적을 막는다
          Kabinet::Persistence::Attributes.set(sp, 'kabinet_section', true)
          sp.activate
        end
        sp
      rescue StandardError
        nil
      end

      def deactivate_section_planes(model)
        model.entities.grep(Sketchup::SectionPlane).each { |sp| sp.deactivate rescue nil }
      end

      # 기존 버그: 단면 평면을 deactivate만 하고 지우지 않아 출력할 때마다
      # 모델에 계속 쌓였음. Kabinet이 만든 것만 골라 제거.
      def erase_kabinet_section_planes(model)
        planes = model.entities.grep(Sketchup::SectionPlane).select do |sp|
          Kabinet::Persistence::Attributes.get(sp, 'kabinet_section')
        end
        model.entities.erase_entities(planes) unless planes.empty?
      rescue StandardError
        nil
      end
    end
  end
end
