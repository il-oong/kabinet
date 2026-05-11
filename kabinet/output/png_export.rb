module Kabinet
  module Output
    module PngExport
      module_function

      DEFAULT_WIDTH  = 2480  # roughly A4 at 300dpi landscape
      DEFAULT_HEIGHT = 1754

      # Export each of the given page names as PNG into output_dir.
      # Returns array of exported file paths.
      def export_pages(page_names, output_dir:, assembly_name:, width: DEFAULT_WIDTH,
                       height: DEFAULT_HEIGHT, model: Sketchup.active_model)
        paths = []
        page_names.each do |page_name|
          page = model.pages.find { |p| p.name == page_name }
          next unless page

          model.pages.selected_page = page
          model.active_view.zoom_extents
          model.active_view.invalidate

          safe_name = page_name.gsub(/[^\wÀ-ɏ가-힣\s\-_]/, '_').strip
          filename = "#{sanitize(assembly_name)}_#{safe_name}_#{timestamp}.png"
          path = File.join(output_dir, filename)

          opts = {
            filename:   path,
            width:      width,
            height:     height,
            antialias:  true,
            transparent: false,
            compression: 0
          }

          result = model.active_view.write_image(opts)
          paths << path if result
        end
        paths
      end

      def sanitize(str)
        str.to_s.gsub(/[\\\/\:\*\?\"\<\>\|]/, '_').strip
      end

      def timestamp
        Time.now.strftime('%Y%m%d_%H%M%S')
      end
    end
  end
end
