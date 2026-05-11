module Kabinet
  module Commands
    module Export
      module_function

      # Full drawing export pipeline for the selected assembly.
      # views: array of symbols :front, :right, :left, :top, :section
      # output_dir: nil → prompt user with UI.savepanel
      def run(views: %i[front right top section], output_dir: nil,
              model: Sketchup.active_model)
        target = Kabinet::Persistence::Attributes.find_assembly_in_selection(model)
        unless target
          UI.messagebox('Kabinet: 선택된 어셈블리 그룹이 없습니다. 캐비닛 그룹을 선택하세요.')
          return
        end

        spec  = Kabinet::Persistence::Attributes.read_assembly_spec(target)
        aname = spec ? spec['name'] : 'kabinet'

        dir = output_dir || UI.savepanel('저장 폴더 선택 (파일명 무시)', Dir.home, 'ignore.pdf')
        return unless dir
        dir = File.dirname(dir) if File.extname(dir) != ''
        FileUtils.mkdir_p(dir)

        # 1. Create pages + draw dimensions
        page_names = Kabinet::Output::Views.generate(target, views: views,
                                                     draw_dimensions: true, model: model)

        # 2. Export PNGs
        png_paths = Kabinet::Output::PngExport.export_pages(page_names, output_dir: dir,
                                                            assembly_name: aname, model: model)

        # 3. Bundle into PDF
        if png_paths.any?
          ts = Time.now.strftime('%Y%m%d_%H%M%S')
          pdf_path = File.join(dir, "#{sanitize(aname)}_drawings_#{ts}.pdf")
          Kabinet::Output::PdfBundler.bundle(png_paths, output_path: pdf_path)
          UI.messagebox("도면 출력 완료!\n\n저장 위치: #{dir}\n\n" \
                        "PNG #{png_paths.size}개 + PDF 1개 생성됨.\n\n#{pdf_path}")
        else
          UI.messagebox('Kabinet: PNG 생성에 실패했습니다. 루비 콘솔을 확인하세요.')
        end

        png_paths
      end

      def sanitize(str)
        str.to_s.gsub(/[\\\/\:\*\?\"\<\>\|]/, '_').strip
      end
    end
  end
end

require 'fileutils'
