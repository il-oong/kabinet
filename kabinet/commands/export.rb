require 'fileutils'

module Kabinet
  module Commands
    module Export
      module_function

      # Full 2D drawing export pipeline for the selected assembly.
      #
      # views:      array of symbols :front, :right, :left, :top, :section
      # output_dir: nil → prompt user with ::UI.savepanel
      #
      # Pipeline:
      #   1. Views.generate   → creates SketchUp scenes in Hidden Line style
      #                         returns [{name:, label:, view:}, ...]
      #   2. PngExport        → activates each scene, writes JPEG + PNG
      #                         returns [{jpg_path:, png_path:, label:}, ...]
      #   3. PdfBundler       → bundles JPEGs into single PDF with labels
      def run(views: %i[front right top section], output_dir: nil,
              model: Sketchup.active_model)
        # ── 대상 어셈블리 ───────────────────────────────────────────────
        target = Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
        unless target
          ::UI.messagebox('Kabinet: 선택된 어셈블리 그룹이 없습니다. 캐비닛 그룹을 선택하세요.')
          return
        end

        spec  = Kabinet::Persistence::Attributes.read_assembly_spec(target)
        aname = (spec && spec['name'] && !spec['name'].strip.empty?) ? spec['name'] : 'kabinet'

        # ── 출력 폴더 선택 ──────────────────────────────────────────────
        dir = output_dir
        unless dir
          chosen = ::UI.savepanel('도면 저장 위치 선택 (파일명 무시)', Dir.home, 'drawings.pdf')
          return unless chosen
          dir = File.extname(chosen) != '' ? File.dirname(chosen) : chosen
        end
        return unless dir
        FileUtils.mkdir_p(dir)

        # ── 1. SketchUp 씬 생성 (Hidden Line 스타일 + 치수선) ──────────
        begin
          page_infos = Kabinet::Output::Views.generate(
            target,
            views:           views,
            draw_dimensions: true,
            model:           model
          )
        rescue StandardError => e
          ::UI.messagebox("Kabinet: 도면 씬 생성 오류\n#{e.message}")
          return
        end

        if page_infos.empty?
          ::UI.messagebox('Kabinet: 생성된 씬이 없습니다.')
          return
        end

        # ── 2. PNG + JPEG 내보내기 ──────────────────────────────────────
        begin
          export_results = Kabinet::Output::PngExport.export_pages(
            page_infos,
            output_dir:    dir,
            assembly_name: aname,
            model:         model
          )
        rescue StandardError => e
          ::UI.messagebox("Kabinet: 이미지 내보내기 오류\n#{e.message}")
          return
        end

        if export_results.empty?
          ::UI.messagebox('Kabinet: PNG/JPEG 생성에 실패했습니다. 루비 콘솔을 확인하세요.')
          return
        end

        # ── 3. PDF 번들링 ───────────────────────────────────────────────
        ts       = Time.now.strftime('%Y%m%d_%H%M%S')
        pdf_path = File.join(dir, "#{sanitize(aname)}_drawings_#{ts}.pdf")

        begin
          # PdfBundler는 { jpg_path:, label: } 형식을 받음
          pdf_inputs = export_results.map { |r| { jpg_path: r[:jpg_path], label: r[:label] } }
          Kabinet::Output::PdfBundler.bundle(pdf_inputs, output_path: pdf_path)
        rescue StandardError => e
          ::UI.messagebox("Kabinet: PDF 생성 오류\n#{e.message}")
          # PNG는 이미 저장됐으니 계속
        end

        # ── 완료 메시지 ─────────────────────────────────────────────────
        png_list = export_results.map { |r| File.basename(r[:png_path]) }.join("\n  ")
        pdf_note = File.exist?(pdf_path) ? "\nPDF: #{File.basename(pdf_path)}" : ''
        ::UI.messagebox(
          "도면 출력 완료!\n\n저장 위치: #{dir}\n\n" \
          "PNG #{export_results.size}개:#{pdf_note}\n  #{png_list}"
        )

        export_results
      end

      def sanitize(str)
        str.to_s.gsub(/[\\\/\:\*\?\"\<\>\|\[\]\s]/, '_').strip
      end
    end
  end
end
