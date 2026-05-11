# Pure-Ruby minimal PDF writer.
# Bundles an ordered list of PNG image files into a single multi-page PDF.
# No external gem required — writes image-only pages with /FlateDecode or raw streams.
# Spec compliant for PDF 1.4 (image-only pages, no fonts, no text layer).
module Kabinet
  module Output
    module PdfBundler
      module_function

      # png_paths: ordered array of File paths to PNG images.
      # output_path: where to write the .pdf
      # page_size: :a4_landscape (default) or [width_pt, height_pt]
      def bundle(png_paths, output_path:, page_size: :a4_landscape)
        pw, ph = resolve_page_size(page_size)
        objects = []      # array of [obj_id, stream_or_nil, dict_string]
        offsets = {}      # obj_id => byte offset

        obj_id = 0
        next_id = -> { obj_id += 1 }

        catalog_id = next_id.call
        pages_id   = next_id.call

        page_ids  = []
        image_ids = []

        png_paths.each_with_index do |path, _i|
          png_data = File.binread(path)
          w, h = png_dimensions(png_data)
          img_id  = next_id.call
          image_ids << img_id
          # Scale image to fit page with margins (36pt = 0.5in each side)
          margin = 36
          max_w  = pw - 2 * margin
          max_h  = ph - 2 * margin
          scale  = [max_w.to_f / w, max_h.to_f / h].min
          iw = (w * scale).round
          ih = (h * scale).round
          ix = margin + (max_w - iw) / 2.0
          iy = margin + (max_h - ih) / 2.0

          page_id = next_id.call
          page_ids << page_id

          # image XObject
          objects << [img_id, png_data,
                      "<< /Type /XObject /Subtype /Image " \
                      "/Width #{w} /Height #{h} " \
                      "/ColorSpace /DeviceRGB /BitsPerComponent 8 " \
                      "/Filter /FlateDecode " \
                      "/Length #{png_data.bytesize} >>"]

          # page content stream
          content = "q\n#{iw} 0 0 #{ih} #{ix.round(2)} #{iy.round(2)} cm\n/Im#{img_id} Do\nQ\n"
          cnt_id = next_id.call
          objects << [cnt_id, content,
                      "<< /Length #{content.bytesize} >>"]

          objects << [page_id, nil,
                      "<< /Type /Page /Parent #{pages_id} 0 R " \
                      "/MediaBox [0 0 #{pw} #{ph}] " \
                      "/Contents #{cnt_id} 0 R " \
                      "/Resources << /XObject << /Im#{img_id} #{img_id} 0 R >> >> >>"]
        end

        objects << [pages_id, nil,
                    "<< /Type /Pages " \
                    "/Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] " \
                    "/Count #{page_ids.size} >>"]
        objects << [catalog_id, nil,
                    "<< /Type /Catalog /Pages #{pages_id} 0 R >>"]

        # Serialize
        buf = String.new(encoding: 'BINARY')
        buf << "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

        objects.sort_by { |id, _, _| id }.each do |obj_id2, stream, dict|
          offsets[obj_id2] = buf.bytesize
          buf << "#{obj_id2} 0 obj\n#{dict}\n"
          if stream
            buf << "stream\n"
            buf << (stream.is_a?(String) ? stream.b : stream)
            buf << "\nendstream\n"
          end
          buf << "endobj\n"
        end

        xref_offset = buf.bytesize
        buf << "xref\n0 #{obj_id + 1}\n"
        buf << "0000000000 65535 f \n"
        (1..obj_id).each do |id|
          off = offsets[id] || 0
          buf << format('%010d 00000 n ', off) + "\n"
        end
        buf << "trailer\n<< /Size #{obj_id + 1} /Root #{catalog_id} 0 R >>\n"
        buf << "startxref\n#{xref_offset}\n%%EOF\n"

        File.open(output_path, 'wb') { |f| f.write(buf) }
        output_path
      end

      def resolve_page_size(size)
        case size
        when :a4_landscape then [841, 595]
        when :a4_portrait  then [595, 841]
        when Array         then size
        else [841, 595]
        end
      end

      # Read PNG width/height from its IHDR chunk (bytes 16..23).
      def png_dimensions(data)
        w = data[16, 4].unpack1('N')
        h = data[20, 4].unpack1('N')
        [w, h]
      end
    end
  end
end
