module Kabinet
  module Output
    module PngExport
      module_function

      DEFAULT_WIDTH  = 2480  # roughly A4 at 300dpi landscape
      DEFAULT_HEIGHT = 1754

      # Export each page as JPEG (PDF 임베드 호환) and also PNG (뷰어용).
      # Returns array of JPEG file paths (used by PdfBundler).
      def export_pages(page_names, output_dir:, assembly_name:, width: DEFAULT_WIDTH,
                       height: DEFAULT_HEIGHT, model: Sketchup.active_model)
        paths = []
        ts = timestamp
        page_names.each do |page_name|
          page = model.pages.find { |p| p.name == page_name }
          next unless page

          model.pages.selected_page = page
          model.active_view.zoom_extents
          model.active_view.invalidate

          base = "#{sanitize(assembly_name)}_#{sanitize(page_name)}_#{ts}"

          # ① JPEG — PDF 임베드용
          jpg_path = File.join(output_dir, "#{base}.jpg")
          model.active_view.write_image(
            filename: jpg_path, width: width, height: height,
            antialias: true, transparent: false
          )

          # ② PNG — 고품질 뷰어용 (선택)
          png_path = File.join(output_dir, "#{base}.png")
          model.active_view.write_image(
            filename: png_path, width: width, height: height,
            antialias: true, transparent: false
          )

          paths << jpg_path if File.exist?(jpg_path)
        end
        paths
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
