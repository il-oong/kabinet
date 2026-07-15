module Kabinet
  module Output
    module PngExport
      module_function

      DEFAULT_WIDTH  = 2480  # roughly A4 at 300dpi landscape
      DEFAULT_HEIGHT = 1754

      # Export each scene page as JPEG (PDF embed) + PNG (viewer use).
      #
      # page_infos: array of { name:, label:, view: } hashes — from Views.generate
      # Returns array of { jpg_path:, png_path:, label: } hashes (used by PdfBundler).
      def export_pages(page_infos, output_dir:, assembly_name:, width: DEFAULT_WIDTH,
                       height: DEFAULT_HEIGHT, model: Sketchup.active_model)
        results = []
        ts = timestamp

        page_infos.each do |info|
          page_name = info[:name] || info['name']
          label     = info[:label] || info['label'] || page_name

          page = model.pages.find { |p| p.name == page_name }
          next unless page

          # ── 페이지 활성화 — 전환 애니메이션 제거 후 즉시 이동
          # (기존 버그: 기본 전환 애니메이션 도중 write_image가 실행되어
          #  중간 프레임이 캡처되거나 빈 이미지가 나왔음)
          page.transition_time = 0 if page.respond_to?(:transition_time=)
          model.pages.selected_page = page
          # 카메라를 페이지 저장값으로 직접 재적용 (전환 상태와 무관하게 확정)
          model.active_view.camera = page.camera if page.camera

          # ── 렌더링 스타일 강제 적용 (Hidden Line — 2D 도면)
          apply_drawing_style(model)

          model.active_view.zoom_extents
          model.active_view.invalidate

          base = "#{sanitize(assembly_name)}_#{sanitize(label)}_#{ts}"

          # ① JPEG — PDF 임베드용
          jpg_path = File.join(output_dir, "#{base}.jpg")
          write_image(model, jpg_path, width, height)

          # ② PNG — 고품질 뷰어용
          png_path = File.join(output_dir, "#{base}.png")
          write_image(model, png_path, width, height)

          results << { jpg_path: jpg_path, png_path: png_path, label: label } if File.exist?(jpg_path)
        end

        results
      end

      # ── Private helpers ────────────────────────────────────────────────

      def apply_drawing_style(model)
        opts = model.rendering_options
        opts['RenderMode']       = 1      # Hidden Line
        opts['DrawEdges']        = true
        opts['DrawFaces']        = true
        opts['DrawHorizon']      = false
        opts['Shadows']          = false
        opts['FogOn']            = false
        opts['BackgroundColor']  = Sketchup::Color.new(255, 255, 255) rescue nil
        opts['GroundColor']      = Sketchup::Color.new(255, 255, 255) rescue nil
        opts['SkyColor']         = Sketchup::Color.new(255, 255, 255) rescue nil
      rescue StandardError
        nil
      end

      def write_image(model, path, width, height)
        model.active_view.write_image(
          filename:    path,
          width:       width,
          height:      height,
          antialias:   true,
          transparent: false
        )
      rescue StandardError => e
        # 실패를 조용히 삼키지 않는다 — "항상 안 되는" 증상의 원인 은폐 방지
        puts "Kabinet write_image 실패 (#{File.basename(path)}): #{e.class}: #{e.message}"
        nil
      end

      def sanitize(str)
        str.to_s.gsub(/[\\\/\:\*\?\"\<\>\|\[\]\s]/, '_').strip
      end

      def timestamp
        Time.now.strftime('%Y%m%d_%H%M%S')
      end
    end
  end
end
