require 'json'
# 도면 시트(DXF) 기능의 SketchUp 연결부 — 설정은 모델 attribute dictionary 에 저장.
# 계산은 전부 Kabinet::Output::Sheet(순수 Ruby)에 있고, 여기서는 모델 읽기/쓰기·이미지 내보내기만 한다.
module Kabinet
  module UI
    module SheetBridge
      DICT = 'kabinet_sheet'.freeze
      KEY  = 'config_json'.freeze
      IMAGE_EXTS = %w[.jpg .jpeg .png].freeze

      module_function

      def sheet
        Kabinet::Output::Sheet
      end

      def text
        Kabinet::Output::Sheet::Text
      end

      # 외부에서 온 문자열(openpanel/Dir/File 결과 등)을 UTF-8 로
      def utf8(value)
        text.utf8(value)
      end

      # JS 로 보낼 JSON — 모든 문자열 UTF-8 정규화
      def js(obj)
        JSON.generate(text.deep_utf8(obj))
      end

      # 콜백 공통 처리: 어떤 동작에서 실패했는지 포함해 UI 에 표시하고 루비 콘솔에 backtrace 를 남긴다.
      # 반환: 블록 결과 또는 nil(실패)
      def guard(dialog, action)
        yield
      rescue StandardError, NotImplementedError => e
        begin
          puts "[Kabinet 도면 시트] #{utf8(action)} 실패: #{e.class}: #{utf8(e.message)}"
          puts((e.backtrace || []).first(20).map { |l| '  ' + utf8(l) }.join("\n"))
        rescue StandardError
          nil
        end
        dialog.execute_script("kabinet.onError(#{js("#{action} 실패 — #{e.class}: #{utf8(e.message)}")})")
        nil
      end

      # addImages 호출 스크립트
      def add_images_script(page_id, paths, caption = nil)
        args = [utf8(page_id), paths.map { |p| utf8(p) }]
        args << utf8(caption) if caption
        "kabinetSheet.addImages(#{args.map { |a| JSON.generate(a) }.join(', ')})"
      end

      # 저장된 구성(없으면 기본값). 항상 정규화해서 반환.
      def load_config(model)
        raw = utf8(model.get_attribute(DICT, KEY))
        cfg = raw.empty? ? {} : (JSON.parse(raw) rescue {})
        sheet::Builder.normalize_config(cfg)
      end

      def save_config(model, cfg)
        cfg = sheet::Builder.normalize_config(cfg)
        model.set_attribute(DICT, KEY, JSON.generate(cfg))
        cfg
      end

      # 선택한 가구(없으면 모델 안 마지막 Kabinet 가구)의 spec → 시트 모델. 없으면 nil.
      def model_data(model, furniture_name: nil)
        grp = Kabinet::Persistence::Attributes.find_assembly_in_selection(model) ||
              Kabinet::Persistence::Attributes.find_all_assemblies(model).last
        return nil unless grp
        spec = Kabinet::Persistence::Attributes.read_assembly_spec(grp)
        return nil unless spec
        data_from_spec(spec, furniture_name: furniture_name)
      end

      def data_from_spec(spec, furniture_name: nil)
        norm = Kabinet::Persistence::Schema.normalize(spec)
        sheet::Model.from_spec(norm, furniture_name: furniture_name)
      end

      # 가구가 없을 때 쓰는 자리표시 모델(틀 확인용)
      def placeholder_model
        sheet::Model.normalize('furniture_name' => '가구명',
                               'overall' => { 'W' => 1800, 'H' => 2300, 'D' => 600, 'kick' => 60 }, 'ep' => { 'left' => true, 'right' => true },
                               'modules' => [{ 'name' => 'M1', 'z' => 60, 'w' => 900, 'h' => 2240, 'type' => 'doors', 'doors' => 2, 'shelves' => [900, 1500] },
                                             { 'name' => 'M2', 'x' => 900, 'z' => 60, 'w' => 900, 'h' => 2240, 'type' => 'drawers', 'drawers' => 4 }])
      end

      # UI 에 보여줄 요약
      def summary(model)
        data = model_data(model)
        { has_furniture: !data.nil?, name: data && utf8(data['furniture_name']), size: data && sheet::Model.summary(data) }
      rescue StandardError => e
        { has_furniture: false, error: e.message }
      end

      # 구성 + 모델 → DXF 파일. 반환: Builder.export 결과
      def export(model, cfg, path, only_ids: nil)
        cfg = text.deep_utf8(cfg)
        data = model_data(model, furniture_name: cfg['furniture_name'].to_s.empty? ? nil : cfg['furniture_name']) || placeholder_model
        sheet::Builder.export(cfg, data, path, only_ids: only_ids)
      end

      # 모델 장면 이름 목록
      def scene_names(model)
        model.pages.to_a.map { |pg| utf8(pg.name) }
      rescue StandardError
        []
      end

      # 이미지를 보관할 폴더(UTF-8): 저장된 모델이면 모델 옆 kabinet_sheet_images/, 아니면 임시 폴더
      def images_dir(model)
        require 'tmpdir'
        mp = model.path.to_s
        base = mp.empty? ? Dir.tmpdir : File.dirname(mp)
        text.join(base, 'kabinet_sheet_images')
      end

      # 현재 시점 또는 장면(scene_index)을 PNG 로 저장 — view.write_image 사용(실기 확인 항목)
      # 반환: UTF-8 파일 경로
      def capture(model, scene_index: -1, width: 1600, height: nil)
        require 'fileutils'
        dir = images_dir(model)
        FileUtils.mkdir_p(text.resolve_path(dir).then { |d| File.exist?(d) ? d : text.native(dir, model.path.to_s) })
        view = model.active_view
        prev = nil
        label = '현재시점'
        if scene_index.to_i >= 0
          pg = model.pages[scene_index.to_i]
          raise "장면 #{scene_index}를 찾을 수 없습니다." unless pg
          prev = model.pages.selected_page
          model.pages.selected_page = pg
          label = utf8(pg.name)
        end
        view.refresh
        w = width.to_i > 0 ? width.to_i : 1600
        h = height.to_i > 0 ? height.to_i : (w * view.vpheight.to_f / [view.vpwidth.to_f, 1.0].max).round
        name = "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{text.safe_name(label)}.png"
        path = text.join(dir, name)                       # SketchUp API 에는 UTF-8 경로
        ok = view.write_image(filename: path, width: w, height: [h, 1].max, antialias: true, transparent: false)
        raise '이미지를 저장하지 못했습니다(view.write_image 실패).' unless ok && File.file?(text.resolve_path(path))
        path
      ensure
        model.pages.selected_page = prev if prev
      end

      def image_file?(path)
        IMAGE_EXTS.include?(File.extname(path.to_s).downcase)
      end

      # 폴더 안 이미지(이름순)
      def images_in(dir)
        real = text.resolve_path(dir)
        Dir.children(real).map { |f| utf8(f) }.select { |f| image_file?(f) }.sort.map { |f| text.join(dir, f) }
      end
    end
  end
end
