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

      # 저장된 구성(없으면 기본값). 항상 정규화해서 반환.
      def load_config(model)
        raw = model.get_attribute(DICT, KEY)
        cfg = raw.to_s.empty? ? {} : (JSON.parse(raw) rescue {})
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
        { has_furniture: !data.nil?, name: data && data['furniture_name'], size: data && sheet::Model.summary(data) }
      rescue StandardError => e
        { has_furniture: false, error: e.message }
      end

      # 구성 + 모델 → DXF 파일. 반환: Builder.export 결과
      def export(model, cfg, path, only_ids: nil)
        data = model_data(model, furniture_name: cfg['furniture_name'].to_s.empty? ? nil : cfg['furniture_name']) || placeholder_model
        sheet::Builder.export(cfg, data, path, only_ids: only_ids)
      end

      def image_file?(path)
        IMAGE_EXTS.include?(File.extname(path.to_s).downcase)
      end

      # 폴더 안 이미지(이름순)
      def images_in(dir)
        Dir.children(dir).select { |f| image_file?(f) }.sort.map { |f| File.join(dir, f) }
      end
    end
  end
end
