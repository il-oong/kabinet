require 'fileutils'
require 'json'
require 'securerandom'
require 'time'

module Kabinet
  # User-owned files live outside the extension so RBZ updates cannot erase them.
  module FurnitureLibrary
    module_function

    def root
      File.join(ENV['LOCALAPPDATA'] || File.join(Dir.home, 'Library', 'Application Support'), 'Kabinet', 'FurnitureLibrary')
    end

    def entry_dir(id, directory = root)
      raise ArgumentError, '저장 가구를 찾을 수 없습니다.' unless /\A[0-9a-f]{32}\z/.match?(id.to_s)
      File.join(directory, id)
    end

    def list(directory: root)
      return [] unless Dir.exist?(directory)
      Dir.children(directory).filter_map do |id|
        next unless /\A[0-9a-f]{32}\z/.match?(id)
        folder = entry_dir(id, directory)
        next unless File.file?(File.join(folder, 'furniture.skp'))
        begin
          data = JSON.parse(File.read(File.join(folder, 'info.json'), encoding: 'UTF-8'))
          next unless data['name'].is_a?(String) && data['saved_at'].is_a?(String)
          { id: id, name: data['name'], saved_at: data['saved_at'], dimensions_mm: data['dimensions_mm'] }
        rescue JSON::ParserError, SystemCallError
          # A damaged entry must not prevent the remaining library from opening.
          next
        end
      end.sort_by { |entry| entry[:saved_at] }.reverse
    end

    def save(name, model: Sketchup.active_model, directory: root)
      name = name.to_s.strip
      raise ArgumentError, '저장할 가구 이름을 입력하세요. (최대 60자)' if name.empty? || name.length > 60
      raise '그룹 편집을 닫고 저장할 가구를 선택하세요.' if model.active_path
      targets = model.selection.to_a
      unless !targets.empty? && targets.all? { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        raise '저장할 판재 또는 가구 그룹/컴포넌트만 선택하세요.'
      end
      bounds = Geom::BoundingBox.new
      targets.each { |e| bounds.add(e.bounds) }
      raise '비어 있는 가구는 저장할 수 없습니다.' unless bounds.valid? && bounds.diagonal > 0
      id = SecureRandom.hex(16)
      FileUtils.mkdir_p(directory)
      staging = File.join(directory, ".saving-#{id}")
      FileUtils.mkdir_p(staging)
      begin
        saved_front = Output::FurnitureSheet.front_axis(targets)
        model.start_operation('가구 보관함 저장용 복사', true)
        begin
          container = model.entities.add_group
          container.name = name
          # Library geometry is normalized by translation only, so its local
          # front vector can follow a placed instance when the user rotates it.
          Output::FurnitureSheet.save_front(container, saved_front)
          container.definition.set_attribute('kabinet_ep', 'front_local', container.get_attribute('kabinet_ep', 'front_local'))
          move = Geom::Transformation.translation(ORIGIN - bounds.min)
          targets.each do |entity|
            copy = container.entities.add_instance(entity.definition, move * entity.transformation)
            copy.name = entity.name
            copy.material = entity.material if entity.material
            copy.hidden = entity.hidden?
          end
          path = File.join(staging, 'furniture.skp')
          raise '가구 파일을 저장하지 못했습니다.' unless container.definition.save_as(path)
        ensure
          model.abort_operation
          model.selection.clear
          targets.each { |e| model.selection.add(e) if e.valid? }
        end
        data = { name: name, saved_at: Time.now.iso8601,
                 dimensions_mm: [bounds.width, bounds.height, bounds.depth].map { |v| v.to_mm.round(2) } }
        File.write(File.join(staging, 'info.json'), JSON.pretty_generate(data), encoding: 'UTF-8')
        File.rename(staging, entry_dir(id, directory))
        id
      ensure
        # Only this operation's generated staging directory may be removed.
        FileUtils.remove_entry(staging) if Dir.exist?(staging)
      end
    end

    def definition(id, model: Sketchup.active_model, directory: root)
      path = File.join(entry_dir(id, directory), 'furniture.skp')
      raise '저장한 가구 파일이 없습니다. 보관함 폴더를 확인하세요.' unless File.file?(path)
      model.definitions.load(path)
    end

    def place(id, model: Sketchup.active_model)
      raise '그룹 편집을 닫고 저장 가구를 불러오세요.' if model.active_path
      item = definition(id, model: model)
      raise '가구를 불러오지 못했습니다.' unless item
      # Native placement follows the cursor and supports SketchUp inference/Esc.
      model.place_component(item, false)
    end
  end
end
