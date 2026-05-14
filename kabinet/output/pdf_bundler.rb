# Pure-Ruby minimal PDF writer — bundles JPEG images into a multi-page PDF.
# JPEG can be embedded directly with /DCTDecode (no pixel extraction needed).
# Each page includes a Helvetica title label at the bottom center.
# No external gem required.
module Kabinet
  module Output
    module PdfBundler
      FONT_SIZE  = 18.0    # pt — label at bottom of each page
      MARGIN     = 36.0    # pt — image margin
      LABEL_AREA = 28.0    # pt reserved at bottom for label text

      module_function

      # page_infos: array of { jpg_path:, label: } hashes (from PngExport)
      #   OR plain string paths (backward compat — no label)
      # output_path: destination .pdf file path
      # page_size: :a4_landscape | :a4_portrait | [width_pt, height_pt]
      def bundle(page_infos, output_path:, page_size: :a4_landscape)
        pw, ph = resolve_page_size(page_size)

        obj_counter = 0
        alloc = -> { obj_counter += 1; obj_counter }

        catalog_id = alloc.call
        pages_id   = alloc.call
        font_id    = alloc.call   # shared Helvetica font object

        page_ids = []
        objects  = {}   # id => { dict:, stream: }

        # ── Shared Helvetica Type1 font ──────────────────────────────────
        objects[font_id] = {
          dict:   '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica ' \
                  '/Encoding /WinAnsiEncoding >>',
          stream: nil
        }

        page_infos.each do |info|
          # backward compat: plain string path
          if info.is_a?(String)
            path  = info
            label = ''
          else
            path  = info[:jpg_path] || info[:path] || ''
            label = info[:label].to_s
          end

          next unless File.exist?(path.to_s)

          jpeg_data = File.binread(path)
          w, h = jpeg_dimensions(jpeg_data)
          next if w == 0 || h == 0

          # Image area = full page minus margins and label strip
          img_area_h = ph - 2 * MARGIN - LABEL_AREA
          max_w = pw - 2 * MARGIN
          max_h = [img_area_h, 1.0].max
          scale = [max_w / w, max_h / h].min
          iw    = (w * scale).round(2)
          ih    = (h * scale).round(2)
          ix    = (MARGIN + (max_w - iw) / 2.0).round(2)
          iy    = (MARGIN + LABEL_AREA + (max_h - ih) / 2.0).round(2)

          img_id = alloc.call
          objects[img_id] = {
            dict:   "<< /Type /XObject /Subtype /Image " \
                    "/Width #{w} /Height #{h} " \
                    "/ColorSpace /DeviceRGB /BitsPerComponent 8 " \
                    "/Filter /DCTDecode /Length #{jpeg_data.bytesize} >>",
            stream: jpeg_data
          }

          # ── Page content stream ──────────────────────────────────────
          label_y   = (MARGIN * 0.4).round(2)
          label_x   = (pw / 2.0).round(2)   # centered via text positioning below

          # Escape label for PDF string literal (parens + backslash only)
          safe_label = label.gsub('\\', '\\\\').gsub('(', '\(').gsub(')', '\)')
          # PDF Type1 Helvetica uses WinAnsi → keep ASCII only
          safe_label = safe_label.encode('windows-1252', invalid: :replace, undef: :replace, replace: '?') rescue safe_label

          content_lines = [
            'q',
            "#{iw} 0 0 #{ih} #{ix} #{iy} cm",
            "/Im#{img_id} Do",
            'Q'
          ]

          unless safe_label.empty?
            label_text_w = safe_label.length * FONT_SIZE * 0.55   # rough Helvetica width estimate
            txt_x = ((pw - label_text_w) / 2.0).round(2)
            txt_x = MARGIN if txt_x < MARGIN
            content_lines += [
              'BT',
              "/F1 #{FONT_SIZE} Tf",
              "#{txt_x} #{label_y} Td",
              "(#{safe_label}) Tj",
              'ET'
            ]
          end

          content = content_lines.join("\n") + "\n"
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
                  "/Resources << " \
                    "/XObject << /Im#{img_id} #{img_id} 0 R >> " \
                    "/Font << /F1 #{font_id} 0 R >> " \
                  ">> >>",
            stream: nil
          }
        end

        # Blank page if no images
        if page_ids.empty?
          page_id = alloc.call
          page_ids << page_id
          objects[page_id] = {
            dict: "<< /Type /Page /Parent #{pages_id} 0 R " \
                  "/MediaBox [0 0 #{pw} #{ph}] " \
                  "/Resources << /Font << /F1 #{font_id} 0 R >> >> >>",
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
        buf << "%PDF-1.4\n".b
        buf << "%\xE2\xE3\xCF\xD3\n".b

        offsets = {}
        (1..obj_counter).each do |id|
          obj = objects[id]
          next unless obj
          offsets[id] = buf.bytesize
          buf << "#{id} 0 obj\n#{obj[:dict]}\n".b
          if obj[:stream]
            buf << "stream\n".b
            s = obj[:stream]
            buf << (s.encoding == Encoding::ASCII_8BIT ? s : s.b)
            buf << "\nendstream\n".b
          end
          buf << "endobj\n".b
        end

        xref_offset = buf.bytesize
        buf << "xref\n0 #{obj_counter + 1}\n".b
        buf << "0000000000 65535 f \n".b
        (1..obj_counter).each do |id|
          buf << (format('%010d 00000 n ', offsets[id] || 0) + "\n").b
        end
        buf << "trailer\n<< /Size #{obj_counter + 1} /Root #{catalog_id} 0 R >>\n".b
        buf << "startxref\n#{xref_offset}\n%%EOF\n".b

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
          i += 1 and next unless data.getbyte(i) == 0xFF
          marker = data[i, 2].unpack1('n')
          i += 2
          next if [0xFF01, 0xFFD0, 0xFFD1, 0xFFD2, 0xFFD3,
                   0xFFD4, 0xFFD5, 0xFFD6, 0xFFD7, 0xFFD9].include?(marker)
          break if i + 2 > data.bytesize
          seg_len = data[i, 2].unpack1('n')
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
