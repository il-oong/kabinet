# Pure-Ruby minimal PDF writer — bundles JPEG images into a multi-page PDF.
# JPEG can be embedded directly with /DCTDecode (no pixel extraction needed).
# No external gem required.
module Kabinet
  module Output
    module PdfBundler
      module_function

      # jpeg_paths: ordered array of .jpg file paths
      # output_path: destination .pdf file path
      # page_size: :a4_landscape | :a4_portrait | [width_pt, height_pt]
      def bundle(jpeg_paths, output_path:, page_size: :a4_landscape)
        pw, ph = resolve_page_size(page_size)

        obj_counter = 0
        alloc = -> { obj_counter += 1; obj_counter }

        catalog_id = alloc.call
        pages_id   = alloc.call

        page_ids = []
        objects  = {}   # id => { dict:, stream: }

        jpeg_paths.each do |path|
          next unless File.exist?(path)

          jpeg_data = File.binread(path)
          w, h = jpeg_dimensions(jpeg_data)
          next if w == 0 || h == 0

          # Fit image into page with 36pt margins
          margin = 36.0
          max_w  = pw - 2 * margin
          max_h  = ph - 2 * margin
          scale  = [max_w / w, max_h / h].min
          iw     = (w * scale).round(2)
          ih     = (h * scale).round(2)
          ix     = (margin + (max_w - iw) / 2.0).round(2)
          iy     = (margin + (max_h - ih) / 2.0).round(2)

          img_id = alloc.call
          objects[img_id] = {
            dict:   "<< /Type /XObject /Subtype /Image " \
                    "/Width #{w} /Height #{h} " \
                    "/ColorSpace /DeviceRGB /BitsPerComponent 8 " \
                    "/Filter /DCTDecode /Length #{jpeg_data.bytesize} >>",
            stream: jpeg_data
          }

          content = "q\n#{iw} 0 0 #{ih} #{ix} #{iy} cm\n/Im#{img_id} Do\nQ\n"
          cnt_id  = alloc.call
          objects[cnt_id] = {
            dict:   "<< /Length #{content.bytesize} >>",
            stream: content.b
          }

          page_id = alloc.call
          page_ids << page_id
          objects[page_id] = {
            dict: "<< /Type /Page /Parent #{pages_id} 0 R " \
                  "/MediaBox [0 0 #{pw} #{ph}] " \
                  "/Contents #{cnt_id} 0 R " \
                  "/Resources << /XObject << /Im#{img_id} #{img_id} 0 R >> >> >>",
            stream: nil
          }
        end

        # If no images, write a blank page so PDF is still valid
        if page_ids.empty?
          page_id = alloc.call
          page_ids << page_id
          objects[page_id] = {
            dict: "<< /Type /Page /Parent #{pages_id} 0 R " \
                  "/MediaBox [0 0 #{pw} #{ph}] >>",
            stream: nil
          }
        end

        objects[pages_id] = {
          dict:   "<< /Type /Pages " \
                  "/Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] " \
                  "/Count #{page_ids.size} >>",
          stream: nil
        }
        objects[catalog_id] = {
          dict:   "<< /Type /Catalog /Pages #{pages_id} 0 R >>",
          stream: nil
        }

        # ── Serialize ──────────────────────────────────────────────────
        buf = ''.b
        buf << "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

        offsets = {}
        (1..obj_counter).each do |id|
          obj = objects[id]
          next unless obj
          offsets[id] = buf.bytesize
          buf << "#{id} 0 obj\n#{obj[:dict]}\n"
          if obj[:stream]
            buf << "stream\n"
            buf << obj[:stream]
            buf << "\nendstream\n"
          end
          buf << "endobj\n"
        end

        xref_offset = buf.bytesize
        buf << "xref\n0 #{obj_counter + 1}\n"
        buf << "0000000000 65535 f \n"
        (1..obj_counter).each do |id|
          buf << format('%010d 00000 n ', offsets[id] || 0) + "\n"
        end
        buf << "trailer\n<< /Size #{obj_counter + 1} /Root #{catalog_id} 0 R >>\n"
        buf << "startxref\n#{xref_offset}\n%%EOF\n"

        File.open(output_path, 'wb') { |f| f.write(buf) }
        output_path
      end

      # ── Helpers ────────────────────────────────────────────────────────

      def resolve_page_size(size)
        case size
        when :a4_landscape then [841, 595]
        when :a4_portrait  then [595, 841]
        when Array         then size
        else [841, 595]
        end
      end

      # Parse JPEG SOF marker to get image width/height.
      def jpeg_dimensions(data)
        i = 2  # skip SOI (FF D8)
        while i + 4 <= data.bytesize
          # Find next marker
          i += 1 and next unless data.getbyte(i) == 0xFF
          marker = data[i, 2].unpack1('n')
          i += 2
          # Skip non-length markers
          next if [0xFF01, 0xFFD0, 0xFFD1, 0xFFD2, 0xFFD3,
                   0xFFD4, 0xFFD5, 0xFFD6, 0xFFD7, 0xFFD9].include?(marker)
          break if i + 2 > data.bytesize
          seg_len = data[i, 2].unpack1('n')
          # SOF markers carry image dimensions
          if (0xFFC0..0xFFCF).cover?(marker) &&
             marker != 0xFFC4 && marker != 0xFFC8 && marker != 0xFFCC
            break if i + 7 > data.bytesize
            h = data[i + 3, 2].unpack1('n')
            w = data[i + 5, 2].unpack1('n')
            return [w, h]
          end
          i += seg_len
        end
        [0, 0]
      end
    end
  end
end
